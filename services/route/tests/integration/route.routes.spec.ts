import fastify, { type FastifyInstance } from 'fastify';
import type { Pool } from 'pg';
import type { Redis } from 'ioredis';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { publishRouteCancelledMock } = vi.hoisted(() => ({
  publishRouteCancelledMock: vi.fn(),
}));

vi.mock('../../src/config.js', () => ({
  config: {
    NODE_ENV: 'test',
    SERVICE_NAME: 'route-service',
    HTTP_PORT: 8083,
    GRPC_PORT: 50053,
    LOG_LEVEL: 'silent',
    DATABASE_URL: 'postgresql://test:test@localhost/test',
    REDIS_URL: 'redis://localhost:6379',
    KAFKA_BROKERS: 'localhost:9092',
    GOOGLE_MAPS_API_KEY: 'test-key',
    USER_SERVICE_GRPC_URL: 'localhost:50052',
    BOOKING_SERVICE_GRPC_URL: 'localhost:50054',
    LOCATION_SERVICE_GRPC_URL: 'localhost:50056',
    SEARCH_RADIUS_METERS: 5000,
    COARSE_MATCH_RADIUS_METERS: 3000,
    ROUTE_CACHE_TTL_SECONDS: 300,
  },
  isProduction: false, isDevelopment: false, isTest: true,
}));

vi.mock('../../src/clients/googlemaps.client.js', () => ({
  getDirections: vi.fn().mockResolvedValue({
    polyline: 'polyline',
    distance_meters: 1000,
    duration_seconds: 600,
  }),
}));

vi.mock('../../src/clients/user.grpc.client.js', () => ({
  checkDriverEligibility: vi.fn().mockResolvedValue({ eligible: true, blockers: [] }),
  getUserProfile: vi.fn().mockResolvedValue({ firstName: 'Test', lastName: 'Driver', ratingAverage: 4.5 }),
}));

vi.mock('../../src/events/route.events.js', () => ({
  publishRouteCancelled: publishRouteCancelledMock,
}));

const { RouteService } = await import('../../src/services/route.service.js');
const { routeRoutes } = await import('../../src/controllers/route.routes.js');
const { AppError } = await import('../../src/utils/errors.js');

function makePool(): Pool {
  return { query: vi.fn() } as unknown as Pool;
}

function makeRedis(): Redis {
  return { get: vi.fn(), setex: vi.fn(), del: vi.fn() } as unknown as Redis;
}

