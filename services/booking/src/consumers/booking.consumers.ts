import { getConsumer } from '../kafka.js';
import { logger } from '../logger.js';
import { BookingService } from '../services/booking.service.js';
import { BookingRepository } from '../repositories/booking.repository.js';
import { pgPool } from '../db.js';

const GROUP_ID = 'booking-service';

export async function startKafkaConsumers(): Promise<void> {
  const service = new BookingService(new BookingRepository(pgPool));

  const consumer = await getConsumer(GROUP_ID);
  await consumer.subscribe({
    topics: ['payment.completed', 'payment.failed', 'route.cancelled_by_driver'],
    fromBeginning: false,
  });

  await consumer.run({
    eachMessage: async ({ topic, message }: { topic: string; message: { value: Buffer | null } }) => {
      const raw = message.value?.toString();
      if (!raw) return;

      try {
        const payload = JSON.parse(raw) as Record<string, unknown>;

        if (topic === 'payment.completed') {
          const bookingId = payload['bookingId'] as string;
          const paymentId = payload['paymentId'] as string;
          if (bookingId && paymentId) {
            await service.handlePaymentCompleted(bookingId, paymentId);
          }
        } else if (topic === 'payment.failed') {
          const bookingId = payload['bookingId'] as string;
          if (bookingId) {
            await service.handlePaymentFailed(bookingId);
          }
        } else if (topic === 'route.cancelled_by_driver') {
          const routeId = payload['routeId'] as string;
          if (routeId) {
            await service.handleDriverCancelledRoute(routeId);
          }
        }
      } catch (err) {
        logger.error({ err, topic }, 'Error processing Kafka message');
      }
    },
  });

  logger.info('Booking Kafka consumers started');
}
