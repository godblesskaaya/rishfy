import fastifyCors from '@fastify/cors';
import fastifyHelmet from '@fastify/helmet';
import fastifySensible from '@fastify/sensible';
import fastify, { type FastifyBaseLogger, type FastifyInstance, type RawServerDefault } from 'fastify';

import { config } from './config.js';
import { pgPool } from './db.js';
import { redis } from './redis.js';
import { logger } from './logger.js';
import { routeRoutes } from './controllers/route.routes.js';
import { RouteService } from './services/route.service.js';

export async function buildApp(): Promise<FastifyInstance> {
  const app: FastifyInstance<RawServerDefault> = fastify({
    logger: logger as unknown as FastifyBaseLogger,
    requestIdHeader: 'x-request-id',
    disableRequestLogging: false,
    bodyLimit: 1024 * 1024,
  });

  await app.register(fastifyHelmet, { global: true });
  await app.register(fastifyCors, { origin: true, credentials: true });
  await app.register(fastifySensible);

  app.get('/health', async () => ({
    status: 'healthy',
    service: config.SERVICE_NAME,
    timestamp: new Date().toISOString(),
  }));

  app.get('/ready', async () => ({ status: 'ready' }));

  app.get('/metrics', async (_req, reply) => {
    const { register } = await import('prom-client');
    reply.header('Content-Type', register.contentType);
    return register.metrics();
  });

  const svc = new RouteService(pgPool, redis);
  await app.register(routeRoutes, { prefix: '/api/v1/routes', svc });

  return app;
}
