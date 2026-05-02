export type PaymentMethod = 'mpesa_tz' | 'tigopesa' | 'airtel_money' | 'halopesa' | 'mock';

export interface InitiatePaymentParams {
  bookingId: string;
  userId: string;
  amountTzs: number;
  method: PaymentMethod;
  payerPhone: string;
  idempotencyKey: string;
  internalReference: string;
}

export interface InitiatePaymentResult {
  providerReference: string | null;
  instructions: string;
  expiresInSeconds: number;
  checkoutUrl?: string;
}

export interface CallbackPayload {
  provider: string;
  rawBody: string;
  signature: string;
}

export interface CallbackResult {
  internalReference: string;
  providerReference: string;
  status: 'completed' | 'failed';
  failureCode?: string;
  failureMessage?: string;
}

export interface RefundParams {
  providerReference: string;
  amountTzs: number;
  reason: string;
  payeePhone: string;
}

export interface RefundResult {
  refundReference: string;
}

export interface PaymentProvider {
  readonly name: string;

  initiatePayment(params: InitiatePaymentParams): Promise<InitiatePaymentResult>;

  verifyCallback(payload: CallbackPayload): boolean;

  parseCallback(payload: CallbackPayload): CallbackResult;

  refund(params: RefundParams): Promise<RefundResult>;
}
