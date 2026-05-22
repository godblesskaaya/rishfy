import { WebSocketServer, WebSocket } from 'ws';
import type { IncomingMessage } from 'http';
import { createServer } from 'http';
import { randomUUID } from 'crypto';
import IORedis from 'ioredis';
import { GeoService } from '../services/geo.service.js';
import { LocationRepository, type TripRow } from '../repositories/location.repository.js';
import { deriveTripLiveState } from '../services/live-trip.service.js';
import { pgPool } from '../db.js';
import { config } from '../config.js';
import { logger } from '../logger.js';
import { getProducer } from '../kafka.js';

interface DriverMessage {
  type: 'location';
  lat: number;
  lng: number;
  bearing?: number;
  heading?: number;
  speedKmh?: number;
  speed_kmh?: number;
  accuracyMeters?: number;
  accuracy_meters?: number;
  tripId?: string;
  trip_id?: string;
  driverId?: string;
  driverUserId?: string;
  driver_user_id?: string;
  timestamp?: string;
}

interface SubscribeMessage {
  type: 'subscribe';
  tripId?: string;
  trip_id?: string;
  bookingId?: string;
  booking_id?: string;
  driverId?: string;
}

type WsMessage = DriverMessage | SubscribeMessage;

interface RequestContext {
  pathname: string;
  tripId: string | null;
  bookingId: string | null;
  driverId: string | null;
}

const tripSubscribers = new Map<string, Set<WebSocket>>();
const driverSubscribers = new Map<string, Set<WebSocket>>();
const passengerSubscriptions = new Map<WebSocket, { tripId: string | null; driverId: string | null }>();
const driverSockets = new Map<WebSocket, string>();
const THROTTLE_MAP = new Map<string, number>();

export function startWsServer(redis: IORedis): void {
  const geo = new GeoService(redis);
  const repo = new LocationRepository(pgPool);
  const httpServer = createServer();
  const wss = new WebSocketServer({ server: httpServer });

  wss.on('connection', (ws: WebSocket, req: IncomingMessage) => {
    const context = parseRequestContext(req);
    const isDriver = context.pathname.startsWith('/ws/driver');
    const isPassenger = context.pathname.startsWith('/ws/location');

    if (isDriver) {
      handleDriverConnection(ws, context, geo, repo);
    } else if (isPassenger) {
      handlePassengerConnection(ws, context, repo);
    } else {
      ws.close(4000, 'Unknown endpoint');
    }
  });

  httpServer.listen(config.WS_PORT, () => {
    logger.info({ port: config.WS_PORT }, 'WebSocket server listening');
  });
}

function parseRequestContext(req: IncomingMessage): RequestContext {
  const rawUrl = req.url ?? '/';
  const url = new URL(rawUrl, 'http://localhost');
  return {
    pathname: url.pathname,
    tripId: url.searchParams.get('trip_id') ?? url.searchParams.get('tripId'),
    bookingId: url.searchParams.get('booking_id') ?? url.searchParams.get('bookingId'),
    driverId: url.searchParams.get('driver_id')
      ?? url.searchParams.get('driverId')
      ?? url.searchParams.get('driver_user_id')
      ?? url.searchParams.get('driverUserId'),
  };
}

async function resolveTripContext(
  repo: LocationRepository,
  identifiers: { tripId?: string | null; bookingId?: string | null },
): Promise<TripRow | null> {
  if (identifiers.tripId) {
    return repo.getTripById(identifiers.tripId);
  }
  if (identifiers.bookingId) {
    return repo.getTripByBookingId(identifiers.bookingId);
  }
  return null;
}

function normalizeTimestamp(timestamp?: string): Date {
  if (!timestamp) return new Date();
  const parsed = new Date(timestamp);
  return Number.isNaN(parsed.getTime()) ? new Date() : parsed;
}

function normalizeHeading(msg: DriverMessage): number | undefined {
  return msg.heading ?? msg.bearing;
}

function normalizeSpeedKmh(msg: DriverMessage): number | undefined {
  return msg.speedKmh ?? msg.speed_kmh;
}

function normalizeAccuracyMeters(msg: DriverMessage): number | undefined {
  return msg.accuracyMeters ?? msg.accuracy_meters;
}

function addSocketSubscriber(map: Map<string, Set<WebSocket>>, key: string, ws: WebSocket): void {
  if (!map.has(key)) map.set(key, new Set());
  map.get(key)!.add(ws);
}

