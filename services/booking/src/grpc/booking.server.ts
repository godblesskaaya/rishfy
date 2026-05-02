import * as grpc from '@grpc/grpc-js';
import * as protoLoader from '@grpc/proto-loader';
import * as path from 'path';
import { config } from '../config.js';
import { logger } from '../logger.js';
import { BookingRepository } from '../repositories/booking.repository.js';
import { BookingService } from '../services/booking.service.js';
import { pgPool } from '../db.js';
import type { BookingRow } from '../repositories/booking.repository.js';

const PROTO_PATH = path.resolve(process.cwd(), 'shared/protos/booking.proto');

const packageDef = protoLoader.loadSync(PROTO_PATH, {
  keepCase: false,
  longs: String,
  enums: String,
  defaults: true,
  oneofs: true,
  includeDirs: [path.resolve(process.cwd(), 'shared/protos')],
});

const grpcObject = grpc.loadPackageDefinition(packageDef) as Record<string, unknown>;
const pkg = (grpcObject['rishfy'] as Record<string, unknown>)['booking'] as Record<string, unknown>;
const BookingServiceDef = (pkg['v1'] as Record<string, unknown>)['BookingService'] as { service: grpc.ServiceDefinition };

const repo = new BookingRepository(pgPool);
const svc = new BookingService(repo);

type Handler<Req, Res> = grpc.handleUnaryCall<Req, Res>;

function rowToProto(b: BookingRow): Record<string, unknown> {
  return {
    bookingId: b.id,
    confirmationCode: b.confirmation_code ?? '',
    routeId: b.route_id,
    passengerUserId: b.passenger_id,
    driverUserId: b.driver_id,
    seatCount: b.seats_booked,
    totalAmount: { amountTzs: String(b.total_price) },
    driverEarnings: { amountTzs: String(b.driver_earnings) },
    platformFee: { amountTzs: String(b.platform_fee) },
    status: (b.status ?? 'PENDING').toUpperCase(),
    pickupCoordinates: b.pickup_lat ? { latitude: b.pickup_lat, longitude: b.pickup_lng } : null,
    dropoffCoordinates: b.dropoff_lat ? { latitude: b.dropoff_lat, longitude: b.dropoff_lng } : null,
    passengerRating: b.passenger_rating ?? 0,
    driverRating: b.driver_rating ?? 0,
    paymentId: b.payment_id ?? '',
    createdAt: b.created_at ? { seconds: String(Math.floor(b.created_at.getTime() / 1000)) } : null,
    tripStartedAt: b.trip_started_at ? { seconds: String(Math.floor(b.trip_started_at.getTime() / 1000)) } : null,
    tripCompletedAt: b.trip_completed_at ? { seconds: String(Math.floor(b.trip_completed_at.getTime() / 1000)) } : null,
  };
}

interface CreateBookingReq {
  passengerUserId: string; routeId: string; seatCount: number;
  pickupCoordinates: { latitude: number; longitude: number };
  dropoffCoordinates: { latitude: number; longitude: number };
  pickupAddress: string; dropoffAddress: string;
  idempotencyKey: string;
}
interface GetBookingReq { bookingId: string; confirmationCode: string }
interface GetBatchReq { bookingIds: string[] }
interface ListUserReq { userId: string; role: string; pagination: { limit: number } }
interface ListRouteReq { routeId: string }
interface CancelReq { bookingId: string; cancellingUserId: string; reason: string }
interface ConfirmReq { bookingId: string; paymentId: string }
interface StartTripReq { bookingId: string; driverUserId: string; currentLocation: { latitude: number; longitude: number } }
interface CompleteTripReq { bookingId: string; driverUserId: string }
interface RatingReq { bookingId: string; raterUserId: string; rating: number; review: string }

const createBooking: Handler<CreateBookingReq, unknown> = async (call, callback) => {
  try {
    const r = call.request;
    const booking = await svc.createBooking({
      routeId: r.routeId,
      passengerId: r.passengerUserId,
      driverId: '',
      seatsBooked: r.seatCount,
      pricePerSeat: 0,
      pickupLat: r.pickupCoordinates?.latitude,
      pickupLng: r.pickupCoordinates?.longitude,
      dropoffLat: r.dropoffCoordinates?.latitude,
      dropoffLng: r.dropoffCoordinates?.longitude,
      pickupName: r.pickupAddress,
      dropoffName: r.dropoffAddress,
      idempotencyKey: r.idempotencyKey,
    });
    callback(null, { booking: rowToProto(booking) });
  } catch (err) {
    logger.error({ err }, 'gRPC createBooking error');
    const msg = String(err);
    const code = msg.includes('NO_SEATS') ? grpc.status.RESOURCE_EXHAUSTED : grpc.status.INTERNAL;
    callback({ code, message: msg } as grpc.ServiceError);
  }
};

const getBooking: Handler<GetBookingReq, unknown> = async (call, callback) => {
  try {
    const { bookingId, confirmationCode } = call.request;
    const booking = bookingId ? await repo.findById(bookingId) : await repo.findByCode(confirmationCode);
    if (!booking) {
      callback({ code: grpc.status.NOT_FOUND, message: 'booking not found' } as grpc.ServiceError);
      return;
    }
    callback(null, rowToProto(booking));
  } catch (err) {
    callback({ code: grpc.status.INTERNAL, message: String(err) } as grpc.ServiceError);
  }
};

