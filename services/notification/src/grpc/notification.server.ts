import * as grpc from '@grpc/grpc-js';
import * as protoLoader from '@grpc/proto-loader';
import * as path from 'path';
import { config } from '../config.js';
import { logger } from '../logger.js';
import { NotificationRepository } from '../repositories/notification.repository.js';
import { NotificationService } from '../services/notification.service.js';
import { pgPool } from '../db.js';
import IORedis from 'ioredis';
import type { NotificationRow } from '../repositories/notification.repository.js';

const PROTO_PATH = path.resolve(process.cwd(), 'shared/protos/notification.proto');

const packageDef = protoLoader.loadSync(PROTO_PATH, {
  keepCase: false,
  longs: String,
  enums: String,
  defaults: true,
  oneofs: true,
  includeDirs: [path.resolve(process.cwd(), 'shared/protos')],
});

const grpcObject = grpc.loadPackageDefinition(packageDef) as Record<string, unknown>;
const pkg = (grpcObject['rishfy'] as Record<string, unknown>)['notification'] as Record<string, unknown>;
const NotificationServiceDef = (pkg['v1'] as Record<string, unknown>)['NotificationService'] as { service: grpc.ServiceDefinition };

const repo = new NotificationRepository(pgPool);
const notifSvc = new NotificationService();

type Handler<Req, Res> = grpc.handleUnaryCall<Req, Res>;

function rowToProto(n: NotificationRow): Record<string, unknown> {
  return {
    notificationId: n.id,
    userId: n.user_id,
    channel: (n.channel ?? 'in_app').toUpperCase().replace('_', '_'),
    status: n.status === 'delivered' ? 'NOTIFICATION_STATUS_DELIVERED' : n.is_read ? 'NOTIFICATION_STATUS_READ' : 'NOTIFICATION_STATUS_SENT',
    title: n.title ?? '',
    body: n.body,
    data: n.data ? Object.fromEntries(Object.entries(n.data as Record<string, unknown>).map(([k, v]) => [k, String(v)])) : {},
    createdAt: n.created_at ? { seconds: String(Math.floor(new Date(n.created_at).getTime() / 1000)) } : null,
    sentAt: n.sent_at ? { seconds: String(Math.floor(new Date(n.sent_at).getTime() / 1000)) } : null,
  };
}

interface SendReq {
  userId: string; channels: string[]; templateId: string;
  templateVariables: Record<string, string>;
  title: string; body: string; data: Record<string, string>;
  idempotencyKey: string; locale: string;
}
interface SendBatchReq { userIds: string[]; channels: string[]; templateId: string; templateVariables: Record<string, string>; batchId: string }
interface RegisterDeviceReq { userId: string; deviceId: string; fcmToken: string; platform: string }
interface UnregisterDeviceReq { userId: string; deviceId: string }
interface GetHistoryReq { userId: string; unreadOnly: boolean; pagination: { limit: number; cursor: string } }
interface MarkReadReq { userId: string; notificationIds: string[] }
interface SendOTPReq { phoneNumber: string; purpose: string; locale: string }

const sendNotification: Handler<SendReq, unknown> = async (call, callback) => {
  try {
    const r = call.request;
    const redis = new IORedis(config.REDIS_URL, { maxRetriesPerRequest: null });
    const channels = (r.channels ?? []).map((c: string) =>
      c.replace('NOTIFICATION_CHANNEL_', '').toLowerCase()
    ).filter((c: string) => ['push', 'sms', 'in_app'].includes(c));

    await notifSvc.enqueue(redis, {
      userId: r.userId,
      templateKey: r.templateId || 'direct',
      lang: r.locale || 'en',
      channels: channels.length ? channels : ['in_app'],
      vars: r.templateVariables ?? {},
      data: r.data ? Object.fromEntries(Object.entries(r.data).map(([k, v]) => [k, v])) : undefined,
    });

    void redis.quit();
    callback(null, { notifications: [] });
  } catch (err) {
    logger.error({ err }, 'gRPC sendNotification error');
    callback({ code: grpc.status.INTERNAL, message: String(err) } as grpc.ServiceError);
  }
};

