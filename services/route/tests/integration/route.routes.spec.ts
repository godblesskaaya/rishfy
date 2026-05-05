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
    SEARCH_RADIUS_METERS: 5000,
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
});