function removeSocketSubscriber(map: Map<string, Set<WebSocket>>, key: string, ws: WebSocket): void {
  const set = map.get(key);
  if (!set) return;
  set.delete(ws);
  if (set.size === 0) map.delete(key);
}

function clearPassengerSubscription(ws: WebSocket): void {
  const current = passengerSubscriptions.get(ws);
  if (!current) return;
  if (current.tripId) removeSocketSubscriber(tripSubscribers, current.tripId, ws);
  if (current.driverId) removeSocketSubscriber(driverSubscribers, current.driverId, ws);
  passengerSubscriptions.delete(ws);
}

async function subscribePassenger(
  ws: WebSocket,
  repo: LocationRepository,
  input: { tripId?: string | null; bookingId?: string | null; driverId?: string | null },
): Promise<void> {
  clearPassengerSubscription(ws);

  const trip = await resolveTripContext(repo, input);
  const tripId = trip?.id ?? input.tripId ?? null;
  const driverId = trip?.driver_id ?? input.driverId ?? null;

  if (tripId) addSocketSubscriber(tripSubscribers, tripId, ws);
  if (driverId) addSocketSubscriber(driverSubscribers, driverId, ws);

  passengerSubscriptions.set(ws, { tripId, driverId });
  ws.send(JSON.stringify({
    type: 'subscribed',
    event: 'trip.subscribed',
    trip_id: trip?.id ?? tripId,
    booking_id: trip?.booking_id ?? input.bookingId ?? null,
    driver_user_id: driverId,
  }));
}

function emitToSubscribers(tripId: string | null, driverId: string | null, payload: Record<string, unknown>): void {
  const recipients = new Set<WebSocket>();

  if (tripId) {
    for (const socket of tripSubscribers.get(tripId) ?? []) {
      recipients.add(socket);
    }
  }

  if (driverId) {
    for (const socket of driverSubscribers.get(driverId) ?? []) {
      recipients.add(socket);
    }
  }

  const serialized = JSON.stringify(payload);
  for (const socket of recipients) {
    if (socket.readyState === WebSocket.OPEN) {
      socket.send(serialized);
    }
  }
}

function buildLocationEventData(args: {
  driverId: string;
  trip: TripRow | null;
  tripId: string | null;
  lat: number;
  lng: number;
  heading?: number;
  speedKmh?: number;
  accuracyMeters?: number;
  timestampIso: string;
  liveState: ReturnType<typeof deriveTripLiveState>;
}): Record<string, unknown> {
  const {
    driverId,
    trip,
    tripId,
    lat,
    lng,
    heading,
    speedKmh,
    accuracyMeters,
    timestampIso,
    liveState,
  } = args;
  return {
    trip_id: trip?.id ?? tripId,
    booking_id: trip?.booking_id ?? null,
    driver_id: driverId,
    driver_user_id: driverId,
    passenger_id: trip?.passenger_id ?? null,
    trip_status: trip?.status ?? null,
    lat,
    lng,
    bearing: heading ?? null,
    heading: heading ?? null,
    speed_kmh: speedKmh ?? null,
    accuracy_meters: accuracyMeters ?? null,
    timestamp: timestampIso,
    active_stop_type: liveState.activeStopType,
    active_stop_lat: liveState.activeStopLat,
    active_stop_lng: liveState.activeStopLng,
    distance_to_active_stop_meters: liveState.distanceToActiveStopMeters,
    proximity_state: liveState.proximityState,
    eta_seconds: liveState.etaSeconds,
    eta_source: liveState.etaSource,
    current_route_fraction: liveState.currentRouteFraction,
    active_stop_route_fraction: liveState.activeStopRouteFraction,
    remaining_route_fraction: liveState.remainingRouteFraction,
    route_geometry_source: liveState.routeGeometrySource,
  };
}

function buildLivePayload(args: Parameters<typeof buildLocationEventData>[0]): Record<string, unknown> {
  return {
    type: 'location_update',
    event: 'driver.location.updated',
    ...buildLocationEventData(args),
  };
}

