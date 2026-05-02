import { Worker, Queue } from 'bullmq';
import IORedis from 'ioredis';
import { config } from '../config.js';
import { logger } from '../logger.js';
import { BookingService } from '../services/booking.service.js';
import { BookingRepository } from '../repositories/booking.repository.js';
import { pgPool } from '../db.js';

export const EXPIRY_QUEUE = 'booking-expiry';

let _queue: Queue | null = null;

export function getExpiryQueue(connection: IORedis): Queue {
  if (!_queue) {
    _queue = new Queue(EXPIRY_QUEUE, { connection });
  }
  return _queue;
}

export function startExpiryWorker(connection: IORedis): Worker {
  const service = new BookingService(new BookingRepository(pgPool));

  const worker = new Worker(
    EXPIRY_QUEUE,
    async (job) => {
      const { bookingId } = job.data as { bookingId: string };
      logger.info({ bookingId, jobId: job.id }, 'Processing booking expiry');
      await service.expireBooking(bookingId);
    },
    { connection, concurrency: 10 },
  );

  worker.on('failed', (job, err) => {
    logger.error({ jobId: job?.id, err }, 'Booking expiry job failed');
  });

  logger.info('Booking expiry worker started');
  return worker;
}

export async function scheduleExpiry(bookingId: string, connection: IORedis): Promise<void> {
  const queue = getExpiryQueue(connection);
  await queue.add(
    'expire',
    { bookingId },
    {
      delay: config.BOOKING_EXPIRY_SECONDS * 1000,
      jobId: `expire:${bookingId}`,
      removeOnComplete: true,
      removeOnFail: 50,
    },
  );
}
