import { readFileSync } from 'node:fs';
import * as admin from 'firebase-admin';
import type { ChannelAdapter, SendParams, SendResult } from './channel.adapter.js';
import { logger } from '../logger.js';
import { DeviceTokenRepository } from '../repositories/device-token.repository.js';
import { pgPool } from '../db.js';

let appState:
  | { app: admin.app.App }
  | { app: null; code: string; reason: string }
  | null = null;

function getErrorMessage(err: unknown): string {
  if (err instanceof Error) return err.message;
  return String(err);
}

function getFirebaseErrorCode(err: unknown): string | undefined {
  if (err && typeof err === 'object') {
    const errorInfo = (err as { errorInfo?: { code?: unknown } }).errorInfo;
    if (errorInfo && typeof errorInfo.code === 'string') {
      return errorInfo.code;
    }

    const code = (err as { code?: unknown }).code;
    if (typeof code === 'string') {
      return code;
    }
  }
  return undefined;
}

function isInvalidRegistrationToken(code: string | undefined, message: string): boolean {
  return code === 'messaging/registration-token-not-registered'
    || code === 'messaging/invalid-registration-token'
    || message.includes('registration-token-not-registered')
    || message.includes('invalid-registration-token');
}

function getServiceAccount(): admin.ServiceAccount | null {
  const serviceAccountJson = process.env['FIREBASE_SERVICE_ACCOUNT_JSON'];
  if (serviceAccountJson) {
    return JSON.parse(serviceAccountJson) as admin.ServiceAccount;
  }

  const credPath = process.env['FIREBASE_SERVICE_ACCOUNT_PATH'];
  if (!credPath) return null;

  const raw = readFileSync(credPath, 'utf8');
  return JSON.parse(raw) as admin.ServiceAccount;
}

function resolveApp(): { app: admin.app.App | null; code?: string; reason?: string } {
  if (appState) return appState;

  const projectId = process.env['FIREBASE_PROJECT_ID'];
  const hasServiceAccount = Boolean(
    process.env['FIREBASE_SERVICE_ACCOUNT_JSON'] || process.env['FIREBASE_SERVICE_ACCOUNT_PATH'],
  );

  if (!hasServiceAccount && !projectId) {
    appState = {
      app: null,
      code: 'FIREBASE_NOT_CONFIGURED',
      reason: 'Neither FIREBASE_PROJECT_ID nor a Firebase service account was provided.',
    };
    return appState;
  }

  try {
    const serviceAccount = getServiceAccount();
    const initOptions = serviceAccount
      ? {
          credential: admin.credential.cert(serviceAccount),
          projectId: serviceAccount.projectId ?? projectId,
        }
      : { projectId };

    appState = { app: admin.initializeApp(initOptions) };
    return appState;
  } catch (err) {
    const existingApp = admin.apps[0] ?? null;
    if (existingApp) {
      logger.warn({ err: getErrorMessage(err) }, 'Firebase init failed; reusing existing app');
      appState = { app: existingApp };
      return appState;
    }

    const reason = getErrorMessage(err);
    logger.warn({
      code: 'FIREBASE_CONFIG_ERROR',
      reason,
      hasProjectId: Boolean(projectId),
      hasServiceAccount,
    }, 'Push delivery disabled because Firebase configuration could not be loaded');

    appState = {
      app: null,
      code: 'FIREBASE_CONFIG_ERROR',
      reason,
    };
    return appState;
  }
}

function maskToken(token: string): string {
  if (token.length <= 8) return token;
  return `...${token.slice(-8)}`;
}

export function __resetPushAdapterForTests(): void {
  appState = null;
}

export class PushAdapter implements ChannelAdapter {
  private readonly deviceRepo = new DeviceTokenRepository(pgPool);

