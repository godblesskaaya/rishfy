import type { FastifyInstance, FastifyReply } from 'fastify';
import { z } from 'zod';
import type { RouteService } from '../services/route.service.js';
import { isAppError } from '../utils/errors.js';

function handleError(err: unknown, reply: FastifyReply) {
  if (isAppError(err)) {
    return reply.code(err.statusCode).send({ error: err.code, message: err.message });
  }
  throw err;
}

const createRouteSchema = z.object({
  vehicle_id: z.string().uuid(),
  origin_name: z.string().min(1).max(500),
  origin_lat: z.number().min(-90).max(90),
  origin_lng: z.number().min(-180).max(180),
  destination_name: z.string().min(1).max(500),
  destination_lat: z.number().min(-90).max(90),
  destination_lng: z.number().min(-180).max(180),
  available_seats: z.number().int().min(1).max(20),
  price_per_seat: z.number().positive(),
  departure_time: z.string().datetime(),
  recurrence: z.enum(['none', 'daily', 'weekdays', 'weekly', 'custom']).default('none'),
  recurrence_days: z.array(z.number().int().min(0).max(6)).optional(),
  recurrence_end_date: z.string().optional(),
});

const searchSchema = z.object({
  origin_lat: z.coerce.number().min(-90).max(90),
  origin_lng: z.coerce.number().min(-180).max(180),
  destination_lat: z.coerce.number().min(-90).max(90),
  destination_lng: z.coerce.number().min(-180).max(180),
  departure_after: z.string().optional(),
  seats_needed: z.coerce.number().int().min(1).default(1),
});

export async function routeRoutes(app: FastifyInstance, { svc }: { svc: RouteService }) {
  // GET /routes/search — PostGIS spatial search
  app.get('/search', async (req, reply) => {
    try {
      const params = searchSchema.parse(req.query);
      const results = await svc.searchRoutes({
        origin_lat: params.origin_lat,
        origin_lng: params.origin_lng,
        destination_lat: params.destination_lat,
        destination_lng: params.destination_lng,
        departure_after: params.departure_after ? new Date(params.departure_after) : undefined,
        seats_needed: params.seats_needed,
      });
      return reply.send({ routes: results, total: results.length });
    } catch (err) { return handleError(err, reply); }
  });

  // GET /routes/me — driver's own routes
  app.get('/me', async (req, reply) => {
    try {
      const driverId = req.headers['x-user-id'] as string;
      if (!driverId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      const limit = parseInt(String((req.query as Record<string, string>)['limit'] ?? '20'));
      const offset = parseInt(String((req.query as Record<string, string>)['offset'] ?? '0'));
      const routes = await svc.getDriverRoutes(driverId, limit, offset);
      return reply.send({ routes, total: routes.length });
    } catch (err) { return handleError(err, reply); }
  });

  // POST /routes
  app.post('/', async (req, reply) => {
    try {
      const driverId = req.headers['x-user-id'] as string;
      if (!driverId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      const body = createRouteSchema.parse(req.body);
      const route = await svc.createRoute(driverId, body);
      return reply.code(201).send(route);
    } catch (err) { return handleError(err, reply); }
  });

  // GET /routes/:id
  app.get<{ Params: { id: string } }>('/:id', async (req, reply) => {
    try {
      const route = await svc.getRoute(req.params.id);
      return reply.send(route);
    } catch (err) { return handleError(err, reply); }
  });

  // PATCH /routes/:id
  app.patch<{ Params: { id: string } }>('/:id', async (req, reply) => {
    try {
      const driverId = req.headers['x-user-id'] as string;
      if (!driverId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      const route = await svc.updateRoute(driverId, req.params.id, req.body as Record<string, unknown>);
      return reply.send(route);
    } catch (err) { return handleError(err, reply); }
  });

  // DELETE /routes/:id — soft cancel
  app.delete<{ Params: { id: string } }>('/:id', async (req, reply) => {
    try {
      const driverId = req.headers['x-user-id'] as string;
      if (!driverId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      await svc.cancelRoute(driverId, req.params.id);
      return reply.code(204).send();
    } catch (err) { return handleError(err, reply); }
  });
}
