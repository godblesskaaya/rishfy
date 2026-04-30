import { describe, it, expect, vi } from 'vitest';

vi.mock('../../src/config.js', () => ({
  config: {
    NODE_ENV: 'test', SERVICE_NAME: 'route-service', HTTP_PORT: 8083, GRPC_PORT: 50053,
    LOG_LEVEL: 'silent', DATABASE_URL: 'postgresql://test:test@localhost/test',
    REDIS_URL: 'redis://localhost:6379', KAFKA_BROKERS: 'localhost:9092',
    GOOGLE_MAPS_API_KEY: 'test-key', USER_SERVICE_GRPC_URL: 'localhost:50052',
    SEARCH_RADIUS_METERS: 5000, ROUTE_CACHE_TTL_SECONDS: 300,
  },
  isProduction: false, isDevelopment: false, isTest: true,
}));
vi.mock('../../src/db.js', () => ({ pgPool: {}, db: {} }));
vi.mock('../../src/clients/googlemaps.client.js', () => ({
  getDirections: vi.fn().mockResolvedValue({
    polyline: 'polyline_data', distance_meters: 10000, duration_seconds: 900,
  }),
}));
vi.mock('../../src/clients/user.grpc.client.js', () => ({
  checkDriverEligibility: vi.fn().mockResolvedValue({ eligible: true, blockers: [] }),
  getUserProfile: vi.fn().mockResolvedValue({ firstName: 'Test', lastName: 'Driver', ratingAverage: 4.5 }),
}));

const { RouteService } = await import('../../src/services/route.service.js');
const { AppError } = await import('../../src/utils/errors.js');

const mockRoute = {
  id: 'route-1', driver_id: 'driver-1', vehicle_id: 'vehicle-1',
  origin_name: 'Dar es Salaam', destination_name: 'Dodoma',
  polyline: null, distance_meters: null, duration_seconds: null,
  available_seats: 3, booked_seats: 0, price_per_seat: '5000',
  departure_time: new Date('2026-05-01T07:00:00Z'), status: 'active' as const,
  recurrence: 'none' as const, recurrence_days: null, recurrence_end_date: null,
  parent_route_id: null, driver_name: null, driver_rating: null,
  vehicle_make: null, vehicle_model: null, vehicle_color: null, vehicle_plate: null,
  created_at: new Date(), updated_at: new Date(),
};

function makePool() { return { query: vi.fn() } as unknown as import('pg').Pool; }
function makeRedis() { return { get: vi.fn().mockResolvedValue(null), setex: vi.fn(), del: vi.fn() } as unknown as import('ioredis').Redis; }

describe('RouteService.getRoute', () => {
  it('throws ROUTE_NOT_FOUND when route missing', async () => {
    const pool = makePool();
    const redis = makeRedis();
    vi.mocked(pool.query).mockResolvedValueOnce({ rows: [], rowCount: 0 } as never);
    const svc = new RouteService(pool, redis);
    await expect(svc.getRoute('nonexistent')).rejects.toThrow(AppError);
  });

  it('returns cached route without DB call', async () => {
    const pool = makePool();
    const redis = makeRedis();
    vi.mocked(redis.get).mockResolvedValueOnce(JSON.stringify(mockRoute));
    const svc = new RouteService(pool, redis);
    const result = await svc.getRoute('route-1');
    expect(result).toBeTruthy();
    expect(vi.mocked(pool.query)).not.toHaveBeenCalled();
  });
});

describe('RouteService.cancelRoute', () => {
  it('throws ROUTE_NOT_FOUND when cancel returns null', async () => {
    const pool = makePool();
    const redis = makeRedis();
    vi.mocked(pool.query).mockResolvedValueOnce({ rows: [], rowCount: 0 } as never);
    const svc = new RouteService(pool, redis);
    await expect(svc.cancelRoute('driver-1', 'bad-route')).rejects.toThrow(AppError);
  });
});
