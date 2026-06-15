import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { UserService } from '../services/user.service.js';
import { isAppError } from '../utils/errors.js';

function handleError(err: unknown, reply: import('fastify').FastifyReply) {
  if (isAppError(err)) {
    return reply.code(err.statusCode).send({ error: err.code, message: err.message });
  }
  throw err;
}

export async function adminRoutes(app: FastifyInstance, { svc }: { svc: UserService }) {
  app.get('/support-cases', async (req, reply) => {
    try {
      const userId = req.headers['x-user-id'] as string;
      if (!userId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      const { status, priority, limit = '50', offset = '0' } = req.query as Record<string, string | undefined>;
      const parsedStatus = z.enum(['open', 'waiting', 'resolved', 'closed']).optional().parse(status);
      const parsedPriority = z.enum(['low', 'normal', 'high', 'urgent']).optional().parse(priority);
      const cases = await svc.listSupportCasesForStaff({
        status: parsedStatus,
        priority: parsedPriority,
        limit: Number(limit),
        offset: Number(offset),
      });
      return reply.send({ cases, total: cases.length });
    } catch (err) { return handleError(err, reply); }
  });

  app.patch<{ Params: { caseId: string } }>('/support-cases/:caseId', async (req, reply) => {
    try {
      const userId = req.headers['x-user-id'] as string;
      if (!userId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      const body = z.object({
        status: z.enum(['open', 'waiting', 'resolved', 'closed']).optional(),
        priority: z.enum(['low', 'normal', 'high', 'urgent']).optional(),
        support_responded: z.boolean().optional(),
      }).parse(req.body ?? {});
      const supportCase = await svc.updateSupportCaseForStaff(req.params.caseId, {
        status: body.status,
        priority: body.priority,
        supportResponded: body.support_responded,
      });
      return reply.send(supportCase);
    } catch (err) { return handleError(err, reply); }
  });

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

  app.get('/reviews', async (req, reply) => {
    try {
      const { status, limit = '50', offset = '0' } = req.query as Record<string, string | undefined>;
      const parsedStatus = z.enum(['pending', 'approved', 'hidden']).optional().parse(status);
      const reviews = await svc.listRatingsForModeration(parsedStatus, Number(limit), Number(offset));
      return reply.send({ reviews, total: reviews.length });
    } catch (err) { return handleError(err, reply); }
  });

  app.post<{ Params: { ratingId: string } }>('/reviews/:ratingId/moderate', async (req, reply) => {
    try {
      const adminId = req.headers['x-user-id'] as string;
      if (!adminId) return reply.code(401).send({ error: 'UNAUTHENTICATED' });
      const body = z.object({
        status: z.enum(['approved', 'hidden']),
        hidden_reason: z.string().max(500).optional(),
      }).parse(req.body ?? {});
      const review = await svc.moderateRating(req.params.ratingId, {
        status: body.status,
        moderatedBy: adminId,
        hiddenReason: body.hidden_reason,
      });
      return reply.send(review);
    } catch (err) { return handleError(err, reply); }
  });
}
