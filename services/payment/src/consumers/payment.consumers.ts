import { getConsumer } from '../kafka.js';
import { logger } from '../logger.js';
import { PaymentService } from '../services/payment.service.js';
import { PaymentRepository } from '../repositories/payment.repository.js';
import { LedgerRepository } from '../repositories/ledger.repository.js';
import { LedgerPostingService } from '../services/ledger.service.js';
import { PayoutRepository } from '../repositories/payout.repository.js';
import { PayoutService } from '../services/payout.service.js';
import { pgPool } from '../db.js';

const GROUP_ID = 'payment-service';
const TOPIC_BOOKING_COMPLETED = 'booking.completed';
const TOPIC_BOOKING_EMERGENCY = 'booking.emergency';

interface BookingCompletedPayload {
  bookingId: string;
  passengerId: string;
  driverId: string;
  totalPrice: number;
  driverEarnings: number;
}

interface BookingEmergencyPayload {
  bookingId: string;
  driverId: string;
  reportedBy: string;
  reporterRole: 'passenger' | 'driver';
  reason: string;
}

export async function startPaymentConsumers(): Promise<void> {
  const service = new PaymentService(
    new PaymentRepository(pgPool),
    new LedgerPostingService(new LedgerRepository(pgPool)),
  );
  const payoutService = new PayoutService(new PayoutRepository(pgPool));

  const consumer = await getConsumer(GROUP_ID);
  await consumer.subscribe({
    topic: TOPIC_BOOKING_COMPLETED,
    fromBeginning: false,
  });
  await consumer.subscribe({
    topic: TOPIC_BOOKING_EMERGENCY,
    fromBeginning: false,
  });

  await consumer.run({
    eachMessage: async ({ topic, message }: { topic: string; message: { value: Buffer | null } }) => {
      const raw = message.value?.toString();
      if (!raw) return;

      try {
        const parsed = JSON.parse(raw) as Record<string, unknown>;
        if (topic === TOPIC_BOOKING_COMPLETED) {
          const payload = parseBookingCompletedPayload(parsed);
          const result = await service.handleBookingCompleted(payload);
          const hold = result.posted ? await payoutService.applyPendingHoldForBooking(payload.bookingId) : null;
          logger.info({ bookingId: payload.bookingId, result, holdId: hold?.id }, 'Processed booking.completed for payable accrual');
          return;
        }
        if (topic === TOPIC_BOOKING_EMERGENCY) {
          const payload = parseBookingEmergencyPayload(parsed);
          const result = await payoutService.recordSafetyHoldRequest({
            bookingId: payload.bookingId,
            driverUserId: payload.driverId,
            requestedBy: payload.reportedBy,
            note: `${payload.reporterRole}: ${payload.reason}`,
          });
          logger.info({
            bookingId: payload.bookingId,
            holdRequestId: result.request.id,
            holdId: result.hold?.id,
          }, 'Processed booking.emergency for payout hold');
        }
      } catch (err) {
        logger.error({ err, topic }, 'Error processing payment-service Kafka message');
      }
    },
  });

  logger.info('Payment Kafka consumers started');
}

function parseBookingCompletedPayload(payload: Record<string, unknown>): BookingCompletedPayload {
  return {
    bookingId: readString(payload, 'bookingId'),
    passengerId: readString(payload, 'passengerId'),
    driverId: readString(payload, 'driverId'),
    totalPrice: readNumber(payload, 'totalPrice'),
    driverEarnings: readNumber(payload, 'driverEarnings'),
  };
}

function parseBookingEmergencyPayload(payload: Record<string, unknown>): BookingEmergencyPayload {
  const reporterRole = readString(payload, 'reporterRole');
  if (reporterRole !== 'passenger' && reporterRole !== 'driver') {
    throw Object.assign(new Error('Invalid reporterRole'), { code: 'INVALID_BOOKING_EMERGENCY_EVENT' });
  }
  return {
    bookingId: readString(payload, 'bookingId'),
    driverId: readString(payload, 'driverId'),
    reportedBy: readString(payload, 'reportedBy'),
    reporterRole,
    reason: readString(payload, 'reason'),
  };
}

function readString(payload: Record<string, unknown>, key: string): string {
  const value = payload[key];
  if (typeof value !== 'string' || value.trim() === '') {
    throw Object.assign(new Error(`Missing ${key}`), { code: 'INVALID_BOOKING_COMPLETED_EVENT' });
  }
  return value;
}

function readNumber(payload: Record<string, unknown>, key: string): number {
  const value = payload[key];
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw Object.assign(new Error(`Missing ${key}`), { code: 'INVALID_BOOKING_COMPLETED_EVENT' });
  }
  return value;
}
