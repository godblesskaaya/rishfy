import fastifyCors from '@fastify/cors';
import fastifyHelmet from '@fastify/helmet';
import fastifySensible from '@fastify/sensible';
import fastify, { type FastifyBaseLogger, type FastifyInstance, type RawServerDefault } from 'fastify';

import { config } from './config.js';
import { logger } from './logger.js';

export async function buildApp(): Promise<FastifyInstance<RawServerDefault>> {
  const app: FastifyInstance<RawServerDefault> = fastify({
    logger: logger as unknown as FastifyBaseLogger,
    requestIdHeader: 'x-request-id',
    disableRequestLogging: false,
    bodyLimit: 1024 * 1024, // 1MB
  });

  // Security
  await app.register(fastifyHelmet, { global: true });
  await app.register(fastifyCors, {
    origin: true, // Lock down in production via env
    credentials: true,
  });
  await app.register(fastifySensible);

  // Health checks
  app.get('/health', async () => ({
    status: 'healthy',
    service: config.SERVICE_NAME,
    timestamp: new Date().toISOString(),
  }));

  app.get('/ready', async () => {
    // TODO: check DB, Redis, Kafka connectivity
    return { status: 'ready' };
  });

  // Prometheus metrics
  app.get('/metrics', async (_req, reply) => {
    const { register } = await import('prom-client');
    reply.header('Content-Type', register.contentType);
    return register.metrics();
  });

  const { notificationRoutes } = await import('./controllers/notification.routes.js');
  await app.register(notificationRoutes);

  return app;
}
