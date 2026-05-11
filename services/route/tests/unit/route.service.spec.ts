import { describe, it, expect, vi, beforeEach } from 'vitest';

vi.mock('../../src/config.js', () => ({
  config: {
    NODE_ENV: 'test', SERVICE_NAME: 'route-service', HTTP_PORT: 8083, GRPC_PORT: 50053,
    LOG_LEVEL: 'silent', DATABASE_URL: 'postgresql://test:test@localhost/test',
    REDIS_URL: 'redis://localhost:6379', KAFKA_BROKERS: 'localhost:9092',
    GOOGLE_MAPS_API_KEY: 'test-key', USER_SERVICE_GRPC_URL: 'localhost:50052',
    SEARCH_RADIUS_METERS: 5000, COARSE_MATCH_RADIUS_METERS: 3000,
    ROUTE_CACHE_TTL_SECONDS: 300,
  },
  isProduction: false, isDevelopment: false, isTest: true,
}));
vi.mock('../../src/db.js', () => ({ pgPool: {}, db: {} }));

const mockGetDirections = vi.fn().mockResolvedValue({
  polyline: '_p~iF~ps|U_ulLnnqC_mqNvxq`@',
  distance_meters: 10000,
  duration_seconds: 900,
});
const mockGetWalkingDistance = vi.fn();
const mockReverseGeocode = vi.fn();

vi.mock('../../src/clients/googlemaps.client.js', () => ({
  getDirections: mockGetDirections,
  getWalkingDistance: mockGetWalkingDistance,
  reverseGeocode: mockReverseGeocode,
}));
vi.mock('../../src/clients/user.grpc.client.js', () => ({
  checkDriverEligibility: vi.fn().mockResolvedValue({ eligible: true, blockers: [] }),
  getUserProfile: vi.fn().mockResolvedValue({ firstName: 'Test', lastName: 'Driver', ratingAverage: 4.5 }),
}));

const { RouteService } = await import('../../src/services/route.service.js');
const { AppError } = await import('../../src/utils/errors.js');

const mockRoute = {
  id: 'route-1', driver_id: 'driver-1', vehicle_id: 'vehicle-1',
  origin_name: 'Ubungo', destination_name: 'Kariakoo',
  origin_lat: -6.7924, origin_lng: 39.2083,
  destination_lat: -6.8161, destination_lng: 39.2894,
  polyline: '_p~iF~ps|U_ulLnnqC', route_geometry_geojson: null,
  distance_meters: 10000, duration_seconds: 1800,
  flexibility_minutes: 15,
  available_seats: 3, booked_seats: 0, price_per_seat: '5000',
  departure_time: new Date('2026-05-01T07:00:00Z'), status: 'active' as const,
  recurrence: 'none' as const, recurrence_days: null, recurrence_end_date: null,
  parent_route_id: null, driver_name: 'Test Driver', driver_rating: '4.5',
  vehicle_make: null, vehicle_model: null, vehicle_color: null, vehicle_plate: null,
  created_at: new Date(), updated_at: new Date(),
};

function makePool() { return { query: vi.fn(), connect: vi.fn() } as unknown as import('pg').Pool; }
function makeRedis() {
  return {
    get: vi.fn().mockResolvedValue(null),
    setex: vi.fn(),
    del: vi.fn(),
  } as unknown as import('ioredis').Redis;
}

// ─── getRoute ─────────────────────────────────────────────────────────────────

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

// ─── cancelRoute ──────────────────────────────────────────────────────────────

describe('RouteService.cancelRoute', () => {
  it('throws ROUTE_NOT_FOUND when cancel returns null', async () => {
    const pool = makePool();
    const redis = makeRedis();
    vi.mocked(pool.query).mockResolvedValueOnce({ rows: [], rowCount: 0 } as never);
    const svc = new RouteService(pool, redis);
    await expect(svc.cancelRoute('driver-1', 'bad-route')).rejects.toThrow(AppError);
  });
});

// ─── previewRoute ─────────────────────────────────────────────────────────────

