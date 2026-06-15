import fastify, { type FastifyInstance } from 'fastify';
import type { Pool } from 'pg';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { publishDriverUpgradedMock } = vi.hoisted(() => ({
  publishDriverUpgradedMock: vi.fn(),
}));

vi.mock('../../src/config.js', () => ({
  config: {
    NODE_ENV: 'test',
    SERVICE_NAME: 'user-service',
    HTTP_PORT: 8082,
    GRPC_PORT: 50052,
    LOG_LEVEL: 'silent',
    DATABASE_URL: 'postgresql://test:test@localhost/test',
    REDIS_URL: 'redis://localhost:6379',
    KAFKA_BROKERS: 'localhost:9092',
    MINIO_ENDPOINT: 'http://localhost:9000',
    MINIO_ACCESS_KEY: 'minioadmin',
    MINIO_SECRET_KEY: 'minioadmin',
    MINIO_BUCKET_USER_UPLOADS: 'rishfy-user-uploads',
  },
  isProduction: false, isDevelopment: false, isTest: true,
}));

vi.mock('../../src/clients/minio.client.js', () => ({
  generateUploadUrl: vi.fn().mockResolvedValue('https://minio/upload-url'),
  buildObjectUrl: vi.fn().mockReturnValue('https://minio/object-url'),
}));

vi.mock('../../src/events/user.events.js', () => ({
  publishDriverUpgraded: publishDriverUpgradedMock,
}));

const { UserService } = await import('../../src/services/user.service.js');
const { userRoutes } = await import('../../src/controllers/user.routes.js');

function makePool(): Pool {
  return { query: vi.fn() } as unknown as Pool;
}

