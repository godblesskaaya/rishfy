import fastifyCors from '@fastify/cors';
import fastifyHelmet from '@fastify/helmet';
import fastifySensible from '@fastify/sensible';
import fastify, { type FastifyBaseLogger, type FastifyInstance, type RawServerDefault } from 'fastify';
import type { Producer } from 'kafkajs';

import { config, isTest } from './config.js';
import { adminRoutes } from './controllers/admin.routes.js';
import { authRoutes } from './controllers/auth.routes.js';
import { internalRoutes } from './controllers/internal.routes.js';
import { publishUserRegistered } from './events/auth.events.js';
import { logger } from './logger.js';
import { InMemoryAuthRepository } from './repositories/auth.repository.js';
import { PgAuthRepository } from './repositories/pg-auth.repository.js';
import { AuthService } from './services/auth.service.js';

export interface BuildAppOptions {
  authService?: AuthService;
  authEventsProducer?: Producer | null;
}

export async function buildApp(options: BuildAppOptions = {}): Promise<FastifyInstance> {
  const app: FastifyInstance<RawServerDefault> = fastify({
    logger: logger as unknown as FastifyBaseLogger,
    requestIdHeader: 'x-request-id',
    disableRequestLogging: false,
    bodyLimit: 1024 * 1024,
  });

  // Use real DB repository in non-test environments
  const repository = isTest ? new InMemoryAuthRepository() : new PgAuthRepository();

  const eventProducer = options.authEventsProducer ?? null;
  const authService = options.authService ?? new AuthService({
    repository,
    otpSender: async ({ destination, code, purpose }) => {
      app.log.info({ destination, code, purpose }, 'Mock OTP dispatched');
    },
    userRegisteredPublisher: eventProducer
      ? (event) => publishUserRegistered(eventProducer, event)
      : undefined,
  });

  await app.register(fastifyHelmet, { global: true });
  await app.register(fastifyCors, {
    origin: true,
    credentials: true,
  });
  await app.register(fastifySensible);

  app.get('/health', async () => ({
    status: 'healthy',
    service: config.SERVICE_NAME,
    timestamp: new Date().toISOString(),
  }));

  app.get('/ready', async () => ({ status: 'ready' }));

  app.get('/metrics', async (_req, reply) => {
    const { register } = await import('prom-client');
    void reply.header('Content-Type', register.contentType);
    return register.metrics();
  });

  await app.register(authRoutes, {
    prefix: '/api/v1/auth',
    authService,
  });

  await app.register(adminRoutes, {
    prefix: '/api/v1/auth',
    repository,
  });

  await app.register(internalRoutes, { prefix: '/internal' });

  return app;
}
