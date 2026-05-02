import type { FastifyInstance } from 'fastify';
import { LocationRepository } from '../repositories/location.repository.js';
import { GeoService } from '../services/geo.service.js';
import { pgPool } from '../db.js';
import IORedis from 'ioredis';
import { config } from '../config.js';
import { logger } from '../logger.js';

const repo = new LocationRepository(pgPool);
const redis = new IORedis(config.REDIS_URL, { maxRetriesPerRequest: null });
const geo = new GeoService(redis);

export async function locationRoutes(app: FastifyInstance): Promise<void> {
  // GET /api/v1/locations/driver/:driverId — last known location
  app.get('/api/v1/locations/driver/:driverId', async (req, reply) => {
    const { driverId } = req.params as { driverId: string };
    const loc = await geo.getDriverLocation(driverId);
    if (!loc) return reply.status(404).send({ error: 'DRIVER_NOT_ACTIVE' });
    return reply.send(loc);
  });

  // GET /api/v1/locations/nearby — nearby active drivers
  app.get('/api/v1/locations/nearby', async (req, reply) => {
    const { lat, lng, radius_km = 5 } = req.query as { lat: number; lng: number; radius_km?: number };
    const drivers = await geo.getNearbyDrivers(lat, lng, radius_km);
    return reply.send({ drivers });
  });

  // POST /api/v1/trips — create trip record (called by booking-service on trip start)
  app.post('/api/v1/trips', async (req, reply) => {
    const body = req.body as {
      bookingId: string; driverId: string; passengerId: string;
      originLat: number; originLng: number; destinationLat: number; destinationLng: number;
    };
    try {
      const trip = await repo.createTrip(body);
      return reply.status(201).send(trip);
    } catch (err) {
      logger.error({ err }, 'POST /trips failed');
      return reply.status(500).send({ error: 'INTERNAL_ERROR' });
    }
  });

  // POST /api/v1/trips/:bookingId/start
  app.post('/api/v1/trips/:bookingId/start', async (req, reply) => {
    const { bookingId } = req.params as { bookingId: string };
    const trip = await repo.startTrip(bookingId);
    if (!trip) return reply.status(409).send({ error: 'TRIP_NOT_FOUND_OR_WRONG_STATE' });
    return reply.send(trip);
  });

  // POST /api/v1/trips/:bookingId/complete
  app.post('/api/v1/trips/:bookingId/complete', async (req, reply) => {
    const { bookingId } = req.params as { bookingId: string };
    const { pathEncoded = null, distanceMeters = 0 } = req.body as { pathEncoded?: string; distanceMeters?: number };
    const trip = await repo.completeTrip(bookingId, pathEncoded, distanceMeters);
    if (!trip) return reply.status(409).send({ error: 'TRIP_NOT_FOUND_OR_WRONG_STATE' });
    return reply.send(trip);
  });
}
