import type { ChannelAdapter, SendParams, SendResult } from './channel.adapter.js';
import { logger } from '../logger.js';

export class SmsAdapter implements ChannelAdapter {
  async send(params: SendParams): Promise<SendResult> {
    // Stub — production implementation uses Africa's Talking or Nexmo
    if (!params.phone) {
      return { status: 'skipped', error: 'No phone number available for SMS delivery', code: 'NO_PHONE' };
    }
    logger.info({ phone: params.phone, body: params.body }, '[sms-stub] Would send SMS');
    return { status: 'sent', providerMessageId: `sms-stub-${Date.now()}` };
  }
}
