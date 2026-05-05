import fastify, { type FastifyInstance } from 'fastify';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const {
  notificationRepoMock,
  deviceRepoMock,
} = vi.hoisted(() => ({
  notificationRepoMock: {
    listByUser: vi.fn(),
    countUnread: vi.fn(),
    markRead: vi.fn(),
    markAllRead: vi.fn(),
  },
  deviceRepoMock: {
    upsert: vi.fn(),
    deactivate: vi.fn(),
    refreshToken: vi.fn(),
  },
}));

vi.mock('../../src/db.js', () => ({
  pgPool: {},
}));

vi.mock('../../src/repositories/notification.repository.js', () => ({
  NotificationRepository: vi.fn().mockImplementation(() => notificationRepoMock),
}));

vi.mock('../../src/repositories/device-token.repository.js', () => ({
  DeviceTokenRepository: vi.fn().mockImplementation(() => deviceRepoMock),
}));

const { notificationRoutes } = await import('../../src/controllers/notification.routes.js');

describe('notification routes integration', () => {
  let app: FastifyInstance;

  beforeEach(async () => {
    vi.clearAllMocks();
    app = fastify();
    await app.register(notificationRoutes);
  });

  afterEach(async () => {
    await app.close();
  });

  it('returns notifications and unread count for authenticated user', async () => {
    notificationRepoMock.listByUser.mockResolvedValue([
      { id: 'n-1', template_key: 'payment.completed', channel: 'in_app' },
    ]);
    notificationRepoMock.countUnread.mockResolvedValue(2);

    const res = await app.inject({
      method: 'GET',
      url: '/api/v1/notifications/me',
      headers: { 'x-user-id': 'user-1' },
    });

    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({
      notifications: [{ id: 'n-1', template_key: 'payment.completed', channel: 'in_app' }],
      unread: 2,
    });
    expect(notificationRepoMock.listByUser).toHaveBeenCalledWith('user-1', 30, 0);
    expect(notificationRepoMock.countUnread).toHaveBeenCalledWith('user-1');
  });

  it('marks all notifications as read', async () => {
    notificationRepoMock.markAllRead.mockResolvedValue(undefined);

    const res = await app.inject({
      method: 'PATCH',
      url: '/api/v1/notifications/read-all',
      headers: { 'x-user-id': 'user-2' },
    });

    expect(res.statusCode).toBe(204);
    expect(notificationRepoMock.markAllRead).toHaveBeenCalledWith('user-2');
  });
});
