import { PaymentRepository } from '../repositories/payment.repository.js';
import { createPaymentProvider } from '../providers/provider.factory.js';
import type { CallbackResult, PaymentProvider } from '../providers/payment.provider.js';
import type { PaymentRow, RefundRow } from '../repositories/payment.repository.js';
import type { LedgerPostingService } from './ledger.service.js';
import { config } from '../config.js';
import { logger } from '../logger.js';
import {
  buildPaymentInitiatedEvent,
  buildPaymentCompletedEvent,
  buildPaymentFailedEvent,
  buildPaymentRefundedEvent,
} from '../events/payment.events.js';

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

export interface BookingCompletedEvent {
  bookingId: string;
  passengerId: string;
  driverId: string;
  totalPrice: number;
  driverEarnings: number;
}

export interface PayableAccrualResult {
  posted: boolean;
  reason?: 'missing_payment' | 'payment_not_completed' | 'ledger_not_configured';
}

export interface ListPaymentsParams {
  status?: string;
  page: number;
  pageSize: number;
}

export interface ListPaymentsResult {
  items: PaymentRow[];
  page: number;
  pageSize: number;
  totalCount: number;
}

export interface ListRefundsParams {
  status?: string;
  page: number;
  pageSize: number;
}

export interface ListRefundsResult {
  items: RefundRow[];
  page: number;
  pageSize: number;
  totalCount: number;
}

export class PaymentService {
  private readonly provider: PaymentProvider;
  private readonly repo: PaymentRepository;
  private readonly ledger?: LedgerPostingService;

