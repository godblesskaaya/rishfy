import * as grpc from '@grpc/grpc-js';
import * as protoLoader from '@grpc/proto-loader';
import * as path from 'path';
import { config } from '../config.js';
import { logger } from '../logger.js';
import { RouteRepository } from '../repositories/route.repository.js';
import { pgPool } from '../db.js';

const PROTO_PATH = path.resolve(process.cwd(), 'shared/protos/route.proto');

const packageDef = protoLoader.loadSync(PROTO_PATH, {
  keepCase: false,
  longs: String,
  enums: String,
  defaults: true,
  oneofs: true,
  includeDirs: [path.resolve(process.cwd(), 'shared/protos')],
});

const grpcObject = grpc.loadPackageDefinition(packageDef) as Record<string, unknown>;
const pkg = (grpcObject['rishfy'] as Record<string, unknown>)['route'] as Record<string, unknown>;
const RouteServiceDef = (pkg['v1'] as Record<string, unknown>)['RouteService'] as { service: grpc.ServiceDefinition };

const repo = new RouteRepository(pgPool);

type Handler<Req, Res> = grpc.handleUnaryCall<Req, Res>;

interface ReserveSeatsReq { routeId: string; seatCount: number; bookingId: string; timeoutSeconds: number }
interface ReserveSeatsRes { success: boolean; seatsRemaining: number; reservationId: string; failureReason: string }
interface ReleaseSeatsReq { reservationId: string; bookingId: string; reason: string }
interface ReleaseSeatsRes { success: boolean; seatsRemaining: number }
interface GetAvailabilityReq { routeId: string }
interface GetAvailabilityRes { totalSeats: number; availableSeats: number; pendingReservations: number }

const reserveSeats: Handler<ReserveSeatsReq, ReserveSeatsRes> = async (call, callback) => {
  try {
    const { routeId, seatCount, bookingId } = call.request;
    const result = await repo.reserveSeats(routeId, seatCount, bookingId);
    callback(null, {
      success: result.success,
      seatsRemaining: result.seatsRemaining,
      reservationId: bookingId,
      failureReason: result.failureReason ?? '',
    });
  } catch (err) {
    logger.error({ err }, 'reserveSeats gRPC error');
    callback({ code: grpc.status.INTERNAL, message: 'internal error' } as grpc.ServiceError);
  }
};

const releaseSeats: Handler<ReleaseSeatsReq, ReleaseSeatsRes> = async (call, callback) => {
  try {
    const { bookingId } = call.request;
    const route = await repo.findById(bookingId);
    if (!route) {
      callback(null, { success: false, seatsRemaining: 0 });
      return;
    }
    const result = await repo.releaseSeats(route.id, 1);
    callback(null, { success: result.success, seatsRemaining: result.seatsRemaining });
  } catch (err) {
    logger.error({ err }, 'releaseSeats gRPC error');
    callback({ code: grpc.status.INTERNAL, message: 'internal error' } as grpc.ServiceError);
  }
};

const getRouteAvailability: Handler<GetAvailabilityReq, GetAvailabilityRes> = async (call, callback) => {
  try {
    const route = await repo.findById(call.request.routeId);
    if (!route) {
      callback({ code: grpc.status.NOT_FOUND, message: 'route not found' } as grpc.ServiceError);
      return;
    }
    callback(null, {
      totalSeats: route.available_seats,
      availableSeats: route.available_seats - route.booked_seats,
      pendingReservations: 0,
    });
  } catch (err) {
    logger.error({ err }, 'getRouteAvailability gRPC error');
    callback({ code: grpc.status.INTERNAL, message: 'internal error' } as grpc.ServiceError);
  }
};

export function startGrpcServer(): grpc.Server {
  const server = new grpc.Server();
  server.addService(RouteServiceDef.service, {
    reserveSeats,
    releaseSeats,
    getRouteAvailability,
    getRoute: (_call: grpc.ServerUnaryCall<unknown, unknown>, callback: grpc.sendUnaryData<unknown>) =>
      callback({ code: grpc.status.UNIMPLEMENTED } as grpc.ServiceError),
    getRoutesBatch: (_call: grpc.ServerUnaryCall<unknown, unknown>, callback: grpc.sendUnaryData<unknown>) =>
      callback({ code: grpc.status.UNIMPLEMENTED } as grpc.ServiceError),
    searchRoutes: (_call: grpc.ServerUnaryCall<unknown, unknown>, callback: grpc.sendUnaryData<unknown>) =>
      callback({ code: grpc.status.UNIMPLEMENTED } as grpc.ServiceError),
    listDriverRoutes: (_call: grpc.ServerUnaryCall<unknown, unknown>, callback: grpc.sendUnaryData<unknown>) =>
      callback({ code: grpc.status.UNIMPLEMENTED } as grpc.ServiceError),
  });

  server.bindAsync(
    `0.0.0.0:${config.GRPC_PORT}`,
    grpc.ServerCredentials.createInsecure(),
    (err, port) => {
      if (err) { logger.error({ err }, 'gRPC bind failed'); process.exit(1); }
      logger.info({ port }, 'route-service gRPC server listening');
    },
  );

  return server;
}
