import type { FastifyPluginAsync } from 'fastify';
import { createHash } from 'node:crypto';

import { verifyPassword } from '../services/password.service.js';
import { issueAuthTokens } from '../services/token.service.js';
import { AuthError } from '../services/errors.js';
import type { AuthRepository } from '../repositories/auth.repository.js';

export interface AdminRoutesOptions {
  repository: AuthRepository;
}

export const adminRoutes: FastifyPluginAsync<AdminRoutesOptions> = async (app, { repository }) => {
  const hashRefreshToken = (token: string): string =>
    createHash('sha256').update(token).digest('hex');

  app.setErrorHandler((error, _req, reply) => {
    if (error instanceof AuthError) {
      return reply.status(error.statusCode).send({ error: error.code, message: error.message });
    }
    app.log.error({ err: error }, 'Admin route error');
    return reply.status(500).send({ error: 'INTERNAL_SERVER_ERROR' });
  });

  /**
   * POST /api/v1/auth/admin/login
   * Accepts { phone_number, password } — admin accounts only.
   * Returns the shape expected by the Next.js admin panel.
   */
  app.post('/admin/login', async (req, reply) => {
    const { phone_number, password } = req.body as { phone_number?: string; password?: string };

    if (!phone_number || !password) {
      return reply.status(400).send({ error: 'MISSING_FIELDS', message: 'phone_number and password are required' });
    }

    const user = await repository.findUserByPhone(phone_number);
    if (!user) {
      throw new AuthError(401, 'INVALID_CREDENTIALS', 'Invalid credentials');
    }

    if (user.lockedUntil && user.lockedUntil.getTime() > Date.now()) {
      throw new AuthError(423, 'ACCOUNT_LOCKED', 'Account temporarily locked');
    }

    if (!verifyPassword(password, user.passwordHash)) {
      user.failedLoginAttempts += 1;
      if (user.failedLoginAttempts >= 5) {
        user.lockedUntil = new Date(Date.now() + 15 * 60 * 1000);
      }
      await repository.updateUser(user);
      throw new AuthError(401, 'INVALID_CREDENTIALS', 'Invalid credentials');
    }

    if (user.role !== 'admin') {
      throw new AuthError(403, 'FORBIDDEN', 'Admin access only');
    }

    // Issue tokens (two-step: provisional → real session id)
    // JWT sub = profileId (UUID) so Nginx x-user-id is always a UUID
    const provisional = issueAuthTokens({ userId: user.profileId, role: user.role, sessionId: 'pending' });
    const session = await repository.createRefreshSession(
      user.id, // auth_db integer id for the FK
      hashRefreshToken(provisional.refreshToken),
      new Date(Date.now() + provisional.refreshExpiresInSeconds * 1000),
    );
    const tokens = issueAuthTokens({ userId: user.profileId, role: user.role, sessionId: session.id });
    session.token = hashRefreshToken(tokens.refreshToken);
    await repository.updateRefreshSession(session);

    // Reset failed attempts on success
    user.failedLoginAttempts = 0;
    user.lockedUntil = undefined;
    await repository.updateUser(user);

    // Split fullName into first/last (best-effort; DB has no separate columns)
    const nameParts = (user.fullName ?? 'Admin').trim().split(/\s+/);
    const firstName = nameParts[0] ?? 'Admin';
    const lastName = nameParts.slice(1).join(' ');

    return reply.send({
      access_token: tokens.accessToken,
      refresh_token: tokens.refreshToken,
      expires_in: tokens.expiresInSeconds,
      user: {
        user_id: user.profileId,
        first_name: firstName,
        last_name: lastName,
        phone_number: user.phoneNumber ?? '',
        email: user.email,
        role: user.role,
        permissions: ['admin'],
      },
    });
  });
};