const getBookingsBatch: Handler<GetBatchReq, unknown> = async (call, callback) => {
  try {
    const bookings = await Promise.all(call.request.bookingIds.map((id) => repo.findById(id)));
    callback(null, { bookings: bookings.filter(Boolean).map((b) => rowToProto(b!)) });
  } catch (err) {
    callback({ code: grpc.status.INTERNAL, message: String(err) } as grpc.ServiceError);
  }
};

const listUserBookings: Handler<ListUserReq, unknown> = async (call, callback) => {
  try {
    const { userId, role } = call.request;
    const isDriver = role === 'ROLE_DRIVER';
    const bookings = isDriver
      ? await repo.listByDriver(userId)
      : await repo.listByPassenger(userId);
    callback(null, { bookings: bookings.map(rowToProto), pagination: {} });
  } catch (err) {
    callback({ code: grpc.status.INTERNAL, message: String(err) } as grpc.ServiceError);
  }
};

const listRouteBookings: Handler<ListRouteReq, unknown> = async (call, callback) => {
  try {
    const bookings = await repo.listByRoute(call.request.routeId);
    callback(null, { bookings: bookings.map(rowToProto) });
  } catch (err) {
    callback({ code: grpc.status.INTERNAL, message: String(err) } as grpc.ServiceError);
  }
};

const cancelBooking: Handler<CancelReq, unknown> = async (call, callback) => {
  try {
    const booking = await svc.cancelByPassenger(call.request.bookingId, call.request.cancellingUserId, call.request.reason);
    if (!booking) {
      callback({ code: grpc.status.NOT_FOUND, message: 'booking not found or not cancellable' } as grpc.ServiceError);
      return;
    }
    callback(null, { booking: rowToProto(booking), refundAmount: { amountTzs: '0' }, refundReference: '' });
  } catch (err) {
    callback({ code: grpc.status.INTERNAL, message: String(err) } as grpc.ServiceError);
  }
};

const confirmBooking: Handler<ConfirmReq, unknown> = async (call, callback) => {
  try {
    const booking = await svc.confirmBooking(call.request.bookingId, call.request.paymentId);
    callback(null, { booking: rowToProto(booking) });
  } catch (err) {
    callback({ code: grpc.status.INTERNAL, message: String(err) } as grpc.ServiceError);
  }
};

const startTrip: Handler<StartTripReq, unknown> = async (call, callback) => {
  try {
    const booking = await svc.startTrip(call.request.bookingId, call.request.driverUserId);
    if (!booking) {
      callback({ code: grpc.status.FAILED_PRECONDITION, message: 'booking not in confirmable state' } as grpc.ServiceError);
      return;
    }
    callback(null, { booking: rowToProto(booking), tripId: '' });
  } catch (err) {
    callback({ code: grpc.status.INTERNAL, message: String(err) } as grpc.ServiceError);
  }
};

const completeTrip: Handler<CompleteTripReq, unknown> = async (call, callback) => {
  try {
    const booking = await svc.completeTrip(call.request.bookingId, call.request.driverUserId);
    if (!booking) {
      callback({ code: grpc.status.FAILED_PRECONDITION, message: 'booking not in progress' } as grpc.ServiceError);
      return;
    }
    callback(null, {
      booking: rowToProto(booking),
      settlementAmount: { amountTzs: String(booking.driver_earnings) },
    });
  } catch (err) {
    callback({ code: grpc.status.INTERNAL, message: String(err) } as grpc.ServiceError);
  }
};

const submitRating: Handler<RatingReq, unknown> = async (call, callback) => {
  try {
    const { bookingId, raterUserId, rating, review } = call.request;
    const booking = await svc.submitRating(bookingId, raterUserId, rating, review ?? '');
    if (!booking) {
      callback({ code: grpc.status.NOT_FOUND, message: 'booking not found' } as grpc.ServiceError);
      return;
    }
    const ratingComplete = !!(booking.passenger_rating && booking.driver_rating);
    callback(null, { booking: rowToProto(booking), ratingComplete });
  } catch (err) {
    callback({ code: grpc.status.INTERNAL, message: String(err) } as grpc.ServiceError);
  }
};

const getTripsForLATRAReport: Handler<unknown, unknown> = (_call, callback) => {
  callback({ code: grpc.status.UNIMPLEMENTED, message: 'not implemented' } as grpc.ServiceError);
};

export function startGrpcServer(): grpc.Server {
  const server = new grpc.Server();
  server.addService(BookingServiceDef.service, {
    createBooking,
    getBooking,
    getBookingsBatch,
    listUserBookings,
    listRouteBookings,
    cancelBooking,
    confirmBooking,
    startTrip,
    completeTrip,
    submitRating,
    getTripsForLATRAReport,
  });

  server.bindAsync(
    `0.0.0.0:${config.GRPC_PORT}`,
    grpc.ServerCredentials.createInsecure(),
    (err, port) => {
      if (err) { logger.error({ err }, 'gRPC bind failed'); process.exit(1); }
      logger.info({ port }, 'booking-service gRPC server listening');
    },
  );

  return server;
}
