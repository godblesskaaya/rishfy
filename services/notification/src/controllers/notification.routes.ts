import type { FastifyInstance } from 'fastify';
import { NotificationRepository } from '../repositories/notification.repository.js';
import { DeviceTokenRepository } from '../repositories/device-token.repository.js';
import { pgPool } from '../db.js';

const repo = new NotificationRepository(pgPool);
const deviceRepo = new DeviceTokenRepository(pgPool);

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

  // POST /api/v1/devices — register FCM device token
  app.post('/api/v1/devices', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });
    const body = req.body as {
      deviceId: string;
      fcmToken: string;
      platform: 'ios' | 'android';
      appVersion?: string;
    };
    const token = await deviceRepo.upsert({
      userId,
      deviceId: body.deviceId,
      fcmToken: body.fcmToken,
      platform: body.platform,
      appVersion: body.appVersion,
    });
    return reply.status(201).send({ deviceId: token.device_id, registered: true });
  });

  // DELETE /api/v1/devices/:deviceId — unregister on logout
  app.delete('/api/v1/devices/:deviceId', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });
    const { deviceId } = req.params as { deviceId: string };
    await deviceRepo.deactivate(userId, deviceId);
    return reply.status(204).send();
  });

  // PATCH /api/v1/devices/:deviceId/token — refresh FCM token
  app.patch('/api/v1/devices/:deviceId/token', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });
    const { deviceId } = req.params as { deviceId: string };
    const { fcmToken } = req.body as { fcmToken: string };
    await deviceRepo.refreshToken(userId, deviceId, fcmToken);
    return reply.status(204).send();
  });
}
