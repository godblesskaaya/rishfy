import { beforeEach, describe, expect, it, vi } from 'vitest';

const addMock = vi.fn().mockResolvedValue(undefined);
const onMock = vi.fn();
const QueueMock = vi.fn(() => ({ add: addMock }));
const WorkerMock = vi.fn(() => ({ on: onMock }));

vi.mock('bullmq', () => ({
  Queue: QueueMock,
  Worker: WorkerMock,
}));

vi.mock('../../src/db.js', () => ({ pgPool: {} }));
vi.mock('../../src/config.js', () => ({
  config: {
    NODE_ENV: 'test',
    SERVICE_NAME: 'notification-service',
    HTTP_PORT: 8087,
    GRPC_PORT: 50057,
    LOG_LEVEL: 'silent',
    DATABASE_URL: 'postgresql://test:test@localhost/test',
    REDIS_URL: 'redis://localhost:6379',
    KAFKA_BROKERS: 'localhost:9092',
    NOTIF_QUEUE_ATTEMPTS: 5,
    NOTIF_QUEUE_BACKOFF_MS: 12000,
  },
  isProduction: false, isDevelopment: false, isTest: true,
}));

const { NotificationService } = await import('../../src/services/notification.service.js');

beforeEach(() => {
  vi.clearAllMocks();
});

describe('NotificationService.enqueue', () => {
  it('enqueues jobs with retry/backoff configuration', async () => {
    const svc = new NotificationService();

    await svc.enqueue({} as never, {
      userId: 'user-1',
      templateKey: 'payment.completed',
      channels: ['push'],
      vars: { amount: '10000' },
    });

    expect(addMock).toHaveBeenCalledWith(
      'send',
      expect.objectContaining({ userId: 'user-1', templateKey: 'payment.completed' }),
      expect.objectContaining({
        attempts: 5,
        backoff: { type: 'exponential', delay: 12000 },
      }),
    );
  });
});
