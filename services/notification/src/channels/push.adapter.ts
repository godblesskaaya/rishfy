import type { ChannelAdapter, SendParams, SendResult } from './channel.adapter.js';
import { logger } from '../logger.js';
import * as admin from 'firebase-admin';

let _app: admin.app.App | null = null;

function getApp(): admin.app.App | null {
  if (_app) return _app;
  const credPath = process.env['FIREBASE_SERVICE_ACCOUNT_PATH'];
  const projectId = process.env['FIREBASE_PROJECT_ID'];
  if (!credPath && !projectId) return null;

  try {
    if (credPath) {
      _app = admin.initializeApp({
        credential: admin.credential.cert(credPath),
      });
    } else {
      _app = admin.initializeApp({ projectId });
    }
  } catch {
    _app = admin.apps[0] ?? null;
  }
  return _app;
}

export class PushAdapter implements ChannelAdapter {
  async send(params: SendParams): Promise<SendResult> {
    const app = getApp();
    if (!app || !params.fcmToken) {
      logger.debug({ userId: params.userId }, '[push] No FCM token or Firebase not configured, skipping');
      return { success: true };
    }

    try {
      const messageId = await admin.messaging(app).send({
        token: params.fcmToken,
        notification: {
          title: params.title,
          body: params.body,
        },
        data: params.data
          ? Object.fromEntries(Object.entries(params.data).map(([k, v]) => [k, String(v)]))
          : undefined,
        android: { priority: 'high' },
        apns: { payload: { aps: { sound: 'default' } } },
      });
      return { success: true, providerMessageId: messageId };
    } catch (err) {
      logger.error({ err, userId: params.userId }, 'FCM send failed');
      return { success: false, error: String(err) };
    }
  }
}
