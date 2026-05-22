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

function toTimestamp(date: Date | null): Record<string, unknown> | null {
  if (!date) return null;
  return { seconds: String(Math.floor(date.getTime() / 1000)) };
}

function mapBookingStatus(status: BookingRow['status']): string {
  switch (status) {
    case 'pending':
      return 'BOOKING_STATUS_PENDING';
    case 'confirmed':
      return 'BOOKING_STATUS_CONFIRMED';
    case 'completed':
      return 'BOOKING_STATUS_COMPLETED';
    case 'no_show':
      return 'BOOKING_STATUS_NO_SHOW';
    default:
      return 'BOOKING_STATUS_CANCELLED';
  }
}

function mapTripStatus(booking: BookingRow): string {
  switch (booking.journey_state) {
    case 'boarded':
    case 'in_transit':
    case 'dropped_off':
    case 'walking_to_destination':
      return 'TRIP_STATUS_IN_PROGRESS';
    case 'completed':
      return 'TRIP_STATUS_COMPLETED';
    case 'cancelled':
    case 'no_show':
      return 'TRIP_STATUS_CANCELLED';
    default:
      return 'TRIP_STATUS_SCHEDULED';
  }
}

function mapJourneyState(journeyState: BookingRow['journey_state']): string {
  switch (journeyState) {
    case 'confirmed':
      return 'JOURNEY_STATE_CONFIRMED';
    case 'driver_approaching':
      return 'JOURNEY_STATE_DRIVER_APPROACHING';
    case 'driver_arrived':
      return 'JOURNEY_STATE_DRIVER_ARRIVED';
    case 'boarded':
    case 'in_transit':
      return 'JOURNEY_STATE_IN_TRANSIT';
    case 'dropped_off':
      return 'JOURNEY_STATE_DROPPED_OFF';
    case 'walking_to_destination':
      return 'JOURNEY_STATE_WALKING_TO_DESTINATION';
    case 'completed':
      return 'JOURNEY_STATE_COMPLETED';
    case 'cancelled':
      return 'JOURNEY_STATE_CANCELLED';
    case 'no_show':
      return 'JOURNEY_STATE_NO_SHOW';
    default:
      return 'JOURNEY_STATE_UNSPECIFIED';
  }
}

function toServiceError(err: unknown): grpc.ServiceError {
  const code = (err as { code?: string } | null)?.code;
  switch (code) {
    case 'NOT_FOUND':
      return { code: grpc.status.NOT_FOUND, message: String(err) } as grpc.ServiceError;
    case 'FORBIDDEN':
      return { code: grpc.status.PERMISSION_DENIED, message: String(err) } as grpc.ServiceError;
    case 'INVALID_STATE':
    case 'CANNOT_DECLINE':
      return { code: grpc.status.FAILED_PRECONDITION, message: String(err) } as grpc.ServiceError;
    default:
      return { code: grpc.status.INTERNAL, message: String(err) } as grpc.ServiceError;
  }
}

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
    status: mapBookingStatus(b.status),
    tripStatus: mapTripStatus(b),
    journeyState: mapJourneyState(b.journey_state),
    pickupCoordinates: b.pickup_lat ? { latitude: b.pickup_lat, longitude: b.pickup_lng } : null,
    dropoffCoordinates: b.dropoff_lat ? { latitude: b.dropoff_lat, longitude: b.dropoff_lng } : null,
    passengerRating: b.passenger_rating ?? 0,
    driverRating: b.driver_rating ?? 0,
    paymentId: b.payment_id ?? '',
    tripId: b.trip_id ?? '',
    createdAt: toTimestamp(b.created_at),
    confirmedAt: toTimestamp(b.confirmed_at),
    cancelledAt: toTimestamp(b.cancelled_at),
    tripStartedAt: toTimestamp(b.trip_started_at),
    tripCompletedAt: toTimestamp(b.trip_completed_at),
    arrivedPickupAt: toTimestamp(b.arrived_pickup_at),
    boardedAt: toTimestamp(b.boarded_at),
    droppedOffAt: toTimestamp(b.dropped_off_at),
    journeyCompletedAt: toTimestamp(b.journey_completed_at),
    noShowAt: toTimestamp(b.no_show_at),
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
interface ArrivePickupReq { bookingId: string; driverUserId: string }
interface BoardPassengerReq { bookingId: string; driverUserId: string }
interface DropoffPassengerReq { bookingId: string; driverUserId: string }
interface MarkNoShowReq { bookingId: string; driverUserId: string; reason: string }
interface CompleteJourneyReq { bookingId: string; actorUserId: string }
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
    const result = await svc.cancelByPassengerWithRefund(call.request.bookingId, call.request.cancellingUserId, call.request.reason);
    if (!result.booking) {
      callback({ code: grpc.status.NOT_FOUND, message: 'booking not found or not cancellable' } as grpc.ServiceError);
      return;
    }
    callback(null, {
      booking: rowToProto(result.booking),
      refundAmount: { amountTzs: String(result.refund.refundedAmountTzs) },
      refundReference: result.refund.refundReference,
    });
  } catch (err) {
    callback(toServiceError(err));
  }
};

