import { PaymentRepository } from '../repositories/payment.repository.js';
import { createPaymentProvider } from '../providers/provider.factory.js';
import type { PaymentProvider } from '../providers/payment.provider.js';
import type { PaymentRow } from '../repositories/payment.repository.js';
import { config } from '../config.js';
import { logger } from '../logger.js';

export interface InitiateParams {
  bookingId: string;
  userId: string;
  amountTzs: number;
  method: string;
  payerPhone: string;
  idempotencyKey: string;
}

export interface InitiateResult {
  payment: PaymentRow;
  instructions: string;
  expiresInSeconds: number;
}

export class PaymentService {
  private readonly provider: PaymentProvider;
  private readonly repo: PaymentRepository;

  constructor(repo: PaymentRepository) {
    this.repo = repo;
    this.provider = createPaymentProvider(config.PAYMENT_PROVIDER);
  }

  async initiatePayment(params: InitiateParams): Promise<InitiateResult> {
    const expiresAt = new Date(Date.now() + 120_000);
    const payment = await this.repo.create({
      bookingId: params.bookingId,
      userId: params.userId,
      idempotencyKey: params.idempotencyKey,
      amountTzs: params.amountTzs,
      method: params.method,
      provider: this.provider.name,
      payerPhone: params.payerPhone,
      expiresAt,
    });

    try {
      const result = await this.provider.initiatePayment({
        bookingId: params.bookingId,
        userId: params.userId,
        amountTzs: params.amountTzs,
        method: params.method as never,
        payerPhone: params.payerPhone,
        idempotencyKey: params.idempotencyKey,
        internalReference: payment.internal_reference,
      });

      if (result.providerReference) {
        await this.repo.setProviderReference(payment.id, result.providerReference);
      }

      return { payment, instructions: result.instructions, expiresInSeconds: result.expiresInSeconds };
    } catch (err) {
      logger.error({ err, paymentId: payment.id }, 'Provider initiatePayment failed');
      await this.repo.markFailed(payment.id, 'PROVIDER_ERROR', String(err));
      throw err;
    }
  }

  async processCallback(provider: string, rawBody: string, signature: string): Promise<{ paymentId: string; newStatus: string }> {
    const payload = { provider, rawBody, signature };
    const verified = this.provider.verifyCallback(payload);

    let paymentId: string | null = null;
    let newStatus = 'unknown';

    try {
      const result = this.provider.parseCallback(payload);
      const payment = await this.repo.findByInternalRef(result.internalReference);
      if (!payment) {
        await this.repo.saveCallback(null, provider, rawBody, signature, verified);
        return { paymentId: '', newStatus: 'not_found' };
      }
      paymentId = payment.id;

      if (result.status === 'completed') {
        await this.repo.markCompleted(payment.id, result.providerReference);
        newStatus = 'completed';
      } else {
        await this.repo.markFailed(payment.id, result.failureCode ?? 'UNKNOWN', result.failureMessage ?? '');
        newStatus = 'failed';
      }
    } catch (err) {
      logger.error({ err }, 'processCallback parse error');
      newStatus = 'error';
    }

    await this.repo.saveCallback(paymentId, provider, rawBody, signature, verified);
    return { paymentId: paymentId ?? '', newStatus };
  }

  async getPayment(id: string): Promise<PaymentRow | null> {
    return this.repo.findById(id);
  }

  async getByBooking(bookingId: string): Promise<PaymentRow | null> {
    return this.repo.findByBookingId(bookingId);
  }
}
