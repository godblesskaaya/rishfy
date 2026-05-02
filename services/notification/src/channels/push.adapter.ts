import type { ChannelAdapter, SendParams, SendResult } from './channel.adapter.js';
import { logger } from '../logger.js';
import * as admin from 'firebase-admin';
import { DeviceTokenRepository } from '../repositories/device-token.repository.js';
import { pgPool } from '../db.js';

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
  private readonly deviceRepo = new DeviceTokenRepository(pgPool);

  async send(params: SendParams): Promise<SendResult> {
    const app = getApp();
    if (!app) {
      logger.debug({ userId: params.userId }, '[push] Firebase not configured, skipping');
      return { success: true };
    }

    // Resolve FCM token(s) — use provided token or look up from device_tokens table
    const tokens: string[] = params.fcmToken
      ? [params.fcmToken]
      : (await this.deviceRepo.getActiveTokensForUser(params.userId)).map((d) => d.fcm_token);

    if (tokens.length === 0) {
      logger.debug({ userId: params.userId }, '[push] No FCM tokens, skipping');
      return { success: true };
    }

    const results: SendResult[] = [];
    for (const token of tokens) {
      results.push(await this._sendToToken(app, token, params));
    }

    const failed = results.filter((r) => !r.success);
    return failed.length === 0
      ? { success: true, providerMessageId: results[0]?.providerMessageId }
      : { success: false, error: failed.map((r) => r.error).join(', ') };
  }

  private async _sendToToken(app: admin.app.App, token: string, params: SendParams): Promise<SendResult> {
    try {
      const messageId = await admin.messaging(app).send({
        token,
        notification: params.title ? { title: params.title, body: params.body } : undefined,
        data: params.data
          ? Object.fromEntries(Object.entries(params.data).map(([k, v]) => [k, String(v)]))
          : undefined,
        android: { priority: 'high' },
        apns: { payload: { aps: { sound: params.title ? 'default' : '' } } },
      });
      return { success: true, providerMessageId: messageId };
    } catch (err) {
      const errStr = String(err);
      // Invalidate token if FCM says it's unregistered/invalid
      if (errStr.includes('registration-token-not-registered') || errStr.includes('invalid-registration-token')) {
        logger.info({ token: token.slice(0, 20) }, '[push] Invalidating stale FCM token');
        await this.deviceRepo.deactivateByToken(token).catch(() => null);
      }
      logger.error({ err, userId: params.userId }, 'FCM send failed');
      return { success: false, error: errStr };
    }
  }

  /**
   * Silent push — no visible notification, just a data payload for state refresh.
   * Used for: booking confirmed, trip started, arrival detected.
   */
  async sendSilent(userId: string, data: Record<string, string>): Promise<void> {
    const app = getApp();
    if (!app) return;

    const tokens = await this.deviceRepo.getActiveTokensForUser(userId);
    await Promise.all(
      tokens.map(async (device) => {
        try {
          await admin.messaging(app).send({
            token: device.fcm_token,
            data,
            android: { priority: 'high' },
            apns: { payload: { aps: { contentAvailable: true } } },
          });
        } catch (err) {
          const errStr = String(err);
          if (errStr.includes('registration-token-not-registered')) {
            await this.deviceRepo.deactivateByToken(device.fcm_token).catch(() => null);
          }
        }
      }),
    );
  }
}
