import { describe, it, expect, vi, beforeAll, afterAll } from 'vitest';
import type { FastifyInstance } from 'fastify';

// Mock heavy deps before importing app
vi.mock('ioredis', () => {
  const Mock = vi.fn().mockImplementation(() => ({
    geoadd: vi.fn().mockResolvedValue(1),
    setex: vi.fn().mockResolvedValue('OK'),
    get: vi.fn().mockResolvedValue(null),
    del: vi.fn().mockResolvedValue(1),
    zrem: vi.fn().mockResolvedValue(1),
    georadius: vi.fn().mockResolvedValue([]),
    disconnect: vi.fn(),
  }));
  return { default: Mock };
});

vi.mock('../../src/db.js', () => ({
  pgPool: {
    query: vi.fn().mockResolvedValue({ rows: [], rowCount: 0 }),
  },
}));

vi.mock('../../src/kafka.js', () => ({
  getProducer: vi.fn().mockResolvedValue({ send: vi.fn().mockResolvedValue(undefined) }),
}));

vi.mock('../../src/config.js', () => ({
  config: {
    SERVICE_NAME: 'location-service',
    NODE_ENV: 'test',
    LOG_LEVEL: 'silent',
    HTTP_PORT: 8086,
    REDIS_URL: 'redis://localhost:6379',
    DATABASE_URL: 'postgresql://localhost/test',
    KAFKA_BROKERS: 'localhost:9092',
    GRPC_PORT: 50056,
    WS_PORT: 8186,
    ARRIVAL_RADIUS_METERS: 100,
    LOCATION_KAFKA_THROTTLE_MS: 5000,
    DRIVER_ACTIVE_TTL_SECONDS: 300,
  },
  isProduction: false,
  isDevelopment: false,
  isTest: true,
}));

vi.mock('../../src/logger.js', () => ({
  logger: {
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
    debug: vi.fn(),
    fatal: vi.fn(),
    trace: vi.fn(),
    child: vi.fn().mockReturnThis(),
  },
}));

vi.mock('prom-client', () => ({
  register: { contentType: 'text/plain', metrics: vi.fn().mockResolvedValue('') },
  collectDefaultMetrics: vi.fn(),
  Counter: vi.fn().mockImplementation(() => ({ inc: vi.fn(), labels: vi.fn().mockReturnThis() })),
  Histogram: vi.fn().mockImplementation(() => ({ observe: vi.fn(), labels: vi.fn().mockReturnThis(), startTimer: vi.fn().mockReturnValue(vi.fn()) })),
  Gauge: vi.fn().mockImplementation(() => ({ set: vi.fn(), labels: vi.fn().mockReturnThis() })),
}));

describe('Location HTTP routes', () => {
  let app: FastifyInstance;

  beforeAll(async () => {
    const { buildApp } = await import('../../src/app.js');
    app = await buildApp();
  });

  afterAll(async () => {
    await app.close();
  });

  it('GET /health returns 200', async () => {
    const res = await app.inject({ method: 'GET', url: '/health' });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ status: 'healthy' });
  });

  it('GET /api/v1/locations/driver/:driverId returns 404 when driver not active', async () => {
    const res = await app.inject({ method: 'GET', url: '/api/v1/locations/driver/not-a-driver' });
    expect(res.statusCode).toBe(404);
    expect(res.json()).toMatchObject({ error: 'DRIVER_NOT_ACTIVE' });
  });

  it('GET /api/v1/locations/drivers/:id/current returns 404 when driver not active', async () => {
    const res = await app.inject({ method: 'GET', url: '/api/v1/locations/drivers/not-a-driver/current' });
    expect(res.statusCode).toBe(404);
    expect(res.json()).toMatchObject({ error: 'DRIVER_NOT_ACTIVE' });
  });

  it('GET /api/v1/locations/nearby returns empty drivers array', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/v1/locations/nearby?lat=-6.7924&lng=39.2083',
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ drivers: [] });
  });
});