function buildArrivalPayload(args: {
  driverId: string;
  trip: TripRow;
  lat: number;
  lng: number;
  timestampIso: string;
  distanceMeters: number | null;
}): Record<string, unknown> {
  const { driverId, trip, lat, lng, timestampIso, distanceMeters } = args;
  return {
    type: 'driver_arrived',
    event: 'driver.arrived',
    trip_id: trip.id,
    booking_id: trip.booking_id,
    driver_id: driverId,
    driver_user_id: driverId,
    passenger_id: trip.passenger_id,
    arrival_lat: lat,
    arrival_lng: lng,
    pickup_lat: trip.origin_lat,
    pickup_lng: trip.origin_lng,
    distance_to_pickup_m: distanceMeters,
    arrived_at: timestampIso,
  };
}

function buildEventEnvelope(
  eventType: string,
  eventVersion: string,
  data: Record<string, unknown>,
  timestampIso: string,
): Record<string, unknown> {
  return {
    event_id: randomUUID(),
    event_type: eventType,
    event_version: eventVersion,
    timestamp: timestampIso,
    source: {
      service: config.SERVICE_NAME,
      instance_id: process.env['HOSTNAME'] ?? 'unknown',
      version: process.env['npm_package_version'] ?? 'unknown',
    },
    data,
  };
}

function shouldThrottle(key: string, nowMs: number, intervalMs: number): boolean {
  const last = THROTTLE_MAP.get(key) ?? 0;
  if (nowMs - last <= intervalMs) return true;
  THROTTLE_MAP.set(key, nowMs);
  return false;
}

function handleDriverConnection(
  ws: WebSocket,
  initialContext: RequestContext,
  geo: GeoService,
  repo: LocationRepository,
): void {
  let boundDriverId = initialContext.driverId;
  let boundTripId = initialContext.tripId;

  ws.on('message', async (raw) => {
    try {
      const msg = JSON.parse(raw.toString()) as WsMessage;
      if (msg.type !== 'location') return;

      const driverMsg = msg as DriverMessage;
      const trip = await resolveTripContext(repo, {
        tripId: driverMsg.tripId ?? driverMsg.trip_id ?? boundTripId,
        bookingId: initialContext.bookingId,
      });

      if (trip) {
        boundTripId = trip.id;
      }

      const effectiveDriverId = trip?.driver_id
        ?? driverMsg.driverId
        ?? driverMsg.driverUserId
        ?? driverMsg.driver_user_id
        ?? boundDriverId;

      if (!effectiveDriverId) {
        logger.warn({ tripId: boundTripId }, 'Ignoring WS driver message without driver identity');
        return;
      }

      if (!boundDriverId) {
        boundDriverId = effectiveDriverId;
        driverSockets.set(ws, effectiveDriverId);
        logger.info({ driverId: effectiveDriverId, tripId: boundTripId }, 'Driver connected to WS');
      }

      const recordedAt = normalizeTimestamp(driverMsg.timestamp);
      const heading = normalizeHeading(driverMsg);
      const speedKmh = normalizeSpeedKmh(driverMsg);
      const accuracyMeters = normalizeAccuracyMeters(driverMsg);
      const liveState = deriveTripLiveState(
        trip,
        { lat: driverMsg.lat, lng: driverMsg.lng, speedKmh },
        config.ARRIVAL_RADIUS_METERS,
      );
      const timestampIso = recordedAt.toISOString();

      const persistedTripId = trip?.id ?? driverMsg.tripId ?? driverMsg.trip_id ?? boundTripId ?? undefined;
      const throttleKeyBase = persistedTripId ?? effectiveDriverId;
      const now = Date.now();
      const locationEventData = buildLocationEventData({
        driverId: effectiveDriverId,
        trip,
        tripId: persistedTripId ?? null,
        lat: driverMsg.lat,
        lng: driverMsg.lng,
        heading,
        speedKmh,
        accuracyMeters,
        timestampIso,
        liveState,
      });

      if (!shouldThrottle(`db:${throttleKeyBase}`, now, config.LOCATION_KAFKA_THROTTLE_MS)) {
        await repo.insertDriverLocation({
          time: recordedAt,
          driverId: effectiveDriverId,
          tripId: persistedTripId,
          lat: driverMsg.lat,
          lng: driverMsg.lng,
          bearing: heading,
          speedKmh,
          accuracyMeters,
        });

        try {
          const producer = await getProducer();
          await producer.send({
            topic: 'driver.location.updated',
            messages: [{
              key: throttleKeyBase,
              value: JSON.stringify(
                buildEventEnvelope('driver.location.updated', '1.2', locationEventData, timestampIso),
              ),
            }],
          });
        } catch (err) {
          logger.warn({ err, driverId: effectiveDriverId }, 'Kafka publish for location update failed');
        }
      }

      await geo.updateDriverLocation({
        driverId: effectiveDriverId,
        lat: driverMsg.lat,
        lng: driverMsg.lng,
        tripId: trip?.id,
        bookingId: trip?.booking_id,
        passengerId: trip?.passenger_id,
        bearing: heading,
        speedKmh,
        accuracyMeters,
        timestamp: timestampIso,
        activeStopType: liveState.activeStopType,
        activeStopLat: liveState.activeStopLat,
        activeStopLng: liveState.activeStopLng,
        distanceToActiveStopMeters: liveState.distanceToActiveStopMeters,
        proximityState: liveState.proximityState,
        etaSeconds: liveState.etaSeconds,
        etaSource: liveState.etaSource,
        updatedAt: timestampIso,
      });

      emitToSubscribers(
        trip?.id ?? persistedTripId ?? null,
        effectiveDriverId,
        buildLivePayload({
          driverId: effectiveDriverId,
          trip,
          tripId: persistedTripId ?? null,
          lat: driverMsg.lat,
          lng: driverMsg.lng,
          heading,
          speedKmh,
          accuracyMeters,
          timestampIso,
          liveState,
        }),
      );

      if (
        trip
        && liveState.proximityState === 'arrived_pickup'
        && !shouldThrottle(`arrival:${trip.id}`, now, 30_000)
      ) {
        const arrivalPayload = buildArrivalPayload({
          driverId: effectiveDriverId,
          trip,
          lat: driverMsg.lat,
          lng: driverMsg.lng,
          timestampIso,
          distanceMeters: liveState.distanceToActiveStopMeters,
        });

        emitToSubscribers(trip.id, effectiveDriverId, arrivalPayload);

        try {
          const producer = await getProducer();
          await producer.send({
            topic: 'driver.arrived',
            messages: [{
              key: trip.id,
              value: JSON.stringify(
                buildEventEnvelope(
                  'driver.arrived',
                  '1.1',
                  {
                    driver_id: effectiveDriverId,
                    trip_id: trip.id,
                    booking_id: trip.booking_id,
                    passenger_id: trip.passenger_id,
                    arrival_lat: driverMsg.lat,
                    arrival_lng: driverMsg.lng,
                    pickup_lat: trip.origin_lat,
                    pickup_lng: trip.origin_lng,
                    distance_to_pickup_m: liveState.distanceToActiveStopMeters,
                    arrived_at: timestampIso,
                  },
                  timestampIso,
                ),
              ),
            }],
          });
        } catch (err) {
          logger.warn({ err, tripId: trip.id }, 'Kafka publish for arrival failed');
        }
      }
    } catch (err) {
      logger.warn({ err }, 'WS driver message parse error');
    }
  });

  ws.on('close', () => {
    if (boundDriverId) {
      driverSockets.delete(ws);
      void geo.removeDriver(boundDriverId);
      logger.info({ driverId: boundDriverId, tripId: boundTripId }, 'Driver disconnected from WS');
    }
  });
}