describe('RouteService.previewRoute', () => {
  it('returns polyline and GeoJSON linestring without DB write', async () => {
    const pool = makePool();
    const redis = makeRedis();
    const svc = new RouteService(pool, redis);

    const result = await svc.previewRoute({
      origin_lat: -6.7924, origin_lng: 39.2083,
      destination_lat: -6.8161, destination_lng: 39.2894,
    });

    expect(result.polyline).toBeTruthy();
    expect(result.geojson_linestring.type).toBe('LineString');
    expect(Array.isArray(result.geojson_linestring.coordinates)).toBe(true);
    expect(result.distance_meters).toBe(10000);
    expect(result.duration_seconds).toBe(900);
    expect(vi.mocked(pool.query)).not.toHaveBeenCalled();
  });

  it('passes waypoints to getDirections', async () => {
    const pool = makePool();
    const redis = makeRedis();
    const svc = new RouteService(pool, redis);
    const waypoints = [{ lat: -6.8, lng: 39.25 }];

    await svc.previewRoute({
      origin_lat: -6.7924, origin_lng: 39.2083,
      destination_lat: -6.8161, destination_lng: 39.2894,
      waypoints,
    });

    expect(mockGetDirections).toHaveBeenCalledWith(
      { lat: -6.7924, lng: 39.2083 },
      { lat: -6.8161, lng: 39.2894 },
      waypoints,
    );
  });

  it('throws DIRECTIONS_UNAVAILABLE when routing API fails', async () => {
    mockGetDirections.mockResolvedValueOnce(null);
    const pool = makePool();
    const redis = makeRedis();
    const svc = new RouteService(pool, redis);

    await expect(svc.previewRoute({
      origin_lat: -6.7924, origin_lng: 39.2083,
      destination_lat: -6.8161, destination_lng: 39.2894,
    })).rejects.toThrow(AppError);
  });
});

// ─── searchRoutes — Stage 3 temporal filter ───────────────────────────────────

describe('RouteService.searchRoutes — Stage 3 temporal filter', () => {
  const desiredTime = new Date('2026-05-01T07:00:00Z');

  // candidate whose estimated pickup time is 30 minutes before desired (within 30+15 = 45 min window)
  const withinWindow = {
    ...mockRoute,
    pickup_fraction: 0.1,   // 10% along route, 1800s * 0.1 = 180s from departure
    dropoff_fraction: 0.8,
    closest_pickup_geojson: '{"type":"Point","coordinates":[39.22,-6.795]}',
    closest_dropoff_geojson: '{"type":"Point","coordinates":[39.28,-6.81]}',
    // departure_time = 07:00, pickup_fraction=0.1, duration=1800 → pickup at 07:03
  };

  // candidate whose estimated pickup time is 2 hours off (outside window)
  const outsideWindow = {
    ...mockRoute,
    id: 'route-2',
    departure_time: new Date('2026-05-01T05:00:00Z'), // 2 hours early
    pickup_fraction: 0.1,
    dropoff_fraction: 0.8,
    closest_pickup_geojson: '{"type":"Point","coordinates":[39.22,-6.795]}',
    closest_dropoff_geojson: '{"type":"Point","coordinates":[39.28,-6.81]}',
  };

  beforeEach(() => {
    mockGetWalkingDistance.mockResolvedValue({ distance_meters: 400, duration_seconds: 300 });
    mockReverseGeocode.mockResolvedValue('Ubungo Bus Stand');
  });

  it('filters out candidates outside combined flexibility window', async () => {
    const pool = makePool();
    const redis = makeRedis();
    vi.mocked(pool.query).mockResolvedValueOnce({ rows: [withinWindow, outsideWindow] } as never);

    const svc = new RouteService(pool, redis);
    const results = await svc.searchRoutes({
      pickup_lat: -6.795, pickup_lng: 39.22,
      dropoff_lat: -6.81, dropoff_lng: 39.28,
      desired_departure_time: desiredTime,
      time_flexibility_minutes: 30,
    });

    // Only withinWindow should survive
    expect(results.length).toBe(1);
    expect(results[0]?.route_id).toBe('route-1');
  });
});

// ─── searchRoutes — Stage 4 walking distance cache ───────────────────────────

