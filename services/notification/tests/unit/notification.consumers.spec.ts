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
  isProduction: false,
  isDevelopment: false,
  isTest: true,
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
  it('subscribes to journey and telemetry topics', async () => {
    await startNotificationConsumers({} as never);

    expect(subscribeMock).toHaveBeenCalledWith(expect.objectContaining({
      topics: expect.arrayContaining([
        'booking.journey_started',
        'passenger.boarded',
        'booking.journey_completed',
        'booking.no_show',
        'driver.location_updated',
        'driver.arrived',
      ]),
    }));
    expect(eachMessageHandler).toBeTruthy();
  });

  it('routes booking.emergency events into notification queue', async () => {
    await startNotificationConsumers({} as never);

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

  it('parses driver.arrived envelope payloads for push fan-out', async () => {
    await startNotificationConsumers({} as never);

    await eachMessageHandler!({
      topic: 'driver.arrived',
      message: {
        value: Buffer.from(JSON.stringify({
          event_id: 'evt-1',
          event_type: 'driver.arrived',
          event_version: '1.1',
          timestamp: '2026-05-22T12:00:00.000Z',
          data: {
            trip_id: 'trip-1',
            booking_id: 'booking-1',
            passenger_id: 'passenger-1',
            driver_id: 'driver-1',
            arrival_lat: -6.79,
            arrival_lng: 39.21,
            pickup_lat: -6.78,
            pickup_lng: 39.2,
            arrived_at: '2026-05-22T12:00:00.000Z',
          },
        })),
      },
    });

    expect(enqueueMock).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        userId: 'passenger-1',
        templateKey: 'driver.arrived',
        sourceEventType: 'driver.arrived',
        sourceEventId: 'booking-1',
        vars: expect.objectContaining({
          pickup_address: 'your pickup point',
        }),
        data: expect.objectContaining({
          tripId: 'trip-1',
          driverId: 'driver-1',
        }),
      }),
    );
  });

  it('routes passenger.boarded to the trip.started notification template', async () => {
    await startNotificationConsumers({} as never);

    await eachMessageHandler!({
      topic: 'passenger.boarded',
      message: {
        value: Buffer.from(JSON.stringify({
          bookingId: 'booking-1',
          routeId: 'route-1',
          passengerId: 'passenger-1',
          driverId: 'driver-1',
          tripId: 'trip-1',
          timestamp: '2026-05-22T12:00:00.000Z',
        })),
      },
    });

    expect(enqueueMock).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        userId: 'passenger-1',
        templateKey: 'trip.started',
        sourceEventType: 'passenger.boarded',
        sourceEventId: 'booking-1',
      }),
    );
  });

  it('parses driver.location_updated envelopes without enqueueing notifications', async () => {
    await startNotificationConsumers({} as never);

    await eachMessageHandler!({
      topic: 'driver.location_updated',
      message: {
        value: Buffer.from(JSON.stringify({
          event_id: 'evt-2',
          event_type: 'driver.location.updated',
          data: {
            trip_id: 'trip-1',
            booking_id: 'booking-1',
            driver_id: 'driver-1',
            proximity_state: 'approaching_pickup',
            active_stop_type: 'pickup',
          },
        })),
      },
    });

    expect(enqueueMock).not.toHaveBeenCalled();
  });
});
