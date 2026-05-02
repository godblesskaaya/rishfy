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

  /**
   * Refund policy:
   *   - Cancelled >= 2 hours before booking departure  → full refund
   *   - Cancelled < 2 hours before departure           → 50% refund
   *   - Driver-cancelled or platform error             → full refund (forced)
   *
   * `forceFullRefund` bypasses the policy (admin-initiated or driver-cancel).
   */
  async refund(params: {
    paymentId: string;
    reason: string;
    initiatedBy: string;
    departuretime?: Date;
    cancelledAt?: Date;
    forceFullRefund?: boolean;
  }): Promise<{ payment: PaymentRow; refundedAmount: number; policy: string }> {
    const payment = await this.repo.findById(params.paymentId);
    if (!payment) throw Object.assign(new Error('Payment not found'), { code: 'NOT_FOUND' });
    if (!['completed', 'processing'].includes(payment.status)) {
      throw Object.assign(new Error('Payment is not refundable'), { code: 'NOT_REFUNDABLE' });
    }

    const eligibleAmount = payment.amount_tzs - payment.refunded_amount_tzs;
    if (eligibleAmount <= 0) {
      throw Object.assign(new Error('Payment already fully refunded'), { code: 'ALREADY_REFUNDED' });
    }

    let refundAmount = eligibleAmount;
    let policy = 'FULL_REFUND';

    if (!params.forceFullRefund && params.departuretime && params.cancelledAt) {
      const msUntilDeparture = params.departuretime.getTime() - params.cancelledAt.getTime();
      const twoHoursMs = 2 * 60 * 60 * 1000;
      if (msUntilDeparture < twoHoursMs) {
        refundAmount = Math.round(eligibleAmount * 0.5);
        policy = 'PENALTY_50';
      }
    }

    if (refundAmount === 0) {
      policy = 'NO_REFUND';
      const updated = await this.repo.markRefunded(payment.id, 0, false);
      return { payment: updated, refundedAmount: 0, policy };
    }

    const partial = refundAmount < eligibleAmount;
    let providerRef: string | undefined;

    try {
      const result = await this.provider.refund({
        providerReference: payment.provider_reference ?? payment.internal_reference,
        amountTzs: refundAmount,
        reason: params.reason,
        payeePhone: payment.payer_phone,
      });
      providerRef = result.refundReference;
    } catch (err) {
      logger.warn({ err, paymentId: payment.id }, 'Provider refund call failed, marking refunded locally');
    }

    const updated = await this.repo.markRefunded(payment.id, refundAmount, partial);
    if (providerRef) {
      await this.repo.setProviderReference(payment.id, providerRef);
    }

    logger.info({ paymentId: payment.id, refundAmount, policy, initiatedBy: params.initiatedBy }, 'Refund applied');
    return { payment: updated, refundedAmount: refundAmount, policy };
  }
}
