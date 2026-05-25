import { describe, it, expect, vi, beforeEach } from 'vitest';
import type IORedis from 'ioredis';

vi.mock('../../src/config.js', () => ({
  config: {
    SERVICE_NAME: 'location-service',
    NODE_ENV: 'test',
    LOG_LEVEL: 'silent',
    HTTP_PORT: 8086,
    REDIS_URL: 'redis://localhost:6379',
    DATABASE_URL: 'postgresql://localhost/test',
    KAFKA_BROKERS: 'localhost:9092',
    WS_PORT: 8186,
    ARRIVAL_RADIUS_METERS: 100,
    LOCATION_KAFKA_THROTTLE_MS: 5000,
    DRIVER_ACTIVE_TTL_SECONDS: 300,
  },
  isProduction: false,
  isDevelopment: false,
  isTest: true,
}));

import { GeoService } from '../../src/services/geo.service.js';

function makeRedis(overrides: Partial<IORedis> = {}): IORedis {
  return {
    geoadd: vi.fn().mockResolvedValue(1),
    setex: vi.fn().mockResolvedValue('OK'),
    get: vi.fn().mockResolvedValue(null),
    del: vi.fn().mockResolvedValue(1),
    zrem: vi.fn().mockResolvedValue(1),
    georadius: vi.fn().mockResolvedValue([]),
    ...overrides,
  } as unknown as IORedis;
}

describe('GeoService.haversineDistance', () => {
  const geo = new GeoService(makeRedis());

  it('returns 0 for identical points', () => {
    expect(geo.haversineDistance(-6.7924, 39.2083, -6.7924, 39.2083)).toBe(0);
  });

  it('calculates ~5 km between Dar es Salaam points', () => {
    // ~5 km north of Dar city centre
    const dist = geo.haversineDistance(-6.7924, 39.2083, -6.7474, 39.2083);
    expect(dist).toBeGreaterThan(4_900);
    expect(dist).toBeLessThan(5_100);
  });

  it('correctly orders: A→B === B→A', () => {
    const lat1 = -3.3869, lng1 = 36.6830;
    const lat2 = -6.7924, lng2 = 39.2083;
    const ab = geo.haversineDistance(lat1, lng1, lat2, lng2);
    const ba = geo.haversineDistance(lat2, lng2, lat1, lng1);
    expect(Math.abs(ab - ba)).toBeLessThan(0.001);
  });

  it('returns ~100 m for a 100 m offset', () => {
    // 0.0009° latitude ≈ 100 m
    const dist = geo.haversineDistance(-6.7924, 39.2083, -6.7933, 39.2083);
    expect(dist).toBeGreaterThan(85);
    expect(dist).toBeLessThan(115);
  });
});

describe('GeoService.updateDriverLocation', () => {
  let redis: IORedis;
  let geo: GeoService;

  beforeEach(() => {
    redis = makeRedis();
    geo = new GeoService(redis);
  });

  it('calls GEOADD and SETEX', async () => {
    await geo.updateDriverLocation({
      driverId: 'driver-1',
      lat: -6.7924,
      lng: 39.2083,
      routeRunId: 'run-1',
      updatedAt: new Date().toISOString(),
    });
    expect(redis.geoadd).toHaveBeenCalledOnce();
    expect(redis.setex).toHaveBeenCalledOnce();
    const [, , payload] = (redis.setex as ReturnType<typeof vi.fn>).mock.calls[0] as [string, number, string];
    expect(JSON.parse(payload)).toMatchObject({ routeRunId: 'run-1' });
  });
});

describe('GeoService.getDriverLocation', () => {
  it('returns null when key is missing', async () => {
    const redis = makeRedis({ get: vi.fn().mockResolvedValue(null) } as Partial<IORedis>);
    const geo = new GeoService(redis);
    const result = await geo.getDriverLocation('unknown-driver');
    expect(result).toBeNull();
  });

  it('parses and returns stored location', async () => {
    const stored = { driverId: 'd1', lat: -6.7924, lng: 39.2083, updatedAt: '2026-05-06T00:00:00Z' };
    const redis = makeRedis({ get: vi.fn().mockResolvedValue(JSON.stringify(stored)) } as Partial<IORedis>);
    const geo = new GeoService(redis);
    const result = await geo.getDriverLocation('d1');
    expect(result).toMatchObject(stored);
  });
});

describe('GeoService.getNearbyDrivers', () => {
  it('returns empty array when no drivers nearby', async () => {
    const redis = makeRedis({ georadius: vi.fn().mockResolvedValue([]) } as Partial<IORedis>);
    const geo = new GeoService(redis);
    const result = await geo.getNearbyDrivers(-6.7924, 39.2083, 5);
    expect(result).toEqual([]);
  });

  it('returns driver ids from georadius result', async () => {
    const redis = makeRedis({ georadius: vi.fn().mockResolvedValue(['d1', 'd2']) } as Partial<IORedis>);
    const geo = new GeoService(redis);
    const result = await geo.getNearbyDrivers(-6.7924, 39.2083, 5);
    expect(result).toEqual(['d1', 'd2']);
  });
});
