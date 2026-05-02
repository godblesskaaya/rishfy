import * as grpc from '@grpc/grpc-js';
import * as protoLoader from '@grpc/proto-loader';
import * as path from 'path';
import { config } from '../config.js';
import { logger } from '../logger.js';
import { LocationRepository } from '../repositories/location.repository.js';
import { GeoService } from '../services/geo.service.js';
import { pgPool } from '../db.js';
import IORedis from 'ioredis';
import type { TripRow } from '../repositories/location.repository.js';

const PROTO_PATH = path.resolve(process.cwd(), 'shared/protos/location.proto');

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
const LocationServiceDef = (pkg['v1'] as Record<string, unknown>)['LocationService'] as { service: grpc.ServiceDefinition };

const repo = new LocationRepository(pgPool);
const redis = new IORedis(config.REDIS_URL, { maxRetriesPerRequest: null });
const geoSvc = new GeoService(redis);

type Handler<Req, Res> = grpc.handleUnaryCall<Req, Res>;

function tripToProto(t: TripRow): Record<string, unknown> {
  return {
    tripId: t.id,
    bookingId: t.booking_id,
    driverUserId: t.driver_id,
    status: (t.status ?? 'pending').toUpperCase(),
    startLocation: { latitude: t.origin_lat, longitude: t.origin_lng },
    endLocation: t.destination_lat ? { latitude: t.destination_lat, longitude: t.destination_lng } : null,
    startTime: t.started_at ? { seconds: String(Math.floor(t.started_at.getTime() / 1000)) } : null,
    endTime: t.completed_at ? { seconds: String(Math.floor(t.completed_at.getTime() / 1000)) } : null,
    distanceMeters: t.total_distance_meters ?? 0,
    durationSeconds: t.total_duration_seconds ?? 0,
  };
}

interface StartTripReq {
  bookingId: string; routeId: string; driverUserId: string;
  startLocation: { latitude: number; longitude: number };
}
interface RecordLocationReq {
  tripId: string; driverUserId: string;
  point: { coordinates: { latitude: number; longitude: number }; speedMps: number; headingDegrees: number; accuracyMeters: number; recordedAt: { seconds: string } };
}
interface RecordBatchReq {
  tripId: string; driverUserId: string;
  points: Array<{ coordinates: { latitude: number; longitude: number }; accuracyMeters: number; recordedAt: { seconds: string } }>;
}
interface GetDriverLocationReq { driverUserId: string; maxAgeSeconds: number }
interface GetDriversLocationsReq { driverUserIds: string[] }
interface GetTripTraceReq { tripId: string }
interface CompleteTripReq { tripId: string; endLocation: { latitude: number; longitude: number }; endTime: { seconds: string } }
interface EstimateETAReq {
  origin: { latitude: number; longitude: number };
  destination: { latitude: number; longitude: number };
}

const startTrip: Handler<StartTripReq, unknown> = async (call, callback) => {
  try {
    const { bookingId, driverUserId, startLocation } = call.request;
    const trip = await repo.createTrip({
      bookingId, driverId: driverUserId, passengerId: '',
      originLat: startLocation.latitude, originLng: startLocation.longitude,
      destinationLat: 0, destinationLng: 0,
    });
    const started = await repo.startTrip(bookingId);
    callback(null, { trip: tripToProto(started ?? trip) });
  } catch (err) {
    logger.error({ err }, 'gRPC startTrip error');
    callback({ code: grpc.status.INTERNAL, message: String(err) } as grpc.ServiceError);
  }
};

const recordLocation: Handler<RecordLocationReq, unknown> = async (call, callback) => {
  try {
    const { driverUserId, tripId, point } = call.request;
    const recordedAt = point?.recordedAt?.seconds
      ? new Date(parseInt(point.recordedAt.seconds, 10) * 1000)
      : new Date();

    await repo.insertDriverLocation({
      time: recordedAt,
      driverId: driverUserId,
      tripId: tripId || undefined,
      lat: point?.coordinates?.latitude ?? 0,
      lng: point?.coordinates?.longitude ?? 0,
      bearing: point?.headingDegrees,
      speedKmh: point?.speedMps ? point.speedMps * 3.6 : undefined,
      accuracyMeters: point?.accuracyMeters,
    });

    await geoSvc.updateDriverLocation({ driverId: driverUserId, lat: point?.coordinates?.latitude ?? 0, lng: point?.coordinates?.longitude ?? 0, updatedAt: new Date().toISOString() });

    callback(null, { accepted: true, pointsReceivedThisTrip: 1 });
  } catch (err) {
    callback({ code: grpc.status.INTERNAL, message: String(err) } as grpc.ServiceError);
  }
};

const recordLocationBatch: Handler<RecordBatchReq, unknown> = async (call, callback) => {
  try {
    const { driverUserId, tripId, points } = call.request;
    let accepted = 0;
    for (const point of points ?? []) {
      const recordedAt = point?.recordedAt?.seconds
        ? new Date(parseInt(point.recordedAt.seconds, 10) * 1000)
        : new Date();
      await repo.insertDriverLocation({
        time: recordedAt,
        driverId: driverUserId,
        tripId: tripId || undefined,
        lat: point?.coordinates?.latitude ?? 0,
        lng: point?.coordinates?.longitude ?? 0,
        accuracyMeters: point?.accuracyMeters,
      });
      accepted++;
    }
    const last = points?.[points.length - 1];
    if (last?.coordinates) {
      await geoSvc.updateDriverLocation({ driverId: driverUserId, lat: last.coordinates.latitude, lng: last.coordinates.longitude, updatedAt: new Date().toISOString() });
    }
    callback(null, { acceptedCount: accepted, rejectedCount: 0, rejectionReasons: [] });
  } catch (err) {
    callback({ code: grpc.status.INTERNAL, message: String(err) } as grpc.ServiceError);
  }
};

