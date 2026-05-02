import type { FastifyInstance } from 'fastify';
import { BookingService } from '../services/booking.service.js';
import { BookingRepository } from '../repositories/booking.repository.js';
import { pgPool } from '../db.js';
import { scheduleExpiry, getExpiryQueue } from '../jobs/booking-expiry.worker.js';
import IORedis from 'ioredis';
import { config } from '../config.js';
import { logger } from '../logger.js';

const service = new BookingService(new BookingRepository(pgPool));
const redis = new IORedis(config.REDIS_URL, { maxRetriesPerRequest: null });

export async function bookingRoutes(app: FastifyInstance): Promise<void> {
  // POST /api/v1/bookings — create booking (saga step 1)
  app.post('/api/v1/bookings', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });

    const body = req.body as {
      routeId: string;
      driverId: string;
      seatsBooked: number;
      pricePerSeat: number;
      pickupName?: string;
      dropoffName?: string;
      pickupLat?: number;
      pickupLng?: number;
      dropoffLat?: number;
      dropoffLng?: number;
      idempotencyKey: string;
    };

    try {
      const booking = await service.createBooking({
        routeId: body.routeId,
        passengerId: userId,
        driverId: body.driverId,
        seatsBooked: body.seatsBooked,
        pricePerSeat: body.pricePerSeat,
        pickupName: body.pickupName,
        dropoffName: body.dropoffName,
        pickupLat: body.pickupLat,
        pickupLng: body.pickupLng,
        dropoffLat: body.dropoffLat,
        dropoffLng: body.dropoffLng,
        idempotencyKey: body.idempotencyKey,
      });
      // Schedule 2-minute expiry job
      await scheduleExpiry(booking.id, redis);
      return reply.status(201).send(booking);
    } catch (err) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code === 'INSUFFICIENT_SEATS' || code === 'ROUTE_NOT_ACTIVE') {
        return reply.status(409).send({ error: code });
      }
      logger.error({ err }, 'POST /bookings failed');
      return reply.status(500).send({ error: 'INTERNAL_ERROR' });
    }
  });

  // GET /api/v1/bookings/me
  app.get('/api/v1/bookings/me', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });
    const userRole = (req.headers['x-user-role'] as string) ?? 'passenger';
    const { limit = 20, offset = 0 } = req.query as { limit?: number; offset?: number };
    const role = userRole === 'driver' ? 'driver' : 'passenger';
    const bookings = await service.listMyBookings(userId, role, limit, offset);
    return reply.send({ bookings });
  });

  // GET /api/v1/bookings/:id
  app.get('/api/v1/bookings/:id', async (req, reply) => {
    const { id } = req.params as { id: string };
    const booking = await service.getBooking(id);
    if (!booking) return reply.status(404).send({ error: 'NOT_FOUND' });
    return reply.send(booking);
  });

  // POST /api/v1/bookings/:id/cancel
  app.post('/api/v1/bookings/:id/cancel', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });
    const { id } = req.params as { id: string };
    const { reason = 'PASSENGER_CANCELLED' } = req.body as { reason?: string };
    try {
      const booking = await service.cancelByPassenger(id, userId, reason);
      // Remove expiry job if still pending
      try { await getExpiryQueue(redis).remove(`expire:${id}`); } catch {}
      return reply.send(booking);
    } catch (err) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code === 'NOT_FOUND') return reply.status(404).send({ error: 'NOT_FOUND' });
      if (code === 'FORBIDDEN') return reply.status(403).send({ error: 'FORBIDDEN' });
      if (code === 'INVALID_STATE') return reply.status(409).send({ error: 'INVALID_STATE' });
      logger.error({ err }, 'POST /bookings/:id/cancel failed');
      return reply.status(500).send({ error: 'INTERNAL_ERROR' });
    }
  });

  // POST /api/v1/bookings/:id/start-trip (driver only)
  app.post('/api/v1/bookings/:id/start-trip', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });
    const { id } = req.params as { id: string };
    try {
      const booking = await service.startTrip(id, userId);
      return reply.send(booking);
    } catch (err) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code === 'NOT_FOUND') return reply.status(404).send({ error: 'NOT_FOUND' });
      if (code === 'FORBIDDEN') return reply.status(403).send({ error: 'FORBIDDEN' });
      return reply.status(409).send({ error: 'INVALID_STATE' });
    }
  });

  // POST /api/v1/bookings/:id/complete-trip (driver only)
  app.post('/api/v1/bookings/:id/complete-trip', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });
    const { id } = req.params as { id: string };
    try {
      const booking = await service.completeTrip(id, userId);
      return reply.send(booking);
    } catch (err) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code === 'NOT_FOUND') return reply.status(404).send({ error: 'NOT_FOUND' });
      if (code === 'FORBIDDEN') return reply.status(403).send({ error: 'FORBIDDEN' });
      return reply.status(409).send({ error: 'INVALID_STATE' });
    }
  });

  // POST /api/v1/bookings/:id/rate
  app.post('/api/v1/bookings/:id/rate', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });
    const { id } = req.params as { id: string };
    const { rating, review = '' } = req.body as { rating: number; review?: string };
    if (!rating || rating < 1 || rating > 5) {
      return reply.status(400).send({ error: 'INVALID_RATING', message: 'rating must be 1-5' });
    }
    try {
      const booking = await service.submitRating(id, userId, rating, review);
      return reply.send(booking);
    } catch (err) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code === 'NOT_FOUND') return reply.status(404).send({ error: 'NOT_FOUND' });
      if (code === 'FORBIDDEN') return reply.status(403).send({ error: 'FORBIDDEN' });
      return reply.status(409).send({ error: 'INVALID_STATE' });
    }
  });
}
