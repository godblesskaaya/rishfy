import * as grpc from '@grpc/grpc-js';
import * as protoLoader from '@grpc/proto-loader';
import * as path from 'path';
import IORedis from 'ioredis';

import { config } from '../config.js';
import { logger } from '../logger.js';
import { LocationRepository } from '../repositories/location.repository.js';
import { GeoService } from '../services/geo.service.js';
import {
  calculatePathDistanceMeters,
  deriveTripLiveState,
  encodePolyline,
} from '../services/live-trip.service.js';
import { pgPool } from '../db.js';
import type { TripRow } from '../repositories/location.repository.js';
import type { DriverLocation } from '../services/geo.service.js';

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
const pkg = (grpcObject.rishfy as Record<string, unknown>).location as Record<string, unknown>;
const locationV1 = pkg.v1 as Record<string, unknown>;
const LocationServiceDef = locationV1.LocationService as { service: grpc.ServiceDefinition };

const repo = new LocationRepository(pgPool);
const redis = new IORedis(config.REDIS_URL, { maxRetriesPerRequest: null });
const geoSvc = new GeoService(redis);

type Handler<Req, Res> = grpc.handleUnaryCall<Req, Res>;

function toTimestamp(date: Date | null): Record<string, unknown> | null {
  if (!date) return null;
  return { seconds: String(Math.floor(date.getTime() / 1000)) };
}

function tripToProto(trip: TripRow): Record<string, unknown> {
  return {
    tripId: trip.id,
    bookingId: trip.booking_id,
    driverUserId: trip.driver_id,
    status: (trip.status ?? 'pending').toUpperCase(),
    startLocation: { latitude: trip.origin_lat, longitude: trip.origin_lng },
    endLocation: trip.destination_lat
      ? { latitude: trip.destination_lat, longitude: trip.destination_lng }
      : null,
    startTime: toTimestamp(trip.started_at),
    endTime: toTimestamp(trip.completed_at),
    distanceMeters: trip.total_distance_meters ?? 0,
    durationSeconds: trip.total_duration_seconds ?? 0,
    passengerUserId: trip.passenger_id,
  };
}

function buildDriverLocationResponse(args: {
  driverUserId: string;
  point: {
    lat: number;
    lng: number;
    speedKmh?: number | null;
    bearing?: number | null;
    accuracyMeters?: number | null;
    timestampIso?: string;
  };
  trip: TripRow | null;
  liveState: ReturnType<typeof deriveTripLiveState>;
  ageSeconds: number;
  isStale: boolean;
  tripId?: string | null;
}): Record<string, unknown> {
  const { driverUserId, point, trip, liveState, ageSeconds, isStale, tripId } = args;
  return {
    point: {
      coordinates: { latitude: point.lat, longitude: point.lng },
      speedMps: (point.speedKmh ?? 0) / 3.6,
      headingDegrees: point.bearing ?? 0,
      accuracyMeters: point.accuracyMeters ?? 0,
    },
    isStale,
    ageSeconds,
    driverUserId,
    tripId: trip?.id ?? tripId ?? '',
    bookingId: trip?.booking_id ?? '',
    passengerUserId: trip?.passenger_id ?? '',
    etaSeconds: liveState.etaSeconds ?? 0,
    etaSource: liveState.etaSource,
    distanceToActiveStopMeters: liveState.distanceToActiveStopMeters ?? 0,
    proximityState: liveState.proximityState,
    activeStopType: liveState.activeStopType ?? '',
    activeStopLat: liveState.activeStopLat ?? 0,
    activeStopLng: liveState.activeStopLng ?? 0,
    currentRouteFraction: liveState.currentRouteFraction ?? 0,
    activeStopRouteFraction: liveState.activeStopRouteFraction ?? 0,
    remainingRouteFraction: liveState.remainingRouteFraction ?? 0,
    routeGeometrySource: liveState.routeGeometrySource,
    tripStatus: trip?.status ?? '',
    timestamp: point.timestampIso ?? '',
    speedKmh: point.speedKmh ?? 0,
    bearingDegrees: point.bearing ?? 0,
    accuracyMeters: point.accuracyMeters ?? 0,
  };
}

async function getTripContextForCachedLocation(loc: DriverLocation | null): Promise<TripRow | null> {
  if (!loc?.tripId) {
    return null;
  }
  return repo.getTripById(loc.tripId);
}

interface StartTripReq {
  bookingId: string;
  routeId: string;
  driverUserId: string;
  startLocation: { latitude: number; longitude: number };
}

interface RecordLocationReq {
  tripId: string;
  driverUserId: string;
  point: {
    coordinates: { latitude: number; longitude: number };
    speedMps?: number;
    headingDegrees?: number;
    accuracyMeters?: number;
    recordedAt?: { seconds: string };
  };
}