describe('user routes integration', () => {
  let app: FastifyInstance;
  let pool: Pool;

  beforeEach(async () => {
    publishDriverUpgradedMock.mockReset();
    pool = makePool();
    const svc = new UserService(pool, { send: vi.fn() } as never);
    app = fastify();
    await app.register(userRoutes, { prefix: '/api/v1/users', svc });
  });

  afterEach(async () => {
    await app.close();
  });

  it('activates a driver vehicle and exposes active ordering in list output', async () => {
    const profile = {
      id: 'dp-1',
      user_id: 'user-1',
      license_number: 'LIC-123',
      license_expiry: new Date('2030-01-01'),
      latra_permit_number: null,
      is_verified: true,
      verified_at: null,
      created_at: new Date(),
      updated_at: new Date(),
    };
    const inactiveVehicle = {
      id: '11111111-1111-4111-8111-111111111111',
      driver_profile_id: 'dp-1',
      make: 'Toyota',
      model: 'Vitz',
      year: 2020,
      color: 'Blue',
      plate_number: 'T111AAA',
      capacity: 4,
      status: 'approved' as const,
      is_active: false,
      created_at: new Date(),
      updated_at: new Date(),
    };
    const activeVehicle = { ...inactiveVehicle, is_active: true };

    vi.mocked(pool.query)
      .mockResolvedValueOnce({ rows: [inactiveVehicle], rowCount: 1 } as never)
      .mockResolvedValueOnce({ rows: [profile], rowCount: 1 } as never)
      .mockResolvedValueOnce({ rows: [activeVehicle], rowCount: 1 } as never)
      .mockResolvedValueOnce({ rows: [profile], rowCount: 1 } as never)
      .mockResolvedValueOnce({
        rows: [
          activeVehicle,
          {
            ...inactiveVehicle,
            id: '22222222-2222-4222-8222-222222222222',
            plate_number: 'T222BBB',
            is_active: false,
          },
        ],
        rowCount: 2,
      } as never);

    const activateRes = await app.inject({
      method: 'PUT',
      url: `/api/v1/users/me/vehicles/${inactiveVehicle.id}/active`,
      headers: { 'x-user-id': 'user-1' },
    });
    expect(activateRes.statusCode).toBe(200);
    expect(activateRes.json().is_active).toBe(true);

    const listRes = await app.inject({
      method: 'GET',
      url: '/api/v1/users/me/vehicles',
      headers: { 'x-user-id': 'user-1' },
    });
    expect(listRes.statusCode).toBe(200);
    expect(listRes.json()[0].is_active).toBe(true);
    const queries = vi.mocked(pool.query).mock.calls.map(([sql]) => String(sql));
    expect(queries.some((sql) => sql.includes('ORDER BY is_active DESC, created_at DESC'))).toBe(true);
  });

  it('publishes driver_upgraded event on become-driver', async () => {
    const upgradedUser = {
      id: 'user-1',
      phone_number: '+255700000001',
      full_name: 'Driver One',
      email: null,
      role: 'driver' as const,
      status: 'active' as const,
      profile_picture_url: null,
      average_rating: '0.00',
      total_ratings: 0,
      created_at: new Date(),
      updated_at: new Date(),
    };
    const driverProfile = {
      id: 'dp-1',
      user_id: 'user-1',
      license_number: 'LIC-999',
      license_expiry: new Date('2030-01-01'),
      latra_permit_number: null,
      is_verified: false,
      verified_at: null,
      created_at: new Date(),
      updated_at: new Date(),
    };

    vi.mocked(pool.query)
      .mockResolvedValueOnce({ rows: [], rowCount: 0 } as never)
      .mockResolvedValueOnce({ rows: [upgradedUser], rowCount: 1 } as never)
      .mockResolvedValueOnce({ rows: [driverProfile], rowCount: 1 } as never);

    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/users/me/become-driver',
      headers: { 'x-user-id': 'user-1' },
      payload: {
        license_number: 'LIC-999',
        license_expiry: '2030-01-01',
      },
    });

    expect(res.statusCode).toBe(201);
    expect(publishDriverUpgradedMock).toHaveBeenCalledTimes(1);
    expect(publishDriverUpgradedMock).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        user_id: 'user-1',
        license_number: 'LIC-999',
      }),
    );
  });

  it('supports /drivers/:id/public alias and strips PII fields', async () => {
    const user = {
      id: 'driver-2',
      phone_number: '+255700000300',
      full_name: 'Driver Two',
      email: 'driver2@rishfy.test',
      role: 'driver' as const,
      status: 'active' as const,
      profile_picture_url: null,
      average_rating: '4.50',
      total_ratings: 12,
      created_at: new Date(),
      updated_at: new Date(),
    };
    const driverProfile = {
      id: 'dp-2',
      user_id: 'driver-2',
      license_number: 'LIC-200',
      license_expiry: new Date('2030-01-01'),
      latra_permit_number: null,
      is_verified: true,
      verified_at: new Date(),
      created_at: new Date(),
      updated_at: new Date(),
    };

	    vi.mocked(pool.query)
	      .mockResolvedValueOnce({ rows: [user], rowCount: 1 } as never)
	      .mockResolvedValueOnce({ rows: [driverProfile], rowCount: 1 } as never)
	      .mockResolvedValueOnce({ rows: [], rowCount: 0 } as never)
	      .mockResolvedValueOnce({ rows: [], rowCount: 0 } as never);

    const res = await app.inject({
      method: 'GET',
      url: '/api/v1/users/drivers/driver-2/public',
    });

    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({
      user: expect.objectContaining({
        id: 'driver-2',
        full_name: 'Driver Two',
        role: 'driver',
      }),
	      driverProfile: expect.objectContaining({
	        id: 'dp-2',
	      }),
	      vehicles: [],
	      activeVehicle: null,
	      reviews: [],
	    });
    expect(res.json().user.phone_number).toBeUndefined();
    expect(res.json().user.email).toBeUndefined();
  });

  it('creates support cases with category-derived priority', async () => {
    const createdAt = new Date('2026-06-15T08:00:00.000Z');
    vi.mocked(pool.query).mockResolvedValueOnce({
      rows: [{
        id: 'case-1',
        user_id: 'user-1',
        booking_id: null,
        subject: 'Refund follow up',
        message: 'My refund is still pending after cancellation.',
        category: 'payment_refund',
        status: 'open',
        priority: 'high',
        last_user_message_at: createdAt,
        last_support_response_at: null,
        resolved_at: null,
        closed_at: null,
        metadata: {},
        created_at: createdAt,
        updated_at: createdAt,
      }],
      rowCount: 1,
    } as never);

    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/users/me/support-cases',
      headers: { 'x-user-id': 'user-1' },
      payload: {
        subject: 'Refund follow up',
        message: 'My refund is still pending after cancellation.',
        category: 'payment refund',
      },
    });

    expect(res.statusCode).toBe(201);
    expect(res.json()).toMatchObject({
      id: 'case-1',
      subject: 'Refund follow up',
      category: 'payment_refund',
      status: 'open',
      priority: 'high',
    });
    expect(vi.mocked(pool.query).mock.calls[0]?.[1]).toEqual([
      'user-1',
      null,
      'Refund follow up',
      'My refund is still pending after cancellation.',
      'payment_refund',
      'high',
    ]);
  });

  it('lists support cases for the authenticated user', async () => {
    const createdAt = new Date('2026-06-15T09:00:00.000Z');
    vi.mocked(pool.query).mockResolvedValueOnce({
      rows: [{
        id: 'case-2',
        user_id: 'user-1',
        booking_id: '11111111-1111-4111-8111-111111111111',
        subject: 'Trip issue',
        message: 'The driver arrived at the wrong gate.',
        category: 'trip',
        status: 'waiting',
        priority: 'normal',
        last_user_message_at: createdAt,
        last_support_response_at: createdAt,
        resolved_at: null,
        closed_at: null,
        metadata: {},
        created_at: createdAt,
        updated_at: createdAt,
      }],
      rowCount: 1,
    } as never);

    const res = await app.inject({
      method: 'GET',
      url: '/api/v1/users/me/support-cases',
      headers: { 'x-user-id': 'user-1' },
    });

    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({
      cases: [
        expect.objectContaining({
          id: 'case-2',
          bookingId: '11111111-1111-4111-8111-111111111111',
          status: 'waiting',
        }),
      ],
    });
  });
});
