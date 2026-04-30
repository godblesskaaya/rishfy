import { describe, it, expect, vi } from 'vitest';

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
vi.mock('../../src/db.js', () => ({ pgPool: {}, db: {} }));
vi.mock('../../src/clients/minio.client.js', () => ({
  generateUploadUrl: vi.fn().mockResolvedValue('https://minio/upload-url'),
  buildObjectUrl: vi.fn().mockReturnValue('https://minio/object-url'),
}));

const { UserService } = await import('../../src/services/user.service.js');
const { AppError } = await import('../../src/utils/errors.js');

const mockUser = {
  id: 'user-1', phone_number: '+255700000001', full_name: 'Test User',
  email: null, role: 'passenger' as const, status: 'active' as const,
  profile_picture_url: null, average_rating: '0.00', total_ratings: 0,
  created_at: new Date(), updated_at: new Date(),
};

function makePool() { return { query: vi.fn() } as unknown as import('pg').Pool; }

describe('UserService.getProfile', () => {
  it('returns user when found', async () => {
    const pool = makePool();
    vi.mocked(pool.query).mockResolvedValueOnce({ rows: [mockUser], rowCount: 1 } as never);
    const result = await new UserService(pool).getProfile('user-1');
    expect(result.id).toBe('user-1');
  });

  it('throws USER_NOT_FOUND when missing', async () => {
    const pool = makePool();
    vi.mocked(pool.query).mockResolvedValueOnce({ rows: [], rowCount: 0 } as never);
    await expect(new UserService(pool).getProfile('missing')).rejects.toThrow(AppError);
  });
});

describe('UserService.getProfileUploadUrl', () => {
  it('rejects invalid content type', async () => {
    await expect(new UserService(makePool()).getProfileUploadUrl('user-1', 'application/pdf')).rejects.toThrow(AppError);
  });

  it('returns upload and public URL for jpeg', async () => {
    const result = await new UserService(makePool()).getProfileUploadUrl('user-1', 'image/jpeg');
    expect(result.uploadUrl).toBeTruthy();
    expect(result.publicUrl).toBeTruthy();
  });
});

describe('UserService.becomeDriver', () => {
  it('throws ALREADY_DRIVER if driver profile exists', async () => {
    const pool = makePool();
    vi.mocked(pool.query).mockResolvedValueOnce({ rows: [{ id: 'dp-1' }], rowCount: 1 } as never);
    await expect(
      new UserService(pool).becomeDriver('user-1', { license_number: 'L123', license_expiry: '2030-01-01' }),
    ).rejects.toThrow(AppError);
  });
});
