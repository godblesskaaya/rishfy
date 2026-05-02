import { WebSocketServer, WebSocket } from 'ws';
import type { IncomingMessage } from 'http';
import { createServer } from 'http';
import IORedis from 'ioredis';
import { GeoService } from '../services/geo.service.js';
import { LocationRepository } from '../repositories/location.repository.js';
import { pgPool } from '../db.js';
import { config } from '../config.js';
import { logger } from '../logger.js';
import { getProducer } from '../kafka.js';

interface DriverMessage {
  type: 'location';
  lat: number;
  lng: number;
  bearing?: number;
  speedKmh?: number;
  accuracyMeters?: number;
  tripId?: string;
}

interface SubscribeMessage {
  type: 'subscribe';
  driverId: string;
}

type WsMessage = DriverMessage | SubscribeMessage;

// Map: driverId → set of subscriber sockets (passengers watching that driver)
const subscribers = new Map<string, Set<WebSocket>>();

// Map: driverWs → driverId (for cleanup on disconnect)
const driverSockets = new Map<WebSocket, string>();

const THROTTLE_MAP = new Map<string, number>();

export function startWsServer(redis: IORedis): void {
  const geo = new GeoService(redis);
  const repo = new LocationRepository(pgPool);
  const httpServer = createServer();
  const wss = new WebSocketServer({ server: httpServer });

  wss.on('connection', (ws: WebSocket, req: IncomingMessage) => {
    const url = req.url ?? '';
    const isDriver = url.startsWith('/ws/driver');
    const isPassenger = url.startsWith('/ws/location');

    if (isDriver) {
      handleDriverConnection(ws, geo, repo, redis);
    } else if (isPassenger) {
      handlePassengerConnection(ws, redis);
    } else {
      ws.close(4000, 'Unknown endpoint');
    }
  });

  httpServer.listen(config.WS_PORT, () => {
    logger.info({ port: config.WS_PORT }, 'WebSocket server listening');
  });
}

function handleDriverConnection(ws: WebSocket, geo: GeoService, repo: LocationRepository, _redis: IORedis): void {
  let driverId: string | null = null;
  const PICKUP_COORDS = new Map<string, { lat: number; lng: number }>();

  ws.on('message', async (raw) => {
    try {
      const msg = JSON.parse(raw.toString()) as WsMessage & { driverId?: string; pickupLat?: number; pickupLng?: number };

      if (!driverId && msg.driverId) {
        driverId = msg.driverId;
        driverSockets.set(ws, driverId);
        logger.info({ driverId }, 'Driver connected to WS');
      }

      if (!driverId) return;

      if (msg.type === 'location') {
        const locMsg = msg as DriverMessage;
        const now = Date.now();

        // Throttle DB write to config.LOCATION_KAFKA_THROTTLE_MS
        const lastDb = THROTTLE_MAP.get(`db:${driverId}`) ?? 0;
        if (now - lastDb > config.LOCATION_KAFKA_THROTTLE_MS) {
          THROTTLE_MAP.set(`db:${driverId}`, now);
          await repo.insertDriverLocation({
            time: new Date(),
            driverId,
            tripId: locMsg.tripId,
            lat: locMsg.lat,
            lng: locMsg.lng,
            bearing: locMsg.bearing,
            speedKmh: locMsg.speedKmh,
            accuracyMeters: locMsg.accuracyMeters,
          });

          // Publish to Kafka (throttled)
          try {
            const producer = await getProducer();
            await producer.send({
              topic: 'driver.location_updated',
              messages: [{ key: driverId, value: JSON.stringify({ driverId, lat: locMsg.lat, lng: locMsg.lng, timestamp: new Date().toISOString() }) }],
            });
          } catch {}
        }

        // Always update Redis GEO (in-memory, cheap)
        await geo.updateDriverLocation({
          driverId,
          lat: locMsg.lat,
          lng: locMsg.lng,
          bearing: locMsg.bearing,
          speedKmh: locMsg.speedKmh,
          updatedAt: new Date().toISOString(),
        });

        // Fan out to all subscribers of this driver
        const subs = subscribers.get(driverId);
        if (subs && subs.size > 0) {
          const payload = JSON.stringify({ type: 'location_update', driverId, lat: locMsg.lat, lng: locMsg.lng, bearing: locMsg.bearing });
          for (const sub of subs) {
            if (sub.readyState === WebSocket.OPEN) sub.send(payload);
          }
        }

        // Arrival detection — check if driver is within 100m of any known pickup point
        const pickup = PICKUP_COORDS.get(driverId);
        if (pickup) {
          const dist = geo.haversineDistance(locMsg.lat, locMsg.lng, pickup.lat, pickup.lng);
          if (dist <= config.ARRIVAL_RADIUS_METERS) {
            const lastArrival = THROTTLE_MAP.get(`arrival:${driverId}`) ?? 0;
            if (now - lastArrival > 30_000) {
              THROTTLE_MAP.set(`arrival:${driverId}`, now);
              try {
                const producer = await getProducer();
                await producer.send({
                  topic: 'driver.arrived',
                  messages: [{ key: driverId, value: JSON.stringify({ driverId, timestamp: new Date().toISOString() }) }],
                });
              } catch {}
            }
          }
        }

        if (msg.pickupLat !== undefined && msg.pickupLng !== undefined) {
          PICKUP_COORDS.set(driverId, { lat: msg.pickupLat, lng: msg.pickupLng });
        }
      }
    } catch (err) {
      logger.warn({ err }, 'WS driver message parse error');
    }
  });

  ws.on('close', () => {
    if (driverId) {
      driverSockets.delete(ws);
      void geo.removeDriver(driverId);
      logger.info({ driverId }, 'Driver disconnected from WS');
    }
  });
}

function handlePassengerConnection(ws: WebSocket, _redis?: unknown): void {
  let watchingDriver: string | null = null;

  ws.on('message', (raw) => {
    try {
      const msg = JSON.parse(raw.toString()) as WsMessage;
      if (msg.type === 'subscribe') {
        const subMsg = msg as SubscribeMessage;
        // Unsubscribe from previous
        if (watchingDriver) {
          subscribers.get(watchingDriver)?.delete(ws);
        }
        watchingDriver = subMsg.driverId;
        if (!subscribers.has(watchingDriver)) {
          subscribers.set(watchingDriver, new Set());
        }
        subscribers.get(watchingDriver)!.add(ws);
        ws.send(JSON.stringify({ type: 'subscribed', driverId: watchingDriver }));
      }
    } catch {}
  });

  ws.on('close', () => {
    if (watchingDriver) {
      subscribers.get(watchingDriver)?.delete(ws);
    }
  });
}
