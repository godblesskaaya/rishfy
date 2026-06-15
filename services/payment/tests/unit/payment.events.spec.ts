import { beforeEach, describe, expect, it, vi } from 'vitest';

const producerMock = {
  send: vi.fn(),
};

vi.mock('../../src/kafka.js', () => ({
  getProducer: vi.fn(async () => producerMock),
}));

vi.mock('../../src/logger.js', () => ({
  logger: { error: vi.fn(), warn: vi.fn(), info: vi.fn() },
}));

const { dispatchPaymentOutboxBatch } = await import('../../src/events/payment.events.js');

const outboxEvent = {
  id: 'event-1',
  event_key: 'payment:payment-1:completed',
  topic: 'payment.completed',
  message_key: 'payment-1',
  payload: { paymentId: 'payment-1', amountTzs: 10000 },
  status: 'publishing',
  attempts: 1,
  next_attempt_at: new Date(),
  locked_at: new Date(),
  published_at: null,
  last_error: null,
  created_at: new Date(),
  updated_at: new Date(),
} as const;

function makeRepo() {
  return {
    claimPendingOutboxEvents: vi.fn().mockResolvedValue([outboxEvent]),
    markOutboxPublished: vi.fn().mockResolvedValue(undefined),
    markOutboxPublishFailed: vi.fn().mockResolvedValue(undefined),
  };
}

describe('payment event outbox dispatcher', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    producerMock.send.mockResolvedValue(undefined);
  });

  it('publishes claimed outbox events and marks them published', async () => {
    const repo = makeRepo();

    const count = await dispatchPaymentOutboxBatch(repo as never, 10);

    expect(count).toBe(1);
    expect(repo.claimPendingOutboxEvents).toHaveBeenCalledWith(10);
    expect(producerMock.send).toHaveBeenCalledWith({
      topic: 'payment.completed',
      messages: [{
        key: 'payment-1',
        value: JSON.stringify({ paymentId: 'payment-1', amountTzs: 10000 }),
      }],
    });
    expect(repo.markOutboxPublished).toHaveBeenCalledWith('event-1');
    expect(repo.markOutboxPublishFailed).not.toHaveBeenCalled();
  });

  it('marks outbox events failed when Kafka publish fails', async () => {
    const repo = makeRepo();
    producerMock.send.mockRejectedValueOnce(new Error('kafka unavailable'));

    const count = await dispatchPaymentOutboxBatch(repo as never, 10);

    expect(count).toBe(1);
    expect(repo.markOutboxPublished).not.toHaveBeenCalled();
    expect(repo.markOutboxPublishFailed).toHaveBeenCalledWith('event-1', 'kafka unavailable');
  });
});
