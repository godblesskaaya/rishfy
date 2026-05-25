import * as grpc from '@grpc/grpc-js';
import * as protoLoader from '@grpc/proto-loader';
import * as path from 'path';

import { config } from '../config.js';
import { logger } from '../logger.js';

const PROTO_PATH = path.resolve(process.cwd(), 'shared/protos/booking.proto');

interface BookingOperation {
  booking_id: string;
  route_id: string;
  passenger_user_id: string;
  driver_user_id: string;
  seat_count: number;
  pickup_address?: string;
  dropoff_address?: string;
  status: string;
  trip_status: string;
  journey_state: string;
  payment_id: string;
  trip_id: string;
  created_at?: { seconds?: string };
  confirmed_at?: { seconds?: string };
  trip_started_at?: { seconds?: string };
  trip_completed_at?: { seconds?: string };
  arrived_pickup_at?: { seconds?: string };
  boarded_at?: { seconds?: string };
  dropped_off_at?: { seconds?: string };
  journey_completed_at?: { seconds?: string };
  no_show_at?: { seconds?: string };
}

interface ListRouteBookingsResponse {
  bookings: BookingOperation[];
}

let instance: grpc.Client | null = null;

function getClient(): grpc.Client {
  if (!instance) {
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
    const BookingService = (pkg['v1'] as Record<string, grpc.ServiceClientConstructor>)['BookingService'];
    if (!BookingService) {
      throw new Error('Failed to load BookingService gRPC client definition');
    }
    instance = new BookingService(
      config.BOOKING_SERVICE_GRPC_URL,
      grpc.credentials.createInsecure(),
    );
  }
  return instance;
}

type GrpcClientMethod<T> = (req: unknown, cb: (err: grpc.ServiceError | null, res: T) => void) => void;

function callUnary<T>(method: string, request: Record<string, unknown>): Promise<T> {
  return new Promise((resolve, reject) => {
    const client = getClient() as unknown as Record<string, GrpcClientMethod<T>>;
    const fn = client[method];
    if (!fn) return reject(new Error(`gRPC method ${method} not found`));
    fn.call(client, request, (err, res) => {
      if (err) reject(err);
      else resolve(res);
    });
  });
}

export async function listRouteBookings(routeId: string): Promise<BookingOperation[]> {
  try {
    const response = await callUnary<ListRouteBookingsResponse>('listRouteBookings', {
      routeId,
    });
    return response.bookings ?? [];
  } catch (err) {
    logger.warn({ err, routeId }, 'gRPC listRouteBookings failed');
    return [];
  }
}
