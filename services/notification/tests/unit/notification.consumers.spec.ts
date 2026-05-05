import { beforeEach, describe, expect, it, vi } from 'vitest';

const enqueueMock = vi.fn().mockResolvedValue(undefined);
const subscribeMock = vi.fn().mockResolvedValue(undefined);
let eachMessageHandler: ((payload: { topic: string; message: { value: Buffer | null } }) => Promise<void>) | null = null;

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
    NOTIF_QUEUE_ATTEMPTS: 4,
    NOTIF_QUEUE_BACKOFF_MS: 15000,
  },
  isProduction: false, isDevelopment: false, isTest: true,
}));

vi.mock('../../src/kafka.js', () => ({
  getConsumer: vi.fn().mockResolvedValue({
    subscribe: subscribeMock,
    run: vi.fn().mockImplementation(async ({ eachMessage }) => {
      eachMessageHandler = eachMessage;
    }),
  }),
}));

vi.mock('../../src/services/notification.service.js', () => ({
  NotificationService: class {
    enqueue = enqueueMock;
  },
}));

const { startNotificationConsumers } = await import('../../src/consumers/notification.consumers.js');

beforeEach(() => {
  vi.clearAllMocks();
  eachMessageHandler = null;
});

describe('Notification consumers', () => {
  it('routes booking.emergency events into notification queue', async () => {
    await startNotificationConsumers({} as never);
    expect(subscribeMock).toHaveBeenCalledTimes(1);
    expect(eachMessageHandler).toBeTruthy();

    await eachMessageHandler!({
      topic: 'booking.emergency',
      message: {
        value: Buffer.from(JSON.stringify({
          bookingId: 'booking-1',
          routeId: 'route-1',
          passengerId: 'passenger-1',
          driverId: 'driver-1',
          reportedBy: 'passenger-1',
          reporterRole: 'passenger',
          reason: 'UNSAFE_SITUATION',
        })),
      },
    });

    expect(enqueueMock).toHaveBeenCalledTimes(2);
    expect(enqueueMock).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        userId: 'driver-1',
        templateKey: 'booking.emergency',
      }),
    );
  });
});
