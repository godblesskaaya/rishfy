import { Queue, Worker } from 'bullmq';
import IORedis from 'ioredis';
import { NotificationRepository } from '../repositories/notification.repository.js';
import { renderTemplate } from './template.renderer.js';
import { PushAdapter } from '../channels/push.adapter.js';
import { SmsAdapter } from '../channels/sms.adapter.js';
import { InAppAdapter } from '../channels/in-app.adapter.js';
import type { ChannelAdapter } from '../channels/channel.adapter.js';
import { logger } from '../logger.js';
import { pgPool } from '../db.js';
import { config } from '../config.js';

export const NOTIF_QUEUE = 'notifications';

const CHANNELS: Record<string, ChannelAdapter> = {
  push: new PushAdapter(),
  sms: new SmsAdapter(),
  in_app: new InAppAdapter(),
};

export interface DispatchParams {
  userId: string;
  templateKey: string;
  lang?: string;
  channels: string[];
  vars: Record<string, string | number>;
  fallbackTitle?: string;
  fallbackBody?: string;
  sourceEventType?: string;
  sourceEventId?: string;
  fcmToken?: string;
  phone?: string;
  data?: Record<string, unknown>;
}

export class NotificationService {
  private readonly repo: NotificationRepository;

  constructor() {
    this.repo = new NotificationRepository(pgPool);
  }

  async dispatch(params: DispatchParams): Promise<void> {
    const lang = params.lang ?? 'en';
    const eventType = params.sourceEventType ?? params.templateKey;
    const category = categoryFor(eventType);
    const enabled = isCriticalNotification(eventType)
      ? true
      : await this.repo.isCategoryEnabled(params.userId, category);
    if (!enabled) {
      logger.info({
        userId: params.userId,
        category,
        templateKey: params.templateKey,
        sourceEventType: params.sourceEventType,
      }, 'Notification skipped by user preference');
      return;
    }
    await Promise.all(
      params.channels.map(async (channel) => {
        const tmpl = await this.repo.getTemplate(params.templateKey, lang, channel);
        if (!tmpl && !params.fallbackBody) {
          logger.warn({ key: params.templateKey, lang, channel }, 'Template not found');
          return;
        }
        const bodyTemplate = tmpl ? tmpl.body_template : params.fallbackBody!;
        const body = renderTemplate(bodyTemplate, params.vars);
        const title = tmpl?.subject
          ? renderTemplate(tmpl.subject, params.vars)
          : (params.fallbackTitle ? renderTemplate(params.fallbackTitle, params.vars) : undefined);

        const notif = await this.repo.create({
          userId: params.userId,
          templateKey: params.templateKey,
          channel,
          title,
          body,
          data: params.data,
          sourceEventType: params.sourceEventType,
          sourceEventId: params.sourceEventId,
        });

        const adapter = CHANNELS[channel];
        if (!adapter) return;

        try {
          const result = await adapter.send({
            userId: params.userId,
            title,
            body,
            data: params.data,
            fcmToken: params.fcmToken,
            phone: params.phone,
          });
          if (result.status === 'sent') {
            await this.repo.markDelivered(notif.id, result.providerMessageId);
          } else if (result.status === 'skipped') {
            await this.repo.markSkipped(notif.id, result.error ?? result.code ?? 'SKIPPED');
            logger.warn({
              notifId: notif.id,
              channel,
              code: result.code,
              reason: result.error,
            }, 'Notification delivery skipped');
          } else {
            await this.repo.markFailed(notif.id, result.error ?? result.code ?? 'UNKNOWN');
            logger.error({
              notifId: notif.id,
              channel,
              code: result.code,
              reason: result.error,
            }, 'Notification delivery failed');
          }
        } catch (err) {
          await this.repo.markFailed(notif.id, String(err));
          logger.error({ err, notifId: notif.id }, 'Channel adapter send failed');
        }
      }),
    );
  }

  async startQueue(connection: IORedis): Promise<{ queue: Queue; worker: Worker }> {
    const queue = new Queue(NOTIF_QUEUE, { connection });
    const worker = new Worker(
      NOTIF_QUEUE,
      async (job) => {
        await this.dispatch(job.data as DispatchParams);
      },
      {
        connection,
        concurrency: 20,
      },
    );
    worker.on('failed', (job, err) => logger.error({ jobId: job?.id, err }, 'Notification job failed'));
    return { queue, worker };
  }

  async enqueue(connection: IORedis, params: DispatchParams, priority = 5): Promise<void> {
    const queue = new Queue(NOTIF_QUEUE, { connection });
    await queue.add('send', params, {
      priority,
      attempts: config.NOTIF_QUEUE_ATTEMPTS,
      backoff: {
        type: 'exponential',
        delay: config.NOTIF_QUEUE_BACKOFF_MS,
      },
      removeOnComplete: 2000,
      removeOnFail: 5000,
    });
  }
}

function isCriticalNotification(type: string): boolean {
  const normalized = type.toLowerCase().replaceAll('.', '_');
  return normalized.includes('emergency') ||
    normalized.includes('sos') ||
    normalized.includes('safety') ||
    normalized.includes('no_show') ||
    normalized.startsWith('system_critical');
}

function categoryFor(type: string): 'bookings' | 'trips' | 'payments' | 'promotions' | 'system' {
  const normalized = type.toLowerCase().replaceAll('.', '_');
  if (normalized.startsWith('booking_')) return 'bookings';
  if (normalized.startsWith('trip_') ||
      normalized.includes('journey') ||
      normalized.includes('boarded') ||
      normalized.includes('dropoff') ||
      normalized.includes('arrived')) {
    return 'trips';
  }
  if (normalized.startsWith('payment_') ||
      normalized.includes('refund') ||
      normalized.includes('payout') ||
      normalized.includes('settlement')) {
    return 'payments';
  }
  if (normalized.startsWith('promo_') || normalized.startsWith('marketing_')) {
    return 'promotions';
  }
  return 'system';
}
