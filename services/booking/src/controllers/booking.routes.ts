import type { FastifyInstance } from 'fastify';
import { BookingService } from '../services/booking.service.js';
import { BookingRepository } from '../repositories/booking.repository.js';
import { pgPool } from '../db.js';
import { scheduleExpiry, getExpiryQueue } from '../jobs/booking-expiry.worker.js';
import IORedis from 'ioredis';
import { config } from '../config.js';
import { logger } from '../logger.js';
import { z } from 'zod';
import { LatraComplianceService } from '../services/latra.service.js';

const service = new BookingService(new BookingRepository(pgPool));
const latraService = new LatraComplianceService(new BookingRepository(pgPool));
const redis = new IORedis(config.REDIS_URL, { maxRetriesPerRequest: null });
const uuidParamSchema = z.object({ routeId: z.string().uuid() });
const latraDateRangeSchema = z.object({
  startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  endDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  cursor: z.string().optional(),
  limit: z.coerce.number().int().min(1).max(500).optional(),
});
const latraVehicleSchema = z.object({
  registration_number: z.string().min(3).max(20),
});

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
      pickupWalkingDistance?: number;
      dropoffWalkingDistance?: number;
      pickupWalkingTime?: number;
      dropoffWalkingTime?: number;
      estimatedPickupTime?: string;
      suggestedPickupName?: string;
      suggestedDropoffName?: string;
      pickupPointLat?: number;
      pickupPointLng?: number;
      dropoffPointLat?: number;
      dropoffPointLng?: number;
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
        pickupWalkingDistance: body.pickupWalkingDistance,
        dropoffWalkingDistance: body.dropoffWalkingDistance,
        pickupWalkingTime: body.pickupWalkingTime,
        dropoffWalkingTime: body.dropoffWalkingTime,
        estimatedPickupTime: body.estimatedPickupTime ? new Date(body.estimatedPickupTime) : undefined,
        suggestedPickupName: body.suggestedPickupName,
        suggestedDropoffName: body.suggestedDropoffName,
        pickupPointLat: body.pickupPointLat,
        pickupPointLng: body.pickupPointLng,
        dropoffPointLat: body.dropoffPointLat,
        dropoffPointLng: body.dropoffPointLng,
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

  // GET /api/v1/bookings/me?role=passenger|driver
  app.get('/api/v1/bookings/me', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });
    const headerRole = (req.headers['x-user-role'] as string) ?? '';
    const query = req.query as { limit?: number; offset?: number; role?: string };
    const requestedRole = (query.role ?? headerRole ?? 'passenger').toLowerCase();
    const { limit = 20, offset = 0 } = query;
    const role = requestedRole === 'driver' ? 'driver' : 'passenger';
    const bookings = await service.listMyBookings(userId, role, limit, offset);
    return reply.send({ bookings });
  });

  // GET /api/v1/bookings/routes/:routeId/operations — driver route workspace
  app.get('/api/v1/bookings/routes/:routeId/operations', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });
    const parse = uuidParamSchema.safeParse(req.params);
    if (!parse.success) {
      return reply.status(400).send({
        error: 'VALIDATION_ERROR',
        message: 'routeId must be a valid UUID',
      });
    }
    const { routeId } = parse.data;
    const bookings = await service.listDriverRouteOperations(routeId, userId);
    return reply.send({ bookings });
  });

  // GET /api/v1/bookings/safety-reports
  app.get('/api/v1/bookings/safety-reports', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });

    try {
      const reports = await service.listSafetyReportsForUser(userId);
      return reply.send({
        reports: reports.map((report) => ({
          reportId: report.id,
          bookingId: report.booking_id,
          routeId: report.route_id,
          passengerId: report.passenger_id,
          driverId: report.driver_id,
          bookingStatus: report.booking_status,
          journeyState: report.journey_state,
          paymentStatus: report.payment_status,
          pickupName: report.pickup_name,
          dropoffName: report.dropoff_name,
          reportedBy: report.payload?.reportedBy,
          reporterRole: report.payload?.reporterRole,
          reason: report.payload?.reason,
          status: report.payment_status === 'paid' ? 'under_review' : 'submitted',
          createdAt: report.created_at,
        })),
      });
    } catch (err) {
      logger.error({ err }, 'GET /bookings/safety-reports failed');
      return reply.status(500).send({ error: 'INTERNAL_ERROR' });
    }
  });

  // GET /api/v1/latra/trips?startDate=YYYY-MM-DD&endDate=YYYY-MM-DD
  app.get('/api/v1/latra/trips', async (req, reply) => {
    const userRole = req.headers['x-user-role'] as string | undefined;
    if (userRole !== 'admin') return reply.status(403).send({ error: 'FORBIDDEN' });
    const parsed = latraDateRangeSchema.safeParse(req.query);
    if (!parsed.success) {
      return reply.status(400).send({ error: 'VALIDATION_ERROR', issues: parsed.error.issues });
    }

    try {
      return reply.send(await latraService.listTrips(parsed.data));
    } catch (err) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code === 'VALIDATION_ERROR') return reply.status(400).send({ error: 'VALIDATION_ERROR' });
      logger.error({ err }, 'GET /latra/trips failed');
      return reply.status(500).send({ error: 'INTERNAL_ERROR' });
    }
  });

  // GET /api/v1/latra/compliance-stats
  app.get('/api/v1/latra/compliance-stats', async (req, reply) => {
    const userRole = req.headers['x-user-role'] as string | undefined;
    if (userRole !== 'admin') return reply.status(403).send({ error: 'FORBIDDEN' });

    try {
      return reply.send(await latraService.getComplianceStats());
    } catch (err) {
      logger.error({ err }, 'GET /latra/compliance-stats failed');
      return reply.status(500).send({ error: 'INTERNAL_ERROR' });
    }
  });

  // POST /api/v1/mock/latra/oauth/token
  app.post('/api/v1/mock/latra/oauth/token', async (_req, reply) => {
    if (config.NODE_ENV === 'production') return reply.status(404).send({ error: 'NOT_FOUND' });
    return reply.send(latraService.mockOAuthToken());
  });

  // POST /api/v1/mock/latra/vehicle-verification
  app.post('/api/v1/mock/latra/vehicle-verification', async (req, reply) => {
    if (config.NODE_ENV === 'production') return reply.status(404).send({ error: 'NOT_FOUND' });
    const parsed = latraVehicleSchema.safeParse(req.body ?? {});
    if (!parsed.success) {
      return reply.status(400).send({ error: 'VALIDATION_ERROR', issues: parsed.error.issues });
    }
    return reply.send(latraService.mockVerifyVehicle(parsed.data.registration_number));
  });

  // POST /api/v1/mock/latra/report-submissions
  app.post('/api/v1/mock/latra/report-submissions', async (req, reply) => {
    if (config.NODE_ENV === 'production') return reply.status(404).send({ error: 'NOT_FOUND' });
    const payload = req.body as { trips?: unknown[] } | undefined;
    return reply.status(202).send({
      accepted: true,
      mock: true,
      received_records: Array.isArray(payload?.trips) ? payload.trips.length : 0,
      submitted_at: new Date().toISOString(),
    });
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
    const { reason = 'PASSENGER_CANCELLED' } = (req.body as { reason?: string }) ?? {};
    try {
      const result = await service.cancelByPassengerWithRefund(id, userId, reason);
      // Remove expiry job if still pending
      try { await getExpiryQueue(redis).remove(`expire_${id}`); } catch {}
      return reply.send({
        ...result.booking,
        refund: result.refund,
      });
    } catch (err) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code === 'NOT_FOUND') return reply.status(404).send({ error: 'NOT_FOUND' });
      if (code === 'FORBIDDEN') return reply.status(403).send({ error: 'FORBIDDEN' });
      if (code === 'INVALID_STATE') return reply.status(409).send({ error: 'INVALID_STATE' });
      logger.error({ err }, 'POST /bookings/:id/cancel failed');
      return reply.status(500).send({ error: 'INTERNAL_ERROR' });
    }
  });

  // POST /api/v1/bookings/:id/emergency
  app.post('/api/v1/bookings/:id/emergency', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });

    const { id } = req.params as { id: string };
    const { reason = 'EMERGENCY_REPORTED' } = (req.body as { reason?: string }) ?? {};

    try {
      const booking = await service.triggerEmergency(id, userId, reason);
      return reply.send({
        reported: true,
        bookingId: booking.id,
        routeId: booking.route_id,
        reason,
      });
    } catch (err) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code === 'NOT_FOUND') return reply.status(404).send({ error: 'NOT_FOUND' });
      if (code === 'FORBIDDEN') return reply.status(403).send({ error: 'FORBIDDEN' });
      logger.error({ err }, 'POST /bookings/:id/emergency failed');
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
      if (code === 'NOT_FOUND') return reply.status(404).send({ error: 'NOT_FOUND', message: 'Booking not found' });
      if (code === 'FORBIDDEN') return reply.status(403).send({ error: 'FORBIDDEN', message: 'Only the assigned driver can start this trip' });
      return reply.status(409).send({ error: 'INVALID_STATE', message: 'Cannot start trip in current state' });
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
      if (code === 'NOT_FOUND') return reply.status(404).send({ error: 'NOT_FOUND', message: 'Booking not found' });
      if (code === 'FORBIDDEN') return reply.status(403).send({ error: 'FORBIDDEN', message: 'Only the assigned driver can complete this trip' });
      return reply.status(409).send({ error: 'INVALID_STATE', message: 'Cannot complete trip in current state' });
    }
  });

  // POST /api/v1/bookings/:id/arrive-pickup (driver only)
  app.post('/api/v1/bookings/:id/arrive-pickup', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });
    const { id } = req.params as { id: string };
    try {
      const booking = await service.arrivePickup(id, userId);
      return reply.send(booking);
    } catch (err) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code === 'NOT_FOUND') return reply.status(404).send({ error: 'NOT_FOUND', message: 'Booking not found' });
      if (code === 'FORBIDDEN') return reply.status(403).send({ error: 'FORBIDDEN', message: 'Only the assigned driver can mark arrival' });
      return reply.status(409).send({ error: 'INVALID_STATE', message: 'Cannot mark pickup arrival in current state' });
    }
  });

  // POST /api/v1/bookings/:id/board-passenger (driver only)
  app.post('/api/v1/bookings/:id/board-passenger', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });
    const { id } = req.params as { id: string };
    try {
      const booking = await service.boardPassenger(id, userId);
      return reply.send(booking);
    } catch (err) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code === 'NOT_FOUND') return reply.status(404).send({ error: 'NOT_FOUND', message: 'Booking not found' });
      if (code === 'FORBIDDEN') return reply.status(403).send({ error: 'FORBIDDEN', message: 'Only the assigned driver can board this passenger' });
      return reply.status(409).send({ error: 'INVALID_STATE', message: 'Cannot board passenger in current state' });
    }
  });

  // POST /api/v1/bookings/:id/dropoff-passenger (driver only)
  app.post('/api/v1/bookings/:id/dropoff-passenger', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });
    const { id } = req.params as { id: string };
    try {
      const booking = await service.dropoffPassenger(id, userId);
      return reply.send(booking);
    } catch (err) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code === 'NOT_FOUND') return reply.status(404).send({ error: 'NOT_FOUND', message: 'Booking not found' });
      if (code === 'FORBIDDEN') return reply.status(403).send({ error: 'FORBIDDEN', message: 'Only the assigned driver can drop off this passenger' });
      return reply.status(409).send({ error: 'INVALID_STATE', message: 'Cannot drop off passenger in current state' });
    }
  });

  // POST /api/v1/bookings/:id/mark-no-show (driver only)
  app.post('/api/v1/bookings/:id/mark-no-show', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });
    const { id } = req.params as { id: string };
    const { reason = 'NO_SHOW' } = (req.body as { reason?: string }) ?? {};
    try {
      const booking = await service.markNoShow(id, userId, reason);
      return reply.send(booking);
    } catch (err) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code === 'NOT_FOUND') return reply.status(404).send({ error: 'NOT_FOUND', message: 'Booking not found' });
      if (code === 'FORBIDDEN') return reply.status(403).send({ error: 'FORBIDDEN', message: 'Only the assigned driver can mark a no-show' });
      return reply.status(409).send({ error: 'INVALID_STATE', message: 'Cannot mark no-show in current state' });
    }
  });

  // POST /api/v1/bookings/:id/complete-journey (driver or passenger)
  app.post('/api/v1/bookings/:id/complete-journey', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });
    const { id } = req.params as { id: string };
    try {
      const booking = await service.completeJourney(id, userId);
      return reply.send(booking);
    } catch (err) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code === 'NOT_FOUND') return reply.status(404).send({ error: 'NOT_FOUND', message: 'Booking not found' });
      if (code === 'FORBIDDEN') return reply.status(403).send({ error: 'FORBIDDEN', message: 'Only booking participants can complete this journey' });
      return reply.status(409).send({ error: 'INVALID_STATE', message: 'Cannot complete journey in current state' });
    }
  });

  // POST /api/v1/bookings/:id/decline (driver only, within 10 min window)
  app.post('/api/v1/bookings/:id/decline', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });
    const { id } = req.params as { id: string };
    const { reason = 'No reason given' } = (req.body as { reason?: string }) ?? {};
    try {
      const booking = await service.declineBooking(id, userId, reason);
      return reply.send(booking);
    } catch (err) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code === 'NOT_FOUND') return reply.status(404).send({ error: 'NOT_FOUND' });
      if (code === 'FORBIDDEN') return reply.status(403).send({ error: 'FORBIDDEN' });
      if (code === 'CANNOT_DECLINE') return reply.status(409).send({ error: 'CANNOT_DECLINE', message: 'Booking is not pending or decline window has expired' });
      logger.error({ err }, 'POST /bookings/:id/decline failed');
      return reply.status(500).send({ error: 'INTERNAL_ERROR' });
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
