import { describe, expect, it, vi } from 'vitest';

import { publishJsonMessage, startJsonConsumer } from '../src/kafka.js';

describe('shared kafka helpers', () => {
  it('publishes JSON encoded messages with key and headers', async () => {
    const send = vi.fn().mockResolvedValue([{ topicName: 'auth.events', partition: 0 }]);
    const producer = { send };

    const result = await publishJsonMessage({
      producer: producer as unknown as Parameters<typeof publishJsonMessage>[0]['producer'],
      topic: 'auth.events',
      key: 'user-1',
      value: { event: 'otp.sent' },
      headers: { correlationId: 'corr-1' },
    });

    expect(result).toEqual([{ topicName: 'auth.events', partition: 0 }]);
    expect(send).toHaveBeenCalledWith({
      topic: 'auth.events',
      messages: [
        {
          key: 'user-1',
          value: JSON.stringify({ event: 'otp.sent' }),
          headers: { correlationId: 'corr-1' },
        },
      ],
    });
  });

  it('subscribes and parses JSON consumer payloads', async () => {
    const subscribe = vi.fn().mockResolvedValue(undefined);
    const run = vi.fn(async ({ eachMessage }: { eachMessage: (payload: Parameters<Parameters<typeof startJsonConsumer>[0]['onMessage']>[0]['raw']) => Promise<void> }) => {
      await eachMessage({
        topic: 'auth.events',
        partition: 1,
        message: {
          key: Buffer.from('user-1'),
          value: Buffer.from(JSON.stringify({ event: 'otp.verified' })),
          attributes: 0,
          timestamp: '0',
          offset: '1',
          headers: {},
        },
        heartbeat: vi.fn(),
        pause: vi.fn(),
      });
    });
    const consumer = { subscribe, run };
    const onMessage = vi.fn().mockResolvedValue(undefined);

    await startJsonConsumer({
      consumer: consumer as unknown as Parameters<typeof startJsonConsumer>[0]['consumer'],
      topic: 'auth.events',
      onMessage,
    });

    expect(subscribe).toHaveBeenCalledWith({ topic: 'auth.events', fromBeginning: false });
    expect(onMessage).toHaveBeenCalledWith(expect.objectContaining({
      topic: 'auth.events',
      partition: 1,
      key: 'user-1',
      value: { event: 'otp.verified' },
    }));
  });
});
