import type { ChannelAdapter, SendParams, SendResult } from './channel.adapter.js';

export class InAppAdapter implements ChannelAdapter {
  async send(_params: SendParams): Promise<SendResult> {
    // In-app notifications are persisted to the notifications table by NotificationService.
    // This adapter is a no-op — persistence happens before dispatch.
    return { success: true };
  }
}
