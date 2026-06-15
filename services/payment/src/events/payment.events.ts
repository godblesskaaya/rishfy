import { getProducer } from '../kafka.js';
import { logger } from '../logger.js';
import type { PaymentOutboxEventInput, PaymentOutboxEventRow, PaymentRepository } from '../repositories/payment.repository.js';

export const PAYMENT_TOPICS = {
  INITIATED: 'payment.initiated',
  COMPLETED: 'payment.completed',
  FAILED: 'payment.failed',
  REFUNDED: 'payment.refunded',
} as const;

interface PaymentEventBase {
  paymentId: string;
  bookingId: string;
  userId: string;
  amountTzs: number;
  provider: string;
  timestamp: string;
}

export type PaymentOutboxEvent = PaymentOutboxEventInput;

function paymentEvent(eventKey: string, topic: string, key: string, value: object): PaymentOutboxEvent {
  return {
    eventKey,
    topic,
    messageKey: key,
    payload: value as Record<string, unknown>,
  };
}

async function publish(topic: string, key: string, value: object): Promise<void> {
  const producer = await getProducer();
  await producer.send({
    topic,
    messages: [{ key, value: JSON.stringify(value) }],
  });
}

export function buildPaymentInitiatedEvent(data: PaymentEventBase): PaymentOutboxEvent {
  return paymentEvent(`payment:${data.paymentId}:initiated`, PAYMENT_TOPICS.INITIATED, data.paymentId, data);
}

export function buildPaymentCompletedEvent(data: PaymentEventBase & { providerReference: string }): PaymentOutboxEvent {
  return paymentEvent(`payment:${data.paymentId}:completed`, PAYMENT_TOPICS.COMPLETED, data.paymentId, data);
}

export function buildPaymentFailedEvent(data: PaymentEventBase & { failureCode: string; failureMessage: string }): PaymentOutboxEvent {
  return paymentEvent(`payment:${data.paymentId}:failed`, PAYMENT_TOPICS.FAILED, data.paymentId, data);
}

export function buildPaymentRefundedEvent(data: PaymentEventBase & { refundedAmountTzs: number; reason: string }): PaymentOutboxEvent {
  return paymentEvent(`payment:${data.paymentId}:refunded:${data.refundedAmountTzs}`, PAYMENT_TOPICS.REFUNDED, data.paymentId, data);
}

export async function dispatchPaymentOutboxBatch(repo: PaymentRepository, limit = 50): Promise<number> {
  const events = await repo.claimPendingOutboxEvents(limit);
  for (const event of events) {
    await publishClaimedEvent(repo, event);
  }
  return events.length;
}

export function startPaymentOutboxDispatcher(repo: PaymentRepository, intervalMs = 5000): NodeJS.Timeout {
  const tick = async (): Promise<void> => {
    try {
      await dispatchPaymentOutboxBatch(repo);
    } catch (err) {
      logger.error({ err }, 'Payment event outbox dispatch failed');
    }
  };
  void tick();
  return setInterval(() => void tick(), intervalMs);
}

async function publishClaimedEvent(repo: PaymentRepository, event: PaymentOutboxEventRow): Promise<void> {
  try {
    await publish(event.topic, event.message_key, event.payload);
    await repo.markOutboxPublished(event.id);
  } catch (err) {
    logger.error({ err, outboxEventId: event.id, topic: event.topic }, 'Failed to publish payment outbox event');
    await repo.markOutboxPublishFailed(event.id, err instanceof Error ? err.message : String(err));
  }
}

export async function publishPaymentInitiated(data: PaymentEventBase): Promise<void> {
  await publish(PAYMENT_TOPICS.INITIATED, data.paymentId, data);
}

export async function publishPaymentCompleted(data: PaymentEventBase & { providerReference: string }): Promise<void> {
  await publish(PAYMENT_TOPICS.COMPLETED, data.paymentId, data);
}

export async function publishPaymentFailed(data: PaymentEventBase & { failureCode: string; failureMessage: string }): Promise<void> {
  await publish(PAYMENT_TOPICS.FAILED, data.paymentId, data);
}

export async function publishPaymentRefunded(data: PaymentEventBase & { refundedAmountTzs: number; reason: string }): Promise<void> {
  await publish(PAYMENT_TOPICS.REFUNDED, data.paymentId, data);
}
