export interface SendParams {
  userId: string;
  title?: string;
  body: string;
  data?: Record<string, unknown>;
  fcmToken?: string;
  phone?: string;
}

export interface SendResult {
  providerMessageId?: string;
  status: 'sent' | 'failed' | 'skipped';
  error?: string;
  code?: string;
}

export interface ChannelAdapter {
  send(params: SendParams): Promise<SendResult>;
}
