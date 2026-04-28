import { Redis, type RedisOptions } from 'ioredis';
import type { Logger } from 'pino';

export interface CreateRedisClientOptions {
  url: string;
  logger?: Logger;
  redisOptions?: RedisOptions;
  lazyConnect?: boolean;
}

export function createRedisClient(options: CreateRedisClientOptions): Redis {
  const client = new Redis(options.url, {
    maxRetriesPerRequest: 3,
    enableReadyCheck: true,
    lazyConnect: options.lazyConnect ?? false,
    ...options.redisOptions,
  });

  client.on('connect', () => {
    options.logger?.info('Redis connected');
  });

  client.on('error', (error: Error) => {
    options.logger?.error({ err: error }, 'Redis error');
  });

  return client;
}

export async function closeRedisClient(client: Redis): Promise<void> {
  await client.quit();
}