function handlePassengerConnection(
  ws: WebSocket,
  initialContext: RequestContext,
  repo: LocationRepository,
): void {
  if (initialContext.tripId || initialContext.bookingId || initialContext.driverId) {
    void subscribePassenger(ws, repo, initialContext).catch((err) => {
      logger.warn({ err, ...initialContext }, 'Initial passenger subscription failed');
    });
  }

  ws.on('message', (raw) => {
    try {
      const msg = JSON.parse(raw.toString()) as WsMessage;
      if (msg.type !== 'subscribe') return;

      const subscribeMsg = msg as SubscribeMessage;
      void subscribePassenger(ws, repo, {
        tripId: subscribeMsg.tripId ?? subscribeMsg.trip_id,
        bookingId: subscribeMsg.bookingId ?? subscribeMsg.booking_id ?? initialContext.bookingId,
        driverId: subscribeMsg.driverId,
      }).catch((err) => {
        logger.warn({ err }, 'Passenger subscription failed');
        ws.send(JSON.stringify({
          type: 'error',
          event: 'trip.subscribe_failed',
          message: 'Could not subscribe to live trip updates',
        }));
      });
    } catch (err) {
      logger.warn({ err }, 'WS passenger message parse error');
    }
  });

  ws.on('close', () => {
    clearPassengerSubscription(ws);
  });
}
