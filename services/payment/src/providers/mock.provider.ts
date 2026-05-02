import type {
  PaymentProvider,
  InitiatePaymentParams,
  InitiatePaymentResult,
  CallbackPayload,
  CallbackResult,
  RefundParams,
  RefundResult,
} from './payment.provider.js';
import { randomUUID } from 'crypto';

export class MockProvider implements PaymentProvider {
  readonly name = 'mock';

  async initiatePayment(params: InitiatePaymentParams): Promise<InitiatePaymentResult> {
    return {
      providerReference: `MOCK-${randomUUID()}`,
      instructions: `[MOCK] Approve payment of TZS ${params.amountTzs} for booking ${params.bookingId}`,
      expiresInSeconds: 120,
    };
  }

  verifyCallback(_payload: CallbackPayload): boolean {
    return true;
  }

  parseCallback(payload: CallbackPayload): CallbackResult {
    const data = JSON.parse(payload.rawBody) as {
      internalReference: string;
      providerReference?: string;
      success?: boolean;
    };
    return {
      internalReference: data.internalReference,
      providerReference: data.providerReference ?? `MOCK-${randomUUID()}`,
      status: data.success !== false ? 'completed' : 'failed',
    };
  }

  async refund(params: RefundParams): Promise<RefundResult> {
    return { refundReference: `MOCK-REFUND-${params.providerReference}` };
  }
}
