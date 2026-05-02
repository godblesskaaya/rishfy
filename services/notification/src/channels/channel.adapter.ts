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
  success: boolean;
  error?: string;
}

export interface ChannelAdapter {
  send(params: SendParams): Promise<SendResult>;
}
