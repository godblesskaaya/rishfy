import * as grpc from '@grpc/grpc-js';
import * as protoLoader from '@grpc/proto-loader';
import * as path from 'path';

import { config } from '../config.js';
import { logger } from '../logger.js';

const PROTO_PATH = path.resolve(process.cwd(), 'shared/protos/location.proto');

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
    const grpcObj = grpc.loadPackageDefinition(packageDef) as Record<string, unknown>;
    const pkg = ((grpcObj.rishfy as Record<string, unknown>).location as Record<string, unknown>)
      .v1 as Record<string, grpc.ServiceClientConstructor>;
    const LocationService = pkg.LocationService;
    if (!LocationService) {
      throw new Error('LocationService gRPC def not found');
    }
    instance = new LocationService(
      config.LOCATION_SERVICE_GRPC_URL,
      grpc.credentials.createInsecure(),
    );
  }
  return instance;
}

type GrpcClientMethod<T> = (
  req: unknown,
  cb: (err: grpc.ServiceError | null, res: T) => void,
) => void;

function callUnary<T>(method: string, req: Record<string, unknown>): Promise<T> {
  return new Promise((resolve, reject) => {
    const client = getClient() as unknown as Record<string, GrpcClientMethod<T>>;
    const fn = client[method];
    if (!fn) {
      reject(new Error(`gRPC method ${method} not found`));
      return;
    }
    fn.call(client, req, (err, res) => {
      if (err) reject(err);
      else resolve(res);
    });
  });
}

interface StartTripGrpcResponse {
  trip?: {
    tripId?: string;
    trip_id?: string;
  };
}

export async function startTrackedTrip(params: {
  bookingId: string;
  routeId: string;
  driverUserId: string;
  startLat: number;
  startLng: number;
  destinationLat?: number;
  destinationLng?: number;
}): Promise<string | null> {
  try {
    const response = await callUnary<StartTripGrpcResponse>('startTrip', {
      bookingId: params.bookingId,
      routeId: params.routeId,
      driverUserId: params.driverUserId,
      startLocation: {
        latitude: params.startLat,
        longitude: params.startLng,
      },
      destinationLocation:
        params.destinationLat != null && params.destinationLng != null
            ? {
                latitude: params.destinationLat,
                longitude: params.destinationLng,
              }
            : undefined,
    });
    return response.trip?.tripId ?? response.trip?.trip_id ?? null;
  } catch (err) {
    logger.warn({ err, bookingId: params.bookingId }, 'startTrackedTrip gRPC failed');
    return null;
  }
}

export async function completeTrackedTrip(params: {
  tripId: string;
  endLat: number;
  endLng: number;
}): Promise<void> {
  try {
    await callUnary('completeTrip', {
      tripId: params.tripId,
      endLocation: {
        latitude: params.endLat,
        longitude: params.endLng,
      },
      endTime: {
        seconds: String(Math.floor(Date.now() / 1000)),
      },
    });
  } catch (err) {
    logger.warn({ err, tripId: params.tripId }, 'completeTrackedTrip gRPC failed');
  }
}
