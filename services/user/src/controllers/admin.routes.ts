import type { FastifyInstance } from 'fastify';
import type { UserService } from '../services/user.service.js';
import { isAppError } from '../utils/errors.js';

function handleError(err: unknown, reply: import('fastify').FastifyReply) {
  if (isAppError(err)) {
    return reply.code(err.statusCode).send({ error: err.code, message: err.message });
  }
  throw err;
}

export async function adminRoutes(app: FastifyInstance, { svc }: { svc: UserService }) {
  // GET /admin/drivers/pending-verification
  app.get('/drivers/pending-verification', async (req, reply) => {
    try {
      const { limit = '50', offset = '0' } = req.query as Record<string, string>;
      const drivers = await svc.listPendingDrivers(Number(limit), Number(offset));
      return reply.send({ drivers, total: drivers.length });
    } catch (err) { return handleError(err, reply); }
  });

  // POST /admin/drivers/:userId/approve
  app.post<{ Params: { userId: string } }>('/drivers/:userId/approve', async (req, reply) => {
    try {
      const profile = await svc.approveDriverProfile(req.params.userId);
      return reply.send({ success: true, profile });
    } catch (err) { return handleError(err, reply); }
  });

  // POST /admin/drivers/:userId/reject
  app.post<{ Params: { userId: string }; Body: { reason?: string } }>('/drivers/:userId/reject', async (req, reply) => {
    try {
      const profile = await svc.rejectDriverProfile(req.params.userId);
      return reply.send({ success: true, profile });
    } catch (err) { return handleError(err, reply); }
  });
}