interface RecordBatchReq {
  tripId: string;
  driverUserId: string;
  points: Array<{
    coordinates: { latitude: number; longitude: number };
    speedMps?: number;
    headingDegrees?: number;
    accuracyMeters?: number;
    recordedAt?: { seconds: string };
  }>;
}

interface GetDriverLocationReq {
  driverUserId: string;
  maxAgeSeconds: number;
}

interface GetDriversLocationsReq {
  driverUserIds: string[];
}

interface GetTripTraceReq {
  tripId: string;
}

interface CompleteTripReq {
  tripId: string;
  endLocation: { latitude: number; longitude: number };
  endTime: { seconds: string };
}

interface EstimateETAReq {
  origin: { latitude: number; longitude: number };
  destination: { latitude: number; longitude: number };
}

const startTrip: Handler<StartTripReq, unknown> = async (call, callback) => {
  try {
    const { bookingId, driverUserId, startLocation } = call.request;
    let trip = await repo.getTripByBookingId(bookingId);
    if (!trip) {
      trip = await repo.createTrip({
        bookingId,
        driverId: driverUserId,
        passengerId: '',
        originLat: startLocation.latitude,
        originLng: startLocation.longitude,
        destinationLat: startLocation.latitude,
        destinationLng: startLocation.longitude,
      });
    }
    const started = await repo.startTripById(trip.id);
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

    const trip = tripId ? await repo.getTripById(tripId) : null;
    const liveState = deriveTripLiveState(
      trip,
      {
        lat: point?.coordinates?.latitude ?? 0,
        lng: point?.coordinates?.longitude ?? 0,
        speedKmh: point?.speedMps ? point.speedMps * 3.6 : undefined,
      },
      config.ARRIVAL_RADIUS_METERS,
    );

    await geoSvc.updateDriverLocation({
      driverId: driverUserId,
      tripId: trip?.id,
      bookingId: trip?.booking_id,
      passengerId: trip?.passenger_id,
      lat: point?.coordinates?.latitude ?? 0,
      lng: point?.coordinates?.longitude ?? 0,
      bearing: point?.headingDegrees,
      speedKmh: point?.speedMps ? point.speedMps * 3.6 : undefined,
      accuracyMeters: point?.accuracyMeters,
      timestamp: recordedAt.toISOString(),
      activeStopType: liveState.activeStopType,
      activeStopLat: liveState.activeStopLat,
      activeStopLng: liveState.activeStopLng,
      distanceToActiveStopMeters: liveState.distanceToActiveStopMeters,
      proximityState: liveState.proximityState,
      etaSeconds: liveState.etaSeconds,
      etaSource: liveState.etaSource,
      updatedAt: recordedAt.toISOString(),
    });

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
        bearing: point?.headingDegrees,
        speedKmh: point?.speedMps ? point.speedMps * 3.6 : undefined,
        accuracyMeters: point?.accuracyMeters,
      });
      accepted++;
    }

    const last = points?.[points.length - 1];
    const trip = tripId ? await repo.getTripById(tripId) : null;
    if (last?.coordinates) {
      const liveState = deriveTripLiveState(
        trip,
        {
          lat: last.coordinates.latitude,
          lng: last.coordinates.longitude,
          speedKmh: last.speedMps ? last.speedMps * 3.6 : undefined,
        },
        config.ARRIVAL_RADIUS_METERS,
      );

      await geoSvc.updateDriverLocation({
        driverId: driverUserId,
        tripId: trip?.id,
        bookingId: trip?.booking_id,
        passengerId: trip?.passenger_id,
        lat: last.coordinates.latitude,
        lng: last.coordinates.longitude,
        bearing: last.headingDegrees,
        speedKmh: last.speedMps ? last.speedMps * 3.6 : undefined,
        accuracyMeters: last.accuracyMeters,
        timestamp: new Date().toISOString(),
        activeStopType: liveState.activeStopType,
        activeStopLat: liveState.activeStopLat,
        activeStopLng: liveState.activeStopLng,
        distanceToActiveStopMeters: liveState.distanceToActiveStopMeters,
        proximityState: liveState.proximityState,
        etaSeconds: liveState.etaSeconds,
        etaSource: liveState.etaSource,
        updatedAt: new Date().toISOString(),
      });
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
      const trip = dbLoc.tripId ? await repo.getTripById(dbLoc.tripId) : null;
      const liveState = deriveTripLiveState(
        trip,
        { lat: dbLoc.lat, lng: dbLoc.lng, speedKmh: dbLoc.speedKmh },
        config.ARRIVAL_RADIUS_METERS,
      );
      callback(null, buildDriverLocationResponse({
        driverUserId,
        point: {
          lat: dbLoc.lat,
          lng: dbLoc.lng,
          speedKmh: dbLoc.speedKmh,
          bearing: dbLoc.bearing,
          accuracyMeters: dbLoc.accuracyMeters,
          timestampIso: dbLoc.time.toISOString(),
        },
        trip,
        liveState,
        ageSeconds,
        isStale: ageSeconds > threshold,
        tripId: dbLoc.tripId ?? null,
      }));
      return;
    }
    const trip = await getTripContextForCachedLocation(loc);
    const liveState = deriveTripLiveState(
      trip,
      { lat: loc.lat, lng: loc.lng, speedKmh: loc.speedKmh },
      config.ARRIVAL_RADIUS_METERS,
    );
    callback(null, buildDriverLocationResponse({
      driverUserId,
      point: {
        lat: loc.lat,
        lng: loc.lng,
        speedKmh: loc.speedKmh,
        bearing: loc.bearing,
        accuracyMeters: loc.accuracyMeters,
        timestampIso: loc.timestamp,
      },
      trip,
      liveState,
      ageSeconds: 0,
      isStale: false,
      tripId: loc.tripId ?? null,
    }));
  } catch (err) {
    callback({ code: grpc.status.INTERNAL, message: String(err) } as grpc.ServiceError);
  }
};

