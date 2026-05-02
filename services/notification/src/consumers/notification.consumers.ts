import { getConsumer } from '../kafka.js';
import { logger } from '../logger.js';
import { NotificationService } from '../services/notification.service.js';
import IORedis from 'ioredis';

const svc = new NotificationService();

interface BookingCreatedPayload {
  bookingId: string; passengerId: string; driverId: string;
  confirmationCode: string; driverName?: string; departureTime?: string;
}

interface PaymentPayload {
  bookingId: string; userId: string; amountTzs: number; providerReference?: string;
  confirmationCode?: string;
}

interface BookingCancelledPayload {
  bookingId: string; passengerId: string; driverId: string;
  cancelledBy: 'passenger' | 'driver' | 'system'; driverName?: string; departureTime?: string;
}

interface TripPayload { bookingId: string; driverId: string; passengerId: string; driverName?: string }

const TOPICS = [
  'booking.created', 'booking.confirmed', 'booking.cancelled', 'booking.expired',
  'booking.trip_started', 'booking.trip_completed', 'booking.rated',
  'payment.completed', 'payment.failed',
  'driver.arrived',
];

export async function startNotificationConsumers(redis: IORedis): Promise<void> {
  const consumer = await getConsumer('notification-service');
  await consumer.subscribe({ topics: TOPICS, fromBeginning: false });

  await consumer.run({
    eachMessage: async ({ topic, message }) => {
      const raw = message.value?.toString();
      if (!raw) return;
      try {
        const p = JSON.parse(raw) as Record<string, unknown>;
        await routeEvent(topic, p, redis);
      } catch (err) {
        logger.error({ err, topic }, 'Notification consumer error');
      }
    },
  });

  logger.info('Notification Kafka consumers started');
}

async function routeEvent(topic: string, p: Record<string, unknown>, redis: IORedis): Promise<void> {
  const enq = (params: Parameters<typeof svc.enqueue>[1]) => svc.enqueue(redis, params);

  if (topic === 'booking.created') {
    const d = p as unknown as BookingCreatedPayload;
    await enq({
      userId: d.passengerId,
      templateKey: 'booking.created',
      channels: ['push', 'sms', 'in_app'],
      vars: {
        confirmation_code: d.confirmationCode,
        driver_name: d.driverName ?? 'your driver',
        departure_time: d.departureTime ?? '',
      },
      sourceEventType: topic,
      sourceEventId: d.bookingId,
    });
  } else if (topic === 'payment.completed') {
    const d = p as unknown as PaymentPayload;
    await enq({
      userId: d.userId,
      templateKey: 'payment.completed',
      channels: ['push', 'sms'],
      vars: {
        amount: d.amountTzs.toLocaleString(),
        provider_reference: d.providerReference ?? '',
        confirmation_code: d.confirmationCode ?? '',
      },
      sourceEventType: topic,
      sourceEventId: d.bookingId,
    });
  } else if (topic === 'payment.failed') {
    const d = p as unknown as PaymentPayload;
    await enq({
      userId: d.userId,
      templateKey: 'payment.failed',
      channels: ['push', 'sms'],
      vars: { confirmation_code: d.confirmationCode ?? '' },
      sourceEventType: topic,
      sourceEventId: d.bookingId,
    });
  } else if (topic === 'booking.cancelled') {
    const d = p as unknown as BookingCancelledPayload;
    if (d.cancelledBy === 'driver') {
      await enq({
        userId: d.passengerId,
        templateKey: 'booking.cancelled.by_driver',
        channels: ['push', 'sms', 'in_app'],
        vars: { driver_name: d.driverName ?? 'your driver', departure_time: d.departureTime ?? '' },
        sourceEventType: topic,
        sourceEventId: d.bookingId,
      });
    } else if (d.cancelledBy === 'passenger') {
      await enq({
        userId: d.passengerId,
        templateKey: 'booking.cancelled.passenger',
        channels: ['push', 'in_app'],
        vars: { driver_name: d.driverName ?? 'your driver', departure_time: d.departureTime ?? '', refund_message: '' },
        sourceEventType: topic,
        sourceEventId: d.bookingId,
      });
    }
  } else if (topic === 'booking.trip_started') {
    const d = p as unknown as TripPayload;
    await enq({
      userId: d.passengerId,
      templateKey: 'trip.started',
      channels: ['push'],
      vars: { driver_name: d.driverName ?? 'your driver' },
      sourceEventType: topic,
      sourceEventId: d.bookingId,
    });
  } else if (topic === 'booking.trip_completed') {
    const d = p as unknown as TripPayload;
    await enq({
      userId: d.passengerId,
      templateKey: 'trip.completed',
      channels: ['push', 'in_app'],
      vars: { driver_name: d.driverName ?? 'your driver' },
      sourceEventType: topic,
      sourceEventId: d.bookingId,
    });
  } else if (topic === 'driver.arrived') {
    const d = p as { passengerId: string; bookingId: string; driverName?: string; pickupAddress?: string };
    await enq({
      userId: d.passengerId,
      templateKey: 'driver.arrived',
      channels: ['push'],
      vars: { driver_name: d.driverName ?? 'your driver', pickup_address: d.pickupAddress ?? '' },
      sourceEventType: topic,
      sourceEventId: d.bookingId,
    });
  }
}