const sendBatchNotification: Handler<SendBatchReq, unknown> = async (call, callback) => {
  try {
    const { userIds, batchId } = call.request;
    callback(null, { batchId: batchId || '', queuedCount: userIds?.length ?? 0, rejectedCount: 0, rejectionUserIds: [] });
  } catch (err) {
    callback({ code: grpc.status.INTERNAL, message: String(err) } as grpc.ServiceError);
  }
};

const registerDevice: Handler<RegisterDeviceReq, unknown> = async (call, callback) => {
  try {
    const { userId, fcmToken } = call.request;
    logger.info({ userId, fcmToken }, 'Device registered (no-op — token stored per user lookup)');
    callback(null, { registered: true });
  } catch (err) {
    callback({ code: grpc.status.INTERNAL, message: String(err) } as grpc.ServiceError);
  }
};

const unregisterDevice: Handler<UnregisterDeviceReq, unknown> = async (call, callback) => {
  try {
    logger.info({ userId: call.request.userId }, 'Device unregistered');
    callback(null, { unregistered: true });
  } catch (err) {
    callback({ code: grpc.status.INTERNAL, message: String(err) } as grpc.ServiceError);
  }
};

const getNotificationHistory: Handler<GetHistoryReq, unknown> = async (call, callback) => {
  try {
    const { userId, unreadOnly } = call.request;
    const limit = call.request.pagination?.limit || 30;
    const rows = await repo.listByUser(userId, limit, 0);
    const filtered = unreadOnly ? rows.filter((n) => !n.is_read) : rows;
    const unreadCount = await repo.countUnread(userId);
    callback(null, { notifications: filtered.map(rowToProto), unreadCount, pagination: {} });
  } catch (err) {
    callback({ code: grpc.status.INTERNAL, message: String(err) } as grpc.ServiceError);
  }
};

const markAsRead: Handler<MarkReadReq, unknown> = async (call, callback) => {
  try {
    const { userId, notificationIds } = call.request;
    if (!notificationIds?.length) {
      await repo.markAllRead(userId);
      callback(null, { markedCount: -1 });
    } else {
      await Promise.all(notificationIds.map((id) => repo.markRead(id, userId)));
      callback(null, { markedCount: notificationIds.length });
    }
  } catch (err) {
    callback({ code: grpc.status.INTERNAL, message: String(err) } as grpc.ServiceError);
  }
};

const sendOTP: Handler<SendOTPReq, unknown> = async (call, callback) => {
  try {
    const { phoneNumber, locale } = call.request;
    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    const redis = new IORedis(config.REDIS_URL, { maxRetriesPerRequest: null });
    const otpRef = `otp:${phoneNumber}:${Date.now()}`;
    await redis.setex(otpRef, 300, otp);
    void redis.quit();

    const lang = locale || 'en';
    await notifSvc.dispatch({
      userId: phoneNumber,
      templateKey: 'otp.verify',
      lang,
      channels: ['sms'],
      vars: { otp },
      phone: phoneNumber,
    });

    callback(null, { otpReference: otpRef, expiresInSeconds: 300, cooldownSeconds: 60 });
  } catch (err) {
    logger.error({ err }, 'gRPC sendOTP error');
    callback({ code: grpc.status.INTERNAL, message: String(err) } as grpc.ServiceError);
  }
};

export function startGrpcServer(): grpc.Server {
  const server = new grpc.Server();
  server.addService(NotificationServiceDef.service, {
    sendNotification,
    sendBatchNotification,
    registerDevice,
    unregisterDevice,
    getNotificationHistory,
    markAsRead,
    sendOTP,
  });

  server.bindAsync(
    `0.0.0.0:${config.GRPC_PORT}`,
    grpc.ServerCredentials.createInsecure(),
    (err, port) => {
      if (err) { logger.error({ err }, 'gRPC bind failed'); process.exit(1); }
      logger.info({ port }, 'notification-service gRPC server listening');
    },
  );

  return server;
}
