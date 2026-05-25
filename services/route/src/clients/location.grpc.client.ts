import * as grpc from '@grpc/grpc-js';
import * as protoLoader from '@grpc/proto-loader';
import * as path from 'path';

import { config } from '../config.js';
import { logger } from '../logger.js';

const PROTO_PATH = path.resolve(process.cwd(), 'shared/protos/location.proto');

interface StartTripResponse {
  trip?: {
    tripId?: string;
    trip_id?: string;
    routeRunId?: string;
    route_run_id?: string;
  };
}

interface CompleteTripResponse {
  trip?: {
    tripId?: string;
    trip_id?: string;
    routeRunId?: string;
    route_run_id?: string;
  };
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
    const pkg = (grpcObject['rishfy'] as Record<string, unknown>)['location'] as Record<string, unknown>;
    const LocationService = (pkg['v1'] as Record<string, grpc.ServiceClientConstructor>)['LocationService'];
    if (!LocationService) {
      throw new Error('Failed to load LocationService gRPC client definition');
    }
    instance = new LocationService(
      config.LOCATION_SERVICE_GRPC_URL,
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

export async function startTrackedRouteRun(params: {
  routeRunId: string;
  routeId: string;
  driverUserId: string;
  originLat: number;
  originLng: number;
  destinationLat: number;
  destinationLng: number;
}): Promise<string | null> {
  try {
    const response = await callUnary<StartTripResponse>('startTrip', {
      routeRunId: params.routeRunId,
      routeId: params.routeId,
      driverUserId: params.driverUserId,
      startLocation: {
        latitude: params.originLat,
        longitude: params.originLng,
      },
      destinationLocation: {
        latitude: params.destinationLat,
        longitude: params.destinationLng,
      },
    });
    return response.trip?.tripId ?? response.trip?.trip_id ?? null;
  } catch (err) {
    logger.warn({ err, routeRunId: params.routeRunId }, 'startTrackedRouteRun gRPC failed');
    return null;
  }
}

export async function completeTrackedRouteRun(params: {
  routeRunId: string;
  endLat: number;
  endLng: number;
}): Promise<string | null> {
  try {
    const response = await callUnary<CompleteTripResponse>('completeTrip', {
      routeRunId: params.routeRunId,
      endLocation: {
        latitude: params.endLat,
        longitude: params.endLng,
      },
      endTime: {
        seconds: String(Math.floor(Date.now() / 1000)),
      },
    });
    return response.trip?.tripId ?? response.trip?.trip_id ?? null;
  } catch (err) {
    logger.warn({ err, routeRunId: params.routeRunId }, 'completeTrackedRouteRun gRPC failed');
    return null;
  }
}
