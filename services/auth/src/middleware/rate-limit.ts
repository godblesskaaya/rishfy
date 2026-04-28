import type { FastifyReply, FastifyRequest } from 'fastify';

import { AuthError } from '../services/errors.js';

type RateLimitEntry = { count: number; resetAt: number };

const buckets = new Map<string, RateLimitEntry>();

export function clearRateLimitBuckets(): void {
  buckets.clear();
}

export function createRateLimit(options: { bucket: string; max: number; windowMs: number }) {
  return async function rateLimit(request: FastifyRequest, reply: FastifyReply): Promise<void> {
    const key = `${options.bucket}:${request.ip}`;
    const now = Date.now();
    const existing = buckets.get(key);

    if (!existing || existing.resetAt <= now) {
      buckets.set(key, { count: 1, resetAt: now + options.windowMs });
      void reply.header('x-ratelimit-limit', options.max);
      void reply.header('x-ratelimit-remaining', options.max - 1);
      return;
    }

    existing.count += 1;
    buckets.set(key, existing);
    const remaining = Math.max(options.max - existing.count, 0);
    void reply.header('x-ratelimit-limit', options.max);
    void reply.header('x-ratelimit-remaining', remaining);

    if (existing.count > options.max) {
      throw new AuthError(429, 'RATE_LIMITED', 'Too many requests for this endpoint');
    }
  };
}
