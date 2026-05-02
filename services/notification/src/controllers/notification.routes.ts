import type { FastifyInstance } from 'fastify';
import { NotificationRepository } from '../repositories/notification.repository.js';
import { pgPool } from '../db.js';

const repo = new NotificationRepository(pgPool);

export async function notificationRoutes(app: FastifyInstance): Promise<void> {
  // GET /api/v1/notifications
  app.get('/api/v1/notifications', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });
    const { limit = 30, offset = 0 } = req.query as { limit?: number; offset?: number };
    const [notifications, unread] = await Promise.all([
      repo.listByUser(userId, limit, offset),
      repo.countUnread(userId),
    ]);
    return reply.send({ notifications, unread });
  });

  // PATCH /api/v1/notifications/:id/read
  app.patch('/api/v1/notifications/:id/read', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });
    const { id } = req.params as { id: string };
    await repo.markRead(id, userId);
    return reply.status(204).send();
  });

  // PATCH /api/v1/notifications/read-all
  app.patch('/api/v1/notifications/read-all', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });
    await repo.markAllRead(userId);
    return reply.status(204).send();
  });
}
