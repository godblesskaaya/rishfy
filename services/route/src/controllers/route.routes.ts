import type { FastifyInstance, FastifyReply } from 'fastify';
import { z, ZodError } from 'zod';
import type { RouteService } from '../services/route.service.js';
import { isAppError } from '../utils/errors.js';

function handleError(err: unknown, reply: FastifyReply) {
  if (isAppError(err)) {
    return reply.code(err.statusCode).send({ error: err.code, message: err.message });
  }
  if (err instanceof ZodError) {
    return reply.code(400).send({ error: 'VALIDATION_ERROR', message: err.errors[0]?.message ?? 'Invalid request' });
  }
  throw err;
}

const waypointSchema = z.object({
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
  name: z.string().optional(),
});

const previewRouteSchema = z.object({
  origin_lat: z.number().min(-90).max(90),
  origin_lng: z.number().min(-180).max(180),
  destination_lat: z.number().min(-90).max(90),
  destination_lng: z.number().min(-180).max(180),
  waypoints: z.array(waypointSchema).max(5).optional(),
});

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
  flexibility_minutes: z.number().int().min(0).max(60).default(15),
  waypoints: z.array(waypointSchema).max(5).optional(),
  recurrence: z.enum(['none', 'daily', 'weekdays', 'weekly', 'custom']).default('none'),
  recurrence_days: z.array(z.number().int().min(0).max(6)).optional(),
  recurrence_end_date: z.string().optional(),
});

const searchSchema = z.object({
  pickup_lat: z.coerce.number().min(-90).max(90),
  pickup_lng: z.coerce.number().min(-180).max(180),
  dropoff_lat: z.coerce.number().min(-90).max(90),
  dropoff_lng: z.coerce.number().min(-180).max(180),
  desired_departure_time: z.string().optional(),
  time_flexibility_minutes: z.coerce.number().int().min(0).max(120).default(30),
  preferred_walking_distance: z.coerce.number().int().min(100).max(5000).optional(),
  max_walking_distance: z.coerce.number().int().min(100).max(5000).default(1000),
  seats_needed: z.coerce.number().int().min(1).default(1),
});
const idParamSchema = z.object({ id: z.string().uuid() });

export async function routeRoutes(app: FastifyInstance, { svc }: { svc: RouteService }) {
  // POST /routes/preview — compute route path without persisting
  app.post('/preview', async (req, reply) => {
    try {
      const driverId = req.headers['x-user-id'] as string;
      if (!driverId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      const body = previewRouteSchema.parse(req.body);
      const result = await svc.previewRoute(body);
      return reply.send(result);
    } catch (err) { return handleError(err, reply); }
  });

  // GET /routes/search — 5-stage matching pipeline
  app.get('/search', async (req, reply) => {
    try {
      const params = searchSchema.parse(req.query);
      const results = await svc.searchRoutes({
        pickup_lat: params.pickup_lat,
        pickup_lng: params.pickup_lng,
        dropoff_lat: params.dropoff_lat,
        dropoff_lng: params.dropoff_lng,
        desired_departure_time: params.desired_departure_time ? new Date(params.desired_departure_time) : undefined,
        time_flexibility_minutes: params.time_flexibility_minutes,
        max_walking_distance_meters: params.preferred_walking_distance ?? params.max_walking_distance,
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
      const params = idParamSchema.parse(req.params);
      const route = await svc.getRoute(params.id);
      return reply.send(route);
    } catch (err) { return handleError(err, reply); }
  });

  // GET /routes/:id/operations — driver route workspace
  app.get<{ Params: { id: string } }>('/:id/operations', async (req, reply) => {
    try {
      const driverId = req.headers['x-user-id'] as string;
      if (!driverId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      const params = idParamSchema.parse(req.params);
      const operations = await svc.getDriverRouteOperations(driverId, params.id);
      return reply.send(operations);
    } catch (err) { return handleError(err, reply); }
  });

  // POST /routes/:id/start-run — persistent driver route session
  app.post<{ Params: { id: string } }>('/:id/start-run', async (req, reply) => {
    try {
      const driverId = req.headers['x-user-id'] as string;
      if (!driverId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      const params = idParamSchema.parse(req.params);
      const workspace = await svc.startRouteRun(driverId, params.id);
      return reply.send(workspace);
    } catch (err) { return handleError(err, reply); }
  });

  // POST /routes/:id/advance-stop — activate the current actionable stop
  app.post<{ Params: { id: string } }>('/:id/advance-stop', async (req, reply) => {
    try {
      const driverId = req.headers['x-user-id'] as string;
      if (!driverId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      const params = idParamSchema.parse(req.params);
      const workspace = await svc.advanceRouteRun(driverId, params.id);
      return reply.send(workspace);
    } catch (err) { return handleError(err, reply); }
  });

  // POST /routes/:id/complete-stop — complete the current stop and advance the run
  app.post<{ Params: { id: string } }>('/:id/complete-stop', async (req, reply) => {
    try {
      const driverId = req.headers['x-user-id'] as string;
      if (!driverId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      const params = idParamSchema.parse(req.params);
      const workspace = await svc.completeCurrentRouteRunStop(driverId, params.id);
      return reply.send(workspace);
    } catch (err) { return handleError(err, reply); }
  });

  // POST /routes/:id/complete-run — finalize the active route run
  app.post<{ Params: { id: string } }>('/:id/complete-run', async (req, reply) => {
    try {
      const driverId = req.headers['x-user-id'] as string;
      if (!driverId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      const params = idParamSchema.parse(req.params);
      const workspace = await svc.completeRouteRun(driverId, params.id);
      return reply.send(workspace);
    } catch (err) { return handleError(err, reply); }
  });

  // PATCH /routes/:id
  app.patch<{ Params: { id: string } }>('/:id', async (req, reply) => {
    try {
      const driverId = req.headers['x-user-id'] as string;
      if (!driverId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      const params = idParamSchema.parse(req.params);
      const route = await svc.updateRoute(driverId, params.id, req.body as Record<string, unknown>);
      return reply.send(route);
    } catch (err) { return handleError(err, reply); }
  });

  // DELETE /routes/:id — soft cancel
  app.delete<{ Params: { id: string } }>('/:id', async (req, reply) => {
    try {
      const driverId = req.headers['x-user-id'] as string;
      if (!driverId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      const params = idParamSchema.parse(req.params);
      await svc.cancelRoute(driverId, params.id);
      return reply.code(204).send();
    } catch (err) { return handleError(err, reply); }
  });
}
