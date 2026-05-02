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
    await Promise.all(
      params.channels.map(async (channel) => {
        const tmpl = await this.repo.getTemplate(params.templateKey, lang, channel);
        if (!tmpl) {
          logger.warn({ key: params.templateKey, lang, channel }, 'Template not found');
          return;
        }
        const body = renderTemplate(tmpl.body_template, params.vars);
        const title = tmpl.subject ? renderTemplate(tmpl.subject, params.vars) : undefined;

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
          if (result.success) {
            await this.repo.markDelivered(notif.id, result.providerMessageId);
          } else {
            await this.repo.markFailed(notif.id, result.error ?? 'UNKNOWN');
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
    await queue.add('send', params, { priority });
  }
}