const getDriverLocation: Handler<GetDriverLocationReq, unknown> = async (call, callback) => {
  try {
    const { driverUserId, maxAgeSeconds } = call.request;
    const threshold = maxAgeSeconds || 60;
    const loc = await geoSvc.getDriverLocation(driverUserId);
    if (!loc) {
      const dbLoc = await repo.getLastKnownLocation(driverUserId);
      if (!dbLoc) {
        callback({ code: grpc.status.NOT_FOUND, message: 'no location found' } as grpc.ServiceError);
        return;
      }
      const ageSeconds = Math.floor((Date.now() - dbLoc.time.getTime()) / 1000);
      callback(null, {
        point: { coordinates: { latitude: dbLoc.lat, longitude: dbLoc.lng }, speedMps: (dbLoc.speedKmh ?? 0) / 3.6, headingDegrees: dbLoc.bearing ?? 0 },
        isStale: ageSeconds > threshold,
        ageSeconds,
      });
      return;
    }
    callback(null, {
      point: { coordinates: { latitude: loc.lat, longitude: loc.lng } },
      isStale: false,
      ageSeconds: 0,
    });
  } catch (err) {
    callback({ code: grpc.status.INTERNAL, message: String(err) } as grpc.ServiceError);
  }
};

const getDriversLocations: Handler<GetDriversLocationsReq, unknown> = async (call, callback) => {
  try {
    const locations = await Promise.all(
      (call.request.driverUserIds ?? []).map(async (id: string) => {
        const loc = await geoSvc.getDriverLocation(id);
        return {
          driverUserId: id,
          point: loc ? { coordinates: { latitude: loc.lat, longitude: loc.lng } } : null,
          isOnline: !!loc,
        };
      }),
    );
    callback(null, { locations });
  } catch (err) {
    callback({ code: grpc.status.INTERNAL, message: String(err) } as grpc.ServiceError);
  }
};

const getTripTrace: Handler<GetTripTraceReq, unknown> = async (call, callback) => {
  try {
    const { tripId } = call.request;
    const points = await repo.getRecentPath(tripId);
    callback(null, {
      trip: null,
      points: points.map((p) => ({
        coordinates: { latitude: p.lat, longitude: p.lng },
        headingDegrees: p.bearing ?? 0,
        recordedAt: { seconds: String(Math.floor(new Date(p.time).getTime() / 1000)) },
      })),
      encodedPolyline: '',
    });
  } catch (err) {
    callback({ code: grpc.status.INTERNAL, message: String(err) } as grpc.ServiceError);
  }
};

const completeTrip: Handler<CompleteTripReq, unknown> = async (call, callback) => {
  try {
    const { tripId } = call.request;
    const points = await repo.getRecentPath(tripId);
    const distanceMeters = points.length > 1 ? points.length * 50 : 0;
    const trip = await repo.completeTrip(tripId, null, distanceMeters);
    if (!trip) {
      callback({ code: grpc.status.NOT_FOUND, message: 'trip not found or not in_progress' } as grpc.ServiceError);
      return;
    }
    callback(null, {
      trip: tripToProto(trip),
      totalDistanceMeters: distanceMeters,
      totalDurationSeconds: trip.total_duration_seconds ?? 0,
      locationPointsRecorded: points.length,
    });
  } catch (err) {
    callback({ code: grpc.status.INTERNAL, message: String(err) } as grpc.ServiceError);
  }
};

const estimateETA: Handler<EstimateETAReq, unknown> = async (call, callback) => {
  try {
    const { origin, destination } = call.request;
    const distMeters = Math.round(geoSvc.haversineDistance(origin.latitude, origin.longitude, destination.latitude, destination.longitude) * 1000);
    const durationSeconds = Math.round(distMeters / 8.3);
    callback(null, { durationSeconds, durationInTrafficSeconds: durationSeconds, distanceMeters: distMeters, cacheSource: 'miss' });
  } catch (err) {
    callback({ code: grpc.status.INTERNAL, message: String(err) } as grpc.ServiceError);
  }
};

export function startGrpcServer(): grpc.Server {
  const server = new grpc.Server();
  server.addService(LocationServiceDef.service, {
    startTrip,
    recordLocation,
    recordLocationBatch,
    getDriverLocation,
    getDriversLocations,
    getTripTrace,
    completeTrip,
    estimateETA,
  });

  server.bindAsync(
    `0.0.0.0:${config.GRPC_PORT}`,
    grpc.ServerCredentials.createInsecure(),
    (err, port) => {
      if (err) { logger.error({ err }, 'gRPC bind failed'); process.exit(1); }
      logger.info({ port }, 'location-service gRPC server listening');
    },
  );

  return server;
}