  constructor(repo: PaymentRepository, ledger?: LedgerPostingService) {
    this.repo = repo;
    this.ledger = ledger;
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

      await this.repo.enqueueOutboxEvent(buildPaymentInitiatedEvent({
        paymentId: payment.id,
        bookingId: payment.booking_id,
        userId: payment.user_id,
        amountTzs: payment.amount_tzs,
        provider: payment.provider,
        timestamp: new Date().toISOString(),
      }));

      return { payment, instructions: result.instructions, expiresInSeconds: result.expiresInSeconds };
    } catch (err) {
      logger.error({ err, paymentId: payment.id }, 'Provider initiatePayment failed');
      const failed = await this.repo.markFailed(payment.id, 'PROVIDER_ERROR', String(err));
      await this.repo.enqueueOutboxEvent(buildPaymentFailedEvent({
        paymentId: failed.id,
        bookingId: failed.booking_id,
        userId: failed.user_id,
        amountTzs: failed.amount_tzs,
        provider: failed.provider,
        failureCode: failed.failure_code ?? 'PROVIDER_ERROR',
        failureMessage: failed.failure_message ?? String(err),
        timestamp: new Date().toISOString(),
      }));
      throw err;
    }
  }

  async processCallback(provider: string, rawBody: string, signature: string): Promise<{ paymentId: string; newStatus: string }> {
    const payload = { provider, rawBody, signature };
    const verified = this.provider.verifyCallback(payload);
    if (!verified) {
      await this.repo.saveCallback(null, provider, rawBody, signature, false);
      throw Object.assign(new Error('Invalid callback signature'), { code: 'INVALID_SIGNATURE' });
    }

    let result: CallbackResult;
    try {
      result = this.provider.parseCallback(payload);
    } catch (err) {
      logger.error({ err }, 'processCallback parse error');
      await this.repo.saveCallback(null, provider, rawBody, signature, true);
      throw Object.assign(new Error('Invalid callback payload'), { code: 'INVALID_CALLBACK_PAYLOAD' });
    }
    const payment = await this.repo.findByInternalRef(result.internalReference);
    if (!payment) {
      await this.repo.saveCallback(null, provider, rawBody, signature, true);
      return { paymentId: '', newStatus: 'not_found' };
    }

    let newStatus = 'failed';
    if (result.status === 'completed') {
      const completed = await this.repo.markCompleted(payment.id, result.providerReference);
      newStatus = 'completed';
      await this.ledger?.recordPaymentCapturedForPayment({
        paymentId: completed.id,
        bookingId: completed.booking_id,
        userId: completed.user_id,
        provider: completed.provider,
        amountTzs: completed.amount_tzs,
        idempotencyKey: `payment:${completed.id}:captured`,
        metadata: {
          providerReference: result.providerReference,
          internalReference: completed.internal_reference,
        },
      });
      await this.repo.enqueueOutboxEvent(buildPaymentCompletedEvent({
        paymentId: completed.id,
        bookingId: completed.booking_id,
        userId: completed.user_id,
        amountTzs: completed.amount_tzs,
        provider: completed.provider,
        providerReference: result.providerReference,
        timestamp: new Date().toISOString(),
      }));
    } else {
      const failed = await this.repo.markFailed(payment.id, result.failureCode ?? 'UNKNOWN', result.failureMessage ?? '');
      await this.repo.enqueueOutboxEvent(buildPaymentFailedEvent({
        paymentId: failed.id,
        bookingId: failed.booking_id,
        userId: failed.user_id,
        amountTzs: failed.amount_tzs,
        provider: failed.provider,
        failureCode: result.failureCode ?? 'UNKNOWN',
        failureMessage: result.failureMessage ?? '',
        timestamp: new Date().toISOString(),
      }));
    }

    await this.repo.saveCallback(payment.id, provider, rawBody, signature, true);
    return { paymentId: payment.id, newStatus };
  }

  async getPayment(id: string): Promise<PaymentRow | null> {
    return this.repo.findById(id);
  }

  async listRefundsForPayment(paymentId: string): Promise<RefundRow[]> {
    return this.repo.listRefundsForPayment(paymentId);
  }

  async listRefunds(params: ListRefundsParams): Promise<ListRefundsResult> {
    const page = Math.max(1, params.page);
    const pageSize = Math.min(Math.max(1, params.pageSize), 100);
    const result = await this.repo.listRefunds({
      status: params.status,
      limit: pageSize,
      offset: (page - 1) * pageSize,
    });
    return {
      items: result.items,
      page,
      pageSize,
      totalCount: result.totalCount,
    };
  }

  async completeManualRefund(params: {
    refundId: string;
    providerReference: string;
  }): Promise<{ payment: PaymentRow; refund: RefundRow }> {
    if (!params.providerReference.trim()) {
      throw Object.assign(new Error('Provider reference is required'), { code: 'VALIDATION_ERROR' });
    }

    const refund = await this.repo.findRefundById(params.refundId);
    if (!refund) throw Object.assign(new Error('Refund not found'), { code: 'NOT_FOUND' });

    const payment = await this.repo.findById(refund.payment_id);
    if (!payment) throw Object.assign(new Error('Payment not found'), { code: 'NOT_FOUND' });

    let updatedPayment = payment;
    let completedRefund = refund;
    if (refund.status !== 'completed') {
      const eligibleAmount = payment.amount_tzs - payment.refunded_amount_tzs;
      if (eligibleAmount < refund.amount_tzs) {
        throw Object.assign(new Error('Refund exceeds available payment balance'), { code: 'REFUND_AMOUNT_EXCEEDS_BALANCE' });
      }
      updatedPayment = await this.repo.markRefunded(
        payment.id,
        refund.amount_tzs,
        refund.amount_tzs < eligibleAmount,
      );
      completedRefund = await this.repo.markRefundCompleted(refund.id, params.providerReference);
    }

    await this.ledger?.recordRefundCompletedForPayment({
      refundId: completedRefund.id,
      paymentId: updatedPayment.id,
      bookingId: updatedPayment.booking_id,
      passengerUserId: updatedPayment.user_id,
      provider: updatedPayment.provider,
      amountTzs: completedRefund.amount_tzs,
      providerReference: completedRefund.provider_reference ?? params.providerReference,
      idempotencyKey: `refund:${completedRefund.id}:completed`,
      metadata: {
        reason: completedRefund.reason,
        policy: completedRefund.policy,
        manualCompletion: true,
      },
    });

    await this.repo.enqueueOutboxEvent(buildPaymentRefundedEvent({
      paymentId: updatedPayment.id,
      bookingId: updatedPayment.booking_id,
      userId: updatedPayment.user_id,
      amountTzs: updatedPayment.amount_tzs,
      provider: updatedPayment.provider,
      refundedAmountTzs: completedRefund.amount_tzs,
      reason: completedRefund.reason,
      timestamp: new Date().toISOString(),
    }));

    return { payment: updatedPayment, refund: completedRefund };
  }

  async getByBooking(bookingId: string): Promise<PaymentRow | null> {
    return this.repo.findByBookingId(bookingId);
  }

  async listPayments(params: ListPaymentsParams): Promise<ListPaymentsResult> {
    const page = Math.max(1, params.page);
    const pageSize = Math.min(Math.max(1, params.pageSize), 100);
    const result = await this.repo.list({
      status: params.status,
      limit: pageSize,
      offset: (page - 1) * pageSize,
    });
    return {
      items: result.items,
      page,
      pageSize,
      totalCount: result.totalCount,
    };
  }

  async handleBookingCompleted(event: BookingCompletedEvent): Promise<PayableAccrualResult> {
    if (!this.ledger) return { posted: false, reason: 'ledger_not_configured' };

    const payment = await this.repo.findByBookingId(event.bookingId);
    if (!payment) return { posted: false, reason: 'missing_payment' };
    if (payment.status !== 'completed') return { posted: false, reason: 'payment_not_completed' };

    const totalAmountTzs = this.assertTzsInteger(event.totalPrice, 'totalPrice');
    const driverEarningsTzs = this.assertTzsInteger(event.driverEarnings, 'driverEarnings');
    const platformFeeTzs = totalAmountTzs - driverEarningsTzs;
    if (platformFeeTzs <= 0) {
      throw Object.assign(new Error('Invalid platform fee amount'), { code: 'INVALID_PLATFORM_FEE' });
    }
    if (payment.amount_tzs !== totalAmountTzs) {
      throw Object.assign(new Error('Booking total does not match completed payment amount'), { code: 'PAYMENT_AMOUNT_MISMATCH' });
    }

    await this.ledger.accrueDriverPayableForBooking({
      paymentId: payment.id,
      bookingId: event.bookingId,
      passengerUserId: event.passengerId,
      driverUserId: event.driverId,
      totalAmountTzs,
      platformFeeTzs,
      driverEarningsTzs,
      idempotencyKey: `booking:${event.bookingId}:driver-payable`,
      metadata: {
        paymentInternalReference: payment.internal_reference,
      },
    });

    return { posted: true };
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
  }): Promise<{
    payment: PaymentRow;
    refundedAmount: number;
    policy: string;
    refundReference: string;
    refundStatus: RefundRow['status'];
  }> {
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
      return {
        payment: updated,
        refundedAmount: 0,
        policy,
        refundReference: '',
        refundStatus: 'completed',
      };
    }

    const partial = refundAmount < eligibleAmount;
    const refund = await this.repo.createRefund({
      paymentId: payment.id,
      bookingId: payment.booking_id,
      userId: payment.user_id,
      amountTzs: refundAmount,
      reason: params.reason,
      policy,
      requestedBy: params.initiatedBy,
    });
    let providerRef: string;

    try {
      const result = await this.provider.refund({
        providerReference: payment.provider_reference ?? payment.internal_reference,
        amountTzs: refundAmount,
        reason: params.reason,
        payeePhone: payment.payer_phone,
      });
      providerRef = result.refundReference;
    } catch (err) {
      const manualRefund = await this.repo.markRefundManualRequired(refund.id, String(err));
      logger.warn({ err, paymentId: payment.id, refundId: refund.id }, 'Provider refund call failed; manual refund required');
      return {
        payment,
        refundedAmount: 0,
        policy,
        refundReference: manualRefund.id,
        refundStatus: manualRefund.status,
      };
    }

    const updated = await this.repo.markRefunded(payment.id, refundAmount, partial);
    await this.repo.markRefundCompleted(refund.id, providerRef);
    await this.ledger?.recordRefundCompletedForPayment({
      refundId: refund.id,
      paymentId: payment.id,
      bookingId: payment.booking_id,
      passengerUserId: payment.user_id,
      provider: payment.provider,
      amountTzs: refundAmount,
      providerReference: providerRef,
      idempotencyKey: `refund:${refund.id}:completed`,
      metadata: {
        reason: params.reason,
        policy,
      },
    });

    await this.repo.enqueueOutboxEvent(buildPaymentRefundedEvent({
      paymentId: updated.id,
      bookingId: updated.booking_id,
      userId: updated.user_id,
      amountTzs: updated.amount_tzs,
      provider: updated.provider,
      refundedAmountTzs: refundAmount,
      reason: params.reason,
      timestamp: new Date().toISOString(),
    }));

    logger.info({ paymentId: payment.id, refundAmount, policy, initiatedBy: params.initiatedBy }, 'Refund applied');
    return {
      payment: updated,
      refundedAmount: refundAmount,
      policy,
      refundReference: providerRef,
      refundStatus: 'completed',
    };
  }

  private assertTzsInteger(value: number, fieldName: string): number {
    if (!Number.isSafeInteger(value) || value <= 0) {
      throw Object.assign(new Error(`${fieldName} must be a positive integer TZS amount`), { code: 'INVALID_MONEY_AMOUNT' });
    }
    return value;
  }
}
