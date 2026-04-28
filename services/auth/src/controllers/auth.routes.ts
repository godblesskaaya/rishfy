import type { FastifyPluginAsync } from 'fastify';

import {
  loginSchema,
  logoutSchema,
  refreshTokenSchema,
  registerSchema,
  resetPasswordSchema,
  verifyOtpSchema,
} from './auth.schemas.js';
import { createRateLimit } from '../middleware/rate-limit.js';
import type { AuthService } from '../services/auth.service.js';
import { AuthError } from '../services/errors.js';

export interface AuthRoutesOptions {
  authService: AuthService;
}

export const authRoutes: FastifyPluginAsync<AuthRoutesOptions> = async (app, options) => {
  const { authService } = options;

  app.setErrorHandler((error, _request, reply) => {
    if (error instanceof AuthError) {
      return reply.status(error.statusCode).send({
        error: error.code,
        message: error.message,
        details: error.details,
      });
    }

    if ('issues' in error && Array.isArray((error as { issues?: unknown[] }).issues)) {
      return reply.status(400).send({
        error: 'VALIDATION_ERROR',
        message: error.message,
      });
    }

    app.log.error({ err: error }, 'Unhandled auth route error');
    return reply.status(500).send({ error: 'INTERNAL_SERVER_ERROR', message: 'Unexpected error' });
  });

  app.post('/register', { preHandler: createRateLimit({ bucket: 'auth-register', max: 2, windowMs: 60_000 }) }, async (request, reply) => {
    const payload = registerSchema.parse(request.body);
    const result = await authService.register(payload);
    return reply.status(201).send(result);
  });

  app.post('/verify-otp', { preHandler: createRateLimit({ bucket: 'auth-otp', max: 3, windowMs: 60_000 }) }, async (request) => {
    const payload = verifyOtpSchema.parse(request.body);
    return authService.verifyOtp(payload);
  });

  app.post('/login', { preHandler: createRateLimit({ bucket: 'auth-login', max: 5, windowMs: 60_000 }) }, async (request) => {
    const payload = loginSchema.parse(request.body);
    return authService.login(payload);
  });

  app.post('/refresh-token', async (request) => {
    const payload = refreshTokenSchema.parse(request.body);
    return authService.refreshToken(payload);
  });

  app.post('/logout', async (request) => {
    const payload = logoutSchema.parse(request.body);
    return authService.logout(payload);
  });

  app.post('/reset-password', { preHandler: createRateLimit({ bucket: 'auth-reset', max: 3, windowMs: 60_000 }) }, async (request) => {
    const payload = resetPasswordSchema.parse(request.body);
    return authService.resetPassword(payload);
  });
};