const getDriversLocations: Handler<GetDriversLocationsReq, unknown> = async (call, callback) => {
  try {
    const locations = await Promise.all(
      (call.request.driverUserIds ?? []).map(async (id: string) => {
        const loc = await geoSvc.getDriverLocation(id);
        const trip = await getTripContextForCachedLocation(loc);
        const liveState = loc
          ? deriveTripLiveState(
              trip,
              { lat: loc.lat, lng: loc.lng, speedKmh: loc.speedKmh },
              config.ARRIVAL_RADIUS_METERS,
            )
          : null;
        return {
          driverUserId: id,
          point: loc
            ? {
                coordinates: { latitude: loc.lat, longitude: loc.lng },
                speedMps: (loc.speedKmh ?? 0) / 3.6,
                headingDegrees: loc.bearing ?? 0,
                accuracyMeters: loc.accuracyMeters ?? 0,
              }
            : null,
          isOnline: !!loc,
          tripId: trip?.id ?? loc?.tripId ?? '',
          bookingId: trip?.booking_id ?? loc?.bookingId ?? '',
          passengerUserId: trip?.passenger_id ?? loc?.passengerId ?? '',
          proximityState: liveState?.proximityState ?? '',
          activeStopType: liveState?.activeStopType ?? '',
          distanceToActiveStopMeters: liveState?.distanceToActiveStopMeters ?? 0,
          etaSeconds: liveState?.etaSeconds ?? 0,
          etaSource: liveState?.etaSource ?? 'none',
          activeStopLat: liveState?.activeStopLat ?? 0,
          activeStopLng: liveState?.activeStopLng ?? 0,
          currentRouteFraction: liveState?.currentRouteFraction ?? 0,
          activeStopRouteFraction: liveState?.activeStopRouteFraction ?? 0,
          remainingRouteFraction: liveState?.remainingRouteFraction ?? 0,
          routeGeometrySource: liveState?.routeGeometrySource ?? 'none',
          tripStatus: trip?.status ?? '',
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
    const trip = await repo.getTripById(tripId);
    const points = await repo.getRecentPath(tripId);
    callback(null, {
      trip: trip ? tripToProto(trip) : null,
      points: points.map((point) => ({
        coordinates: { latitude: point.lat, longitude: point.lng },
        headingDegrees: point.bearing ?? 0,
        recordedAt: { seconds: String(Math.floor(new Date(point.time).getTime() / 1000)) },
      })),
      encodedPolyline: encodePolyline(
        points.map((point) => ({ lat: point.lat, lng: point.lng })),
      ),
    });
  } catch (err) {
    callback({ code: grpc.status.INTERNAL, message: String(err) } as grpc.ServiceError);
  }
};

const completeTrip: Handler<CompleteTripReq, unknown> = async (call, callback) => {
  try {
    const { tripId } = call.request;
    const points = await repo.getRecentPath(tripId);
    const distanceMeters = calculatePathDistanceMeters(points);
    const pathEncoded = encodePolyline(points.map((point) => ({
      lat: point.lat,
      lng: point.lng,
    })));
    const trip = await repo.completeTripById(tripId, pathEncoded, distanceMeters);
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
    const distMeters = Math.round(
      geoSvc.haversineDistance(
        origin.latitude,
        origin.longitude,
        destination.latitude,
        destination.longitude,
      ),
    );
    const durationSeconds = Math.round(distMeters / 8.3);
    callback(null, {
      durationSeconds,
      durationInTrafficSeconds: durationSeconds,
      distanceMeters: distMeters,
      cacheSource: 'miss',
    });
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
      if (err) {
        logger.error({ err }, 'gRPC bind failed');
        process.exit(1);
      }
      logger.info({ port }, 'location-service gRPC server listening');
    },
  );

  return server;
}