describe('RouteService.searchRoutes — Stage 4 walking distance cache', () => {
  const candidate = {
    ...mockRoute,
    pickup_fraction: 0.1,
    dropoff_fraction: 0.8,
    closest_pickup_geojson: '{"type":"Point","coordinates":[39.22,-6.795]}',
    closest_dropoff_geojson: '{"type":"Point","coordinates":[39.28,-6.81]}',
  };

  it('uses Redis cache on second search — does not call walking API again', async () => {
    const futureTime = new Date(Date.now() + 3600_000);
    const futureCandidate = {
      ...candidate,
      departure_time: futureTime,
      closest_pickup_geojson: '{"type":"Point","coordinates":[39.215,-6.793]}',
      closest_dropoff_geojson: '{"type":"Point","coordinates":[39.285,-6.808]}',
    };

    const pool = makePool();
    const cachedWalk = JSON.stringify({ distance_meters: 350, duration_seconds: 260 });

    // Key-based mock: walk: keys return cached values; everything else returns null
    const redis = {
      get: vi.fn().mockImplementation((key: string) =>
        Promise.resolve(key.startsWith('walk:') ? cachedWalk : null),
      ),
      setex: vi.fn(),
      del: vi.fn(),
    } as unknown as import('ioredis').Redis;

    vi.mocked(pool.query).mockResolvedValueOnce({ rows: [futureCandidate] } as never);
    mockReverseGeocode.mockResolvedValue('Ubungo');
    mockGetWalkingDistance.mockClear();

    const svc = new RouteService(pool, redis);
    await svc.searchRoutes({
      pickup_lat: -6.795, pickup_lng: 39.22,
      dropoff_lat: -6.81, dropoff_lng: 39.28,
      desired_departure_time: futureTime,
    });

    expect(mockGetWalkingDistance).not.toHaveBeenCalled();
  });

  it('discards candidate when walking distance exceeds max', async () => {
    const futureTime = new Date(Date.now() + 3600_000);
    const futureCandidate = {
      ...candidate,
      departure_time: futureTime,
      closest_pickup_geojson: '{"type":"Point","coordinates":[39.215,-6.793]}',
      closest_dropoff_geojson: '{"type":"Point","coordinates":[39.285,-6.808]}',
    };

    const pool = makePool();
    const redis = makeRedis();
    vi.mocked(pool.query).mockResolvedValueOnce({ rows: [futureCandidate] } as never);

    mockGetWalkingDistance.mockResolvedValue({ distance_meters: 1500, duration_seconds: 1200 });

    const svc = new RouteService(pool, redis);
    const results = await svc.searchRoutes({
      pickup_lat: -6.795, pickup_lng: 39.22,
      dropoff_lat: -6.81, dropoff_lng: 39.28,
      max_walking_distance_meters: 1000,
      desired_departure_time: futureTime,
    });

    expect(results).toHaveLength(0);
  });
});

// ─── searchRoutes — Stage 5 ranking ──────────────────────────────────────────

describe('RouteService.searchRoutes — Stage 5 ranking', () => {
  it('returns results sorted by walking_distance_to_pickup ascending', async () => {
    const futureTime = new Date(Date.now() + 3600_000);
    const base = {
      ...mockRoute,
      departure_time: futureTime,
      pickup_fraction: 0.1,
      dropoff_fraction: 0.8,
      closest_pickup_geojson: '{"type":"Point","coordinates":[39.215,-6.793]}',
      closest_dropoff_geojson: '{"type":"Point","coordinates":[39.285,-6.808]}',
    };
    const closer  = { ...base, id: 'route-close' };
    const farther = { ...base, id: 'route-far'   };

    const pool = makePool();
    const redis = makeRedis();
    vi.mocked(pool.query).mockResolvedValueOnce({ rows: [farther, closer] } as never);

    let call = 0;
    mockGetWalkingDistance.mockImplementation(() => {
      call++;
      // First two calls are for farther's pickup+dropoff, next two for closer's
      if (call === 1) return Promise.resolve({ distance_meters: 900, duration_seconds: 700 });
      if (call === 2) return Promise.resolve({ distance_meters: 300, duration_seconds: 220 });
      if (call === 3) return Promise.resolve({ distance_meters: 200, duration_seconds: 150 });
      return Promise.resolve({ distance_meters: 100, duration_seconds: 80 });
    });
    mockReverseGeocode.mockResolvedValue('Some street');

    const svc = new RouteService(pool, redis);
    const results = await svc.searchRoutes({
      pickup_lat: -6.795, pickup_lng: 39.22,
      dropoff_lat: -6.81, dropoff_lng: 39.28,
      max_walking_distance_meters: 1000,
      desired_departure_time: futureTime,
    });

    expect(results[0]?.route_id).toBe('route-close');
    expect(results[1]?.route_id).toBe('route-far');
    expect(results[0]!.walking_distance_to_pickup).toBeLessThan(results[1]!.walking_distance_to_pickup);
  });
});