  async send(params: SendParams): Promise<SendResult> {
    const resolved = resolveApp();
    if (!resolved.app) {
      return {
        status: 'skipped',
        code: resolved.code,
        error: resolved.reason,
      };
    }

    const tokens = params.fcmToken
      ? [params.fcmToken]
      : (await this.deviceRepo.getActiveTokensForUser(params.userId)).map((device) => device.fcm_token);

    if (tokens.length === 0) {
      logger.info({ userId: params.userId }, '[push] No active FCM tokens');
      return {
        status: 'skipped',
        code: 'NO_ACTIVE_TOKENS',
        error: 'No active FCM tokens found for user.',
      };
    }

    const results = await Promise.all(
      tokens.map(async (token) => this.sendToToken(resolved.app!, token, params)),
    );

    const delivered = results.filter((result) => result.status === 'sent');
    const failed = results.filter((result) => result.status === 'failed');
    logger.info({
      userId: params.userId,
      tokensAttempted: tokens.length,
      deliveredCount: delivered.length,
      failedCount: failed.length,
    }, 'FCM delivery attempt completed');

    if (delivered.length > 0) {
      if (failed.length > 0) {
        logger.warn({
          userId: params.userId,
          failedCodes: failed.map((result) => result.code).filter(Boolean),
        }, 'FCM delivery partially failed');
      }

      return {
        status: 'sent',
        providerMessageId: delivered[0]?.providerMessageId,
        code: failed.length > 0 ? 'FCM_PARTIAL_FAILURE' : undefined,
        error: failed.length > 0
          ? failed.map((result) => result.error ?? result.code ?? 'FCM_SEND_FAILED').join('; ')
          : undefined,
      };
    }

    return {
      status: 'failed',
      code: failed[0]?.code ?? 'FCM_SEND_FAILED',
      error: failed.map((result) => result.error ?? result.code ?? 'FCM_SEND_FAILED').join('; '),
    };
  }

  private async sendToToken(
    app: admin.app.App,
    token: string,
    params: SendParams,
  ): Promise<SendResult> {
    try {
      const messageId = await admin.messaging(app).send({
        token,
        notification: params.title ? { title: params.title, body: params.body } : undefined,
        data: params.data
          ? Object.fromEntries(Object.entries(params.data).map(([key, value]) => [key, String(value)]))
          : undefined,
        android: { priority: 'high' },
        apns: { payload: { aps: { sound: params.title ? 'default' : '' } } },
      });

      logger.info({
        userId: params.userId,
        token: maskToken(token),
        providerMessageId: messageId,
      }, 'FCM push delivered');

      return { status: 'sent', providerMessageId: messageId };
    } catch (err) {
      const code = getFirebaseErrorCode(err);
      const message = getErrorMessage(err);
      if (isInvalidRegistrationToken(code, message)) {
        logger.info({ token: maskToken(token), code }, '[push] Invalidating stale FCM token');
        await this.deviceRepo.deactivateByToken(token).catch(() => null);
      }

      logger.error({
        err: message,
        code,
        userId: params.userId,
        token: maskToken(token),
      }, 'FCM send failed');

      return {
        status: 'failed',
        code: code ?? 'FCM_SEND_FAILED',
        error: message,
      };
    }
  }

  async sendSilent(userId: string, data: Record<string, string>): Promise<void> {
    const resolved = resolveApp();
    if (!resolved.app) {
      logger.warn({ userId, code: resolved.code, reason: resolved.reason }, 'Silent push skipped');
      return;
    }

    const tokens = await this.deviceRepo.getActiveTokensForUser(userId);
    if (tokens.length === 0) {
      logger.info({ userId }, '[push] No active FCM tokens for silent delivery');
      return;
    }

    const results = await Promise.all(tokens.map(async (device) => {
      try {
        await admin.messaging(resolved.app!).send({
          token: device.fcm_token,
          data,
          android: { priority: 'high' },
          apns: { payload: { aps: { contentAvailable: true } } },
        });
        return { status: 'sent' as const };
      } catch (err) {
        const code = getFirebaseErrorCode(err);
        const message = getErrorMessage(err);
        if (isInvalidRegistrationToken(code, message)) {
          await this.deviceRepo.deactivateByToken(device.fcm_token).catch(() => null);
        }

        logger.error({
          err: message,
          code,
          userId,
          token: maskToken(device.fcm_token),
        }, 'Silent FCM send failed');

        return { status: 'failed' as const };
      }
    }));

    logger.info({
      userId,
      tokensAttempted: tokens.length,
      deliveredCount: results.filter((result) => result.status === 'sent').length,
      failedCount: results.filter((result) => result.status === 'failed').length,
    }, 'Silent FCM delivery attempt completed');
  }
}
