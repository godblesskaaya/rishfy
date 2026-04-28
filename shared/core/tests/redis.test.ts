import { beforeEach, describe, expect, it, vi } from 'vitest';

import { closeRedisClient, createRedisClient } from '../src/redis.js';

const constructorMock = vi.fn();

vi.mock('ioredis', () => {
  class RedisMock {
    public readonly on = vi.fn().mockReturnThis();
    public readonly quit = vi.fn().mockResolvedValue('OK');

    constructor(...args: unknown[]) {
      constructorMock(...args, this);
    }
  }

  return { default: RedisMock, Redis: RedisMock };
});

describe('shared redis helpers', () => {
  beforeEach(() => {
    constructorMock.mockClear();
  });

  it('creates redis clients with safe defaults and caller options', () => {
    const client = createRedisClient({
      url: 'redis://localhost:6379',
      lazyConnect: true,
      redisOptions: { keyPrefix: 'auth:' },
    });

    expect(constructorMock).toHaveBeenCalledWith(
      'redis://localhost:6379',
      expect.objectContaining({
        maxRetriesPerRequest: 3,
        enableReadyCheck: true,
        lazyConnect: true,
        keyPrefix: 'auth:',
      }),
      client
    );
    const redisMock = client as unknown as { on: ReturnType<typeof vi.fn>; quit: ReturnType<typeof vi.fn> };

    expect(redisMock.on).toHaveBeenCalledWith('connect', expect.any(Function));
    expect(redisMock.on).toHaveBeenCalledWith('error', expect.any(Function));
  });

  it('closes redis clients with quit', async () => {
    const client = createRedisClient({ url: 'redis://localhost:6379', lazyConnect: true });

    await closeRedisClient(client);

    const redisMock = client as unknown as { quit: ReturnType<typeof vi.fn> };

    expect(redisMock.quit).toHaveBeenCalledOnce();
  });
});
