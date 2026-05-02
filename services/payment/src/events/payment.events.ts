import { getProducer } from '../kafka.js';
import { logger } from '../logger.js';

const TOPICS = {
  INITIATED: 'payment.initiated',
  COMPLETED: 'payment.completed',
  FAILED: 'payment.failed',
  REFUNDED: 'payment.refunded',
};

interface PaymentEventBase {
  paymentId: string;
  bookingId: string;
  userId: string;
  amountTzs: number;
  provider: string;
  timestamp: string;
}

async function publish(topic: string, key: string, value: object): Promise<void> {
  try {
    const producer = await getProducer();
    await producer.send({
      topic,
      messages: [{ key, value: JSON.stringify(value) }],
    });
  } catch (err) {
    logger.error({ err, topic, key }, 'Failed to publish payment event');
  }
}

export async function publishPaymentInitiated(data: PaymentEventBase): Promise<void> {
  await publish(TOPICS.INITIATED, data.paymentId, data);
}

export async function publishPaymentCompleted(data: PaymentEventBase & { providerReference: string }): Promise<void> {
  await publish(TOPICS.COMPLETED, data.paymentId, data);
}

export async function publishPaymentFailed(data: PaymentEventBase & { failureCode: string; failureMessage: string }): Promise<void> {
  await publish(TOPICS.FAILED, data.paymentId, data);
}

export async function publishPaymentRefunded(data: PaymentEventBase & { refundedAmountTzs: number; reason: string }): Promise<void> {
  await publish(TOPICS.REFUNDED, data.paymentId, data);
}
