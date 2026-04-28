import type { FastifyPluginAsync } from 'fastify';

import { verifyAccessToken } from '../services/token.service.js';

export const internalRoutes: FastifyPluginAsync = async (app) => {
  app.route({
    method: ['GET', 'POST'],
    url: '/verify-token',
    handler: async (request, reply) => {
      const header = request.headers.authorization;
      if (!header || !header.toLowerCase().startsWith('bearer ')) {
        return reply.status(401).send({ error: 'UNAUTHORIZED', message: 'Missing bearer token' });
      }

      const token = header.slice(7).trim();
      try {
        const claims = verifyAccessToken(token);
        void reply.header('x-user-id', claims.sub);
        void reply.header('x-user-role', claims.role);
        return reply.status(200).send({ sub: claims.sub, role: claims.role });
      } catch {
        return reply.status(401).send({ error: 'UNAUTHORIZED', message: 'Invalid or expired token' });
      }
    },
  });
};