describe('route routes integration', () => {
  let app: FastifyInstance;
  let pool: Pool;
  let redis: Redis;
  let producer: { send: ReturnType<typeof vi.fn> };

  beforeEach(async () => {
    publishRouteCancelledMock.mockReset();
    pool = makePool();
    redis = makeRedis();
    producer = { send: vi.fn() };
    const svc = new RouteService(pool, redis, producer as never);

    app = fastify();
    await app.register(routeRoutes, { prefix: '/api/v1/routes', svc });
  });

  afterEach(async () => {
    await app.close();
  });

  // ── POST /preview ─────────────────────────────────────────────────────────

  it('POST /api/v1/routes/preview returns 200 with polyline and does not write to DB', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/routes/preview',
      headers: { 'x-user-id': 'driver-1' },
      payload: {
        origin_lat: -6.7924,
        origin_lng: 39.2083,
        destination_lat: -6.8161,
        destination_lng: 39.2894,
      },
    });

    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body) as Record<string, unknown>;
    expect(body.polyline).toBe('polyline');
    expect(body.distance_meters).toBe(1000);
    expect(body.duration_seconds).toBe(600);
    expect(body.geojson_linestring).toBeTruthy();
    // No DB write should have occurred
    expect(vi.mocked(pool.query)).not.toHaveBeenCalled();
  });

  it('POST /api/v1/routes/preview returns 401 without x-user-id', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/routes/preview',
      payload: {
        origin_lat: -6.7924, origin_lng: 39.2083,
        destination_lat: -6.8161, destination_lng: 39.2894,
      },
    });
    expect(res.statusCode).toBe(401);
  });

  // ── GET /search ───────────────────────────────────────────────────────────

  it('GET /api/v1/routes/search returns 200 with new params', async () => {
    vi.mocked(pool.query).mockResolvedValueOnce({ rows: [] } as never);
    const futureTime = new Date(Date.now() + 3600_000).toISOString();

    const res = await app.inject({
      method: 'GET',
      url: '/api/v1/routes/search',
      query: {
        pickup_lat: '-6.795',
        pickup_lng: '39.22',
        dropoff_lat: '-6.81',
        dropoff_lng: '39.28',
        desired_departure_time: futureTime,
        time_flexibility_minutes: '30',
        max_walking_distance: '1000',
        seats_needed: '1',
      },
    });

    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body) as { routes: unknown[] };
    expect(Array.isArray(body.routes)).toBe(true);
  });

  it('GET /api/v1/routes/search returns 400 when required params are missing', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/v1/routes/search',
      query: { pickup_lat: '-6.795' }, // missing pickup_lng, dropoff_lat, dropoff_lng
    });
    expect(res.statusCode).toBe(400);
  });

  // ── Route expiry worker ───────────────────────────────────────────────────

  it('startRouteExpiryWorker runs UPDATE with correct SQL on tick', async () => {
    const { startRouteExpiryWorker } = await import('../../src/jobs/route-expiry.worker.js');
    vi.mocked(pool.query).mockResolvedValue({ rowCount: 2 } as never);

    const timer = startRouteExpiryWorker(pool);
    clearInterval(timer);

    // tick runs immediately on startup
    expect(vi.mocked(pool.query)).toHaveBeenCalledWith(
      expect.stringContaining("status = 'departed'"),
    );
    expect(vi.mocked(pool.query)).toHaveBeenCalledWith(
      expect.stringContaining("departure_time + (flexibility_minutes * INTERVAL '1 minute')"),
    );
  });

  it('publishes route.cancelled_by_driver when a driver cancels an active route', async () => {
    const departureTime = new Date('2026-05-10T08:00:00.000Z');
    const cancelledRoute = {
      id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      driver_id: 'driver-1',
      vehicle_id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      origin_name: 'Mikocheni',
      destination_name: 'Posta',
      polyline: null,
      distance_meters: null,
      duration_seconds: null,
      available_seats: 3,
      booked_seats: 0,
      price_per_seat: '5000',
      departure_time: departureTime,
      status: 'cancelled' as const,
      recurrence: 'none' as const,
      recurrence_days: null,
      recurrence_end_date: null,
      parent_route_id: null,
      driver_name: null,
      driver_rating: null,
      vehicle_make: null,
      vehicle_model: null,
      vehicle_color: null,
      vehicle_plate: null,
      created_at: new Date(),
      updated_at: new Date(),
    };

    vi.mocked(pool.query).mockResolvedValueOnce({ rows: [cancelledRoute], rowCount: 1 } as never);

    const res = await app.inject({
      method: 'DELETE',
      url: `/api/v1/routes/${cancelledRoute.id}`,
      headers: { 'x-user-id': 'driver-1' },
    });

    expect(res.statusCode).toBe(204);
    expect(publishRouteCancelledMock).toHaveBeenCalledTimes(1);
    expect(publishRouteCancelledMock).toHaveBeenCalledWith(
      producer,
      expect.objectContaining({
        route_id: cancelledRoute.id,
        driver_id: 'driver-1',
        departure_time: departureTime.toISOString(),
      }),
    );
  });

  it('GET /api/v1/routes/:id/operations returns the driver route workspace', async () => {
    const route = {
      id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      driver_id: 'driver-1',
      vehicle_id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      origin_name: 'Mikocheni',
      origin_lat: -6.7924,
      origin_lng: 39.2083,
      destination_name: 'Posta',
      destination_lat: -6.8161,
      destination_lng: 39.2894,
      polyline: null,
      route_geometry_geojson: null,
      distance_meters: null,
      duration_seconds: null,
      flexibility_minutes: 15,
      available_seats: 3,
      booked_seats: 0,
      price_per_seat: '5000',
      departure_time: new Date('2026-05-10T08:00:00.000Z'),
      status: 'active' as const,
      recurrence: 'none' as const,
      recurrence_days: null,
      recurrence_end_date: null,
      parent_route_id: null,
      driver_name: 'Test Driver',
      driver_rating: '4.5',
      vehicle_make: null,
      vehicle_model: null,
      vehicle_color: null,
      vehicle_plate: null,
      created_at: new Date(),
      updated_at: new Date(),
    };

    const svc = new RouteService(pool, redis, producer as never);
    vi.spyOn(svc, 'getDriverRouteOperations').mockResolvedValue({
      route,
      active_run: null,
      run_stops: [],
      bookings: [
        {
          booking_id: 'booking-1',
          route_id: route.id,
          passenger_user_id: 'passenger-1',
          driver_user_id: 'driver-1',
          seat_count: 1,
          status: 'BOOKING_STATUS_CONFIRMED',
          trip_status: 'TRIP_STATUS_SCHEDULED',
          journey_state: 'JOURNEY_STATE_DRIVER_ARRIVED',
          payment_id: 'payment-1',
          trip_id: '',
          operational_priority: 0,
        },
      ],
    });

    const opsApp = fastify();
    await opsApp.register(routeRoutes, { prefix: '/api/v1/routes', svc });

    const res = await opsApp.inject({
      method: 'GET',
      url: `/api/v1/routes/${route.id}/operations`,
      headers: { 'x-user-id': 'driver-1' },
    });

    expect(res.statusCode).toBe(200);
    expect(JSON.parse(res.body)).toMatchObject({
      route: { id: route.id },
      bookings: [{ booking_id: 'booking-1', operational_priority: 0 }],
    });

    await opsApp.close();
  });

  it('GET /api/v1/routes/:id/operations returns 400 for a non-UUID route id', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/v1/routes/not-a-uuid/operations',
      headers: { 'x-user-id': 'driver-1' },
    });

    expect(res.statusCode).toBe(400);
  });

  it('POST /api/v1/routes/:id/start-run returns the started driver route workspace', async () => {
    const route = {
      id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      driver_id: 'driver-1',
      vehicle_id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      origin_name: 'Mikocheni',
      origin_lat: -6.7924,
      origin_lng: 39.2083,
      destination_name: 'Posta',
      destination_lat: -6.8161,
      destination_lng: 39.2894,
      polyline: null,
      route_geometry_geojson: null,
      distance_meters: null,
      duration_seconds: null,
      flexibility_minutes: 15,
      available_seats: 3,
      booked_seats: 0,
      price_per_seat: '5000',
      departure_time: new Date('2026-05-10T08:00:00.000Z'),
      status: 'active' as const,
      recurrence: 'none' as const,
      recurrence_days: null,
      recurrence_end_date: null,
      parent_route_id: null,
      driver_name: 'Test Driver',
      driver_rating: '4.5',
      vehicle_make: null,
      vehicle_model: null,
      vehicle_color: null,
      vehicle_plate: null,
      created_at: new Date(),
      updated_at: new Date(),
    };

    const svc = new RouteService(pool, redis, producer as never);
    vi.spyOn(svc, 'startRouteRun').mockResolvedValue({
      route,
      active_run: {
        id: 'run-1',
        route_id: route.id,
        driver_id: 'driver-1',
        status: 'active',
        started_at: new Date(),
        completed_at: null,
        cancelled_at: null,
        current_stop_index: 0,
        created_at: new Date(),
        updated_at: new Date(),
      },
      run_stops: [],
      bookings: [],
    });

    const opsApp = fastify();
    await opsApp.register(routeRoutes, { prefix: '/api/v1/routes', svc });

    const res = await opsApp.inject({
      method: 'POST',
      url: `/api/v1/routes/${route.id}/start-run`,
      headers: { 'x-user-id': 'driver-1' },
    });

    expect(res.statusCode).toBe(200);
    expect(JSON.parse(res.body)).toMatchObject({
      route: { id: route.id },
      active_run: { id: 'run-1', status: 'active' },
      bookings: [],
    });

    await opsApp.close();
  });

  it('POST /api/v1/routes/:id/advance-stop returns the advanced workspace', async () => {
    const routeId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
    const svc = new RouteService(pool, redis, producer as never);
    vi.spyOn(svc, 'advanceRouteRun').mockResolvedValue({
      route: { id: routeId } as never,
      active_run: {
        id: 'run-1',
        route_id: routeId,
        driver_id: 'driver-1',
        status: 'active',
        started_at: new Date(),
        completed_at: null,
        cancelled_at: null,
        current_stop_index: 1,
        created_at: new Date(),
        updated_at: new Date(),
      },
      run_stops: [
        {
          id: 'stop-2',
          route_run_id: 'run-1',
          booking_id: 'booking-1',
          stop_kind: 'dropoff',
          sequence: 1,
          status: 'active',
          stop_name: 'Dropoff 1',
          created_at: new Date(),
          updated_at: new Date(),
        },
      ],
      bookings: [],
    });

    const opsApp = fastify();
    await opsApp.register(routeRoutes, { prefix: '/api/v1/routes', svc });

    const res = await opsApp.inject({
      method: 'POST',
      url: `/api/v1/routes/${routeId}/advance-stop`,
      headers: { 'x-user-id': 'driver-1' },
    });

    expect(res.statusCode).toBe(200);
    expect(JSON.parse(res.body)).toMatchObject({
      active_run: { id: 'run-1', current_stop_index: 1 },
      run_stops: [{ sequence: 1, status: 'active' }],
    });

    await opsApp.close();
  });

  it('POST /api/v1/routes/:id/complete-stop returns the updated workspace', async () => {
    const routeId = 'ffffffff-ffff-4fff-8fff-ffffffffffff';
    const svc = new RouteService(pool, redis, producer as never);
    vi.spyOn(svc, 'completeCurrentRouteRunStop').mockResolvedValue({
      route: { id: routeId } as never,
      active_run: {
        id: 'run-1',
        route_id: routeId,
        driver_id: 'driver-1',
        status: 'active',
        started_at: new Date(),
        completed_at: null,
        cancelled_at: null,
        current_stop_index: 2,
        created_at: new Date(),
        updated_at: new Date(),
      },
      run_stops: [
        {
          id: 'stop-2',
          route_run_id: 'run-1',
          booking_id: 'booking-1',
          stop_kind: 'dropoff',
          sequence: 1,
          status: 'completed',
          stop_name: 'Dropoff 1',
          created_at: new Date(),
          updated_at: new Date(),
        },
      ],
      bookings: [],
    });

    const opsApp = fastify();
    await opsApp.register(routeRoutes, { prefix: '/api/v1/routes', svc });

    const res = await opsApp.inject({
      method: 'POST',
      url: `/api/v1/routes/${routeId}/complete-stop`,
      headers: { 'x-user-id': 'driver-1' },
    });

    expect(res.statusCode).toBe(200);
    expect(JSON.parse(res.body)).toMatchObject({
      active_run: { current_stop_index: 2 },
      run_stops: [{ sequence: 1, status: 'completed' }],
    });

    await opsApp.close();
  });

  it('POST /api/v1/routes/:id/complete-run returns the finalized workspace', async () => {
    const routeId = '12121212-1212-4121-8121-121212121212';
    const svc = new RouteService(pool, redis, producer as never);
    vi.spyOn(svc, 'completeRouteRun').mockResolvedValue({
      route: { id: routeId } as never,
      active_run: null,
      run_stops: [],
      bookings: [],
    });

    const opsApp = fastify();
    await opsApp.register(routeRoutes, { prefix: '/api/v1/routes', svc });

    const res = await opsApp.inject({
      method: 'POST',
      url: `/api/v1/routes/${routeId}/complete-run`,
      headers: { 'x-user-id': 'driver-1' },
    });

    expect(res.statusCode).toBe(200);
    expect(JSON.parse(res.body)).toMatchObject({
      route: { id: routeId },
      active_run: null,
      bookings: [],
    });

    await opsApp.close();
  });

  it('POST /api/v1/routes/:id/complete-run returns 409 when stops are still open', async () => {
    const routeId = '34343434-3434-4343-8434-343434343434';
    const svc = new RouteService(pool, redis, producer as never);
    vi.spyOn(svc, 'completeRouteRun').mockRejectedValue(
      new AppError(
        'ROUTE_RUN_NOT_FINISHED',
        409,
        'Complete or skip all remaining stops before finishing the route run',
      ),
    );

    const opsApp = fastify();
    await opsApp.register(routeRoutes, { prefix: '/api/v1/routes', svc });

    const res = await opsApp.inject({
      method: 'POST',
      url: `/api/v1/routes/${routeId}/complete-run`,
      headers: { 'x-user-id': 'driver-1' },
    });

    expect(res.statusCode).toBe(409);
    expect(JSON.parse(res.body)).toMatchObject({
      error: 'ROUTE_RUN_NOT_FINISHED',
    });

    await opsApp.close();
  });
});