const confirmBooking: Handler<ConfirmReq, unknown> = async (call, callback) => {
  try {
    const booking = await svc.confirmBooking(call.request.bookingId, call.request.paymentId);
    callback(null, { booking: rowToProto(booking) });
  } catch (err) {
    callback(toServiceError(err));
  }
};

const startTrip: Handler<StartTripReq, unknown> = async (call, callback) => {
  try {
    const booking = await svc.startTrip(call.request.bookingId, call.request.driverUserId);
    if (!booking) {
      callback({ code: grpc.status.FAILED_PRECONDITION, message: 'booking not in confirmable state' } as grpc.ServiceError);
      return;
    }
    callback(null, { booking: rowToProto(booking), tripId: booking.trip_id ?? '' });
  } catch (err) {
    callback(toServiceError(err));
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
    callback(toServiceError(err));
  }
};

const arrivePickup: Handler<ArrivePickupReq, unknown> = async (call, callback) => {
  try {
    const booking = await svc.arrivePickup(call.request.bookingId, call.request.driverUserId);
    callback(null, { booking: rowToProto(booking) });
  } catch (err) {
    callback(toServiceError(err));
  }
};

const boardPassenger: Handler<BoardPassengerReq, unknown> = async (call, callback) => {
  try {
    const booking = await svc.boardPassenger(call.request.bookingId, call.request.driverUserId);
    callback(null, { booking: rowToProto(booking), tripId: booking.trip_id ?? '' });
  } catch (err) {
    callback(toServiceError(err));
  }
};

const dropoffPassenger: Handler<DropoffPassengerReq, unknown> = async (call, callback) => {
  try {
    const booking = await svc.dropoffPassenger(call.request.bookingId, call.request.driverUserId);
    callback(null, { booking: rowToProto(booking), tripId: booking.trip_id ?? '' });
  } catch (err) {
    callback(toServiceError(err));
  }
};

const markNoShow: Handler<MarkNoShowReq, unknown> = async (call, callback) => {
  try {
    const booking = await svc.markNoShow(call.request.bookingId, call.request.driverUserId, call.request.reason);
    callback(null, { booking: rowToProto(booking) });
  } catch (err) {
    callback(toServiceError(err));
  }
};

const completeJourney: Handler<CompleteJourneyReq, unknown> = async (call, callback) => {
  try {
    const booking = await svc.completeJourney(call.request.bookingId, call.request.actorUserId);
    callback(null, { booking: rowToProto(booking) });
  } catch (err) {
    callback(toServiceError(err));
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
    callback(toServiceError(err));
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
    arrivePickup,
    boardPassenger,
    dropoffPassenger,
    markNoShow,
    completeJourney,
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
