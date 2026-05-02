import type { ChannelAdapter, SendParams, SendResult } from './channel.adapter.js';
import { logger } from '../logger.js';

export class PushAdapter implements ChannelAdapter {
  async send(params: SendParams): Promise<SendResult> {
    // Stub — replaced by Firebase Admin in Task #83
    logger.info({ userId: params.userId, title: params.title }, '[push-stub] Would send push notification');
    return { success: true, providerMessageId: `stub-${Date.now()}` };
  }
}
