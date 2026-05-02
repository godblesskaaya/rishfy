import * as grpc from '@grpc/grpc-js';
import * as protoLoader from '@grpc/proto-loader';
import * as path from 'path';
import { config } from '../config.js';
import { logger } from '../logger.js';

const PROTO_PATH = path.resolve(process.cwd(), 'shared/protos/route.proto');

let _instance: grpc.Client | null = null;

function getClient(): grpc.Client {
  if (!_instance) {
    const packageDef = protoLoader.loadSync(PROTO_PATH, {
      keepCase: false, longs: String, enums: String, defaults: true, oneofs: true,
      includeDirs: [path.resolve(process.cwd(), 'shared/protos')],
    });
    const grpcObj = grpc.loadPackageDefinition(packageDef) as Record<string, unknown>;
    const pkg = ((grpcObj['rishfy'] as Record<string, unknown>)['route'] as Record<string, unknown>)['v1'] as Record<string, grpc.ServiceClientConstructor>;
    const RouteService = pkg['RouteService'];
    if (!RouteService) throw new Error('RouteService gRPC def not found');
    _instance = new RouteService(config.ROUTE_SERVICE_GRPC_URL, grpc.credentials.createInsecure());
  }
  return _instance;
}

type GrpcClientMethod<T> = (req: unknown, cb: (err: grpc.ServiceError | null, res: T) => void) => void;

function callUnary<T>(method: string, req: Record<string, unknown>): Promise<T> {
  return new Promise((resolve, reject) => {
    const client = getClient() as unknown as Record<string, GrpcClientMethod<T>>;
    const fn = client[method];
    if (!fn) return reject(new Error(`gRPC method ${method} not found`));
    fn(req, (err, res) => { if (err) reject(err); else resolve(res); });
  });
}

export interface ReserveSeatsResult { success: boolean; seatsRemaining: number; reservationId: string; failureReason: string }

export async function reserveSeats(routeId: string, seatCount: number, bookingId: string): Promise<ReserveSeatsResult> {
  try {
    return await callUnary<ReserveSeatsResult>('reserveSeats', { routeId, seatCount, bookingId, timeoutSeconds: 120 });
  } catch (err) {
    logger.warn({ err, routeId }, 'reserveSeats gRPC failed');
    return { success: false, seatsRemaining: 0, reservationId: '', failureReason: 'ROUTE_SERVICE_UNAVAILABLE' };
  }
}

export async function releaseSeats(bookingId: string, reason: string): Promise<void> {
  try {
    await callUnary('releaseSeats', { reservationId: bookingId, bookingId, reason });
  } catch (err) {
    logger.warn({ err, bookingId }, 'releaseSeats gRPC failed');
  }
}
