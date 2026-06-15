import type { FastifyInstance } from 'fastify';
import { PaymentService } from '../services/payment.service.js';
import { PaymentRepository } from '../repositories/payment.repository.js';
import type { PaymentRow } from '../repositories/payment.repository.js';
import { LedgerRepository } from '../repositories/ledger.repository.js';
import { LedgerPostingService } from '../services/ledger.service.js';
import { pgPool } from '../db.js';
import { logger } from '../logger.js';
import type { RefundRow } from '../repositories/payment.repository.js';

const ledgerRepository = new LedgerRepository(pgPool);
const service = new PaymentService(
  new PaymentRepository(pgPool),
  new LedgerPostingService(ledgerRepository),
);

export async function paymentRoutes(app: FastifyInstance): Promise<void> {
  app.get('/api/v1/refunds', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string | undefined;
    const userRole = req.headers['x-user-role'] as string | undefined;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });
    if (userRole !== 'admin') return reply.status(403).send({ error: 'FORBIDDEN' });

    const query = req.query as { status?: string; page?: string; page_size?: string };
    const page = Number.parseInt(query.page ?? '1', 10);
    const pageSize = Number.parseInt(query.page_size ?? '50', 10);
    const result = await service.listRefunds({
      status: query.status,
      page: Number.isFinite(page) ? page : 1,
      pageSize: Number.isFinite(pageSize) ? pageSize : 50,
    });

    return reply.send({
      items: result.items.map(toRefundDto),
      pagination: {
        page: result.page,
        page_size: result.pageSize,
        total_count: result.totalCount,
        total_pages: Math.ceil(result.totalCount / result.pageSize),
        has_next: result.page * result.pageSize < result.totalCount,
        has_previous: result.page > 1,
      },
    });
  });

  app.post('/api/v1/refunds/:id/complete', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string | undefined;
    const userRole = req.headers['x-user-role'] as string | undefined;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });
    if (userRole !== 'admin') return reply.status(403).send({ error: 'FORBIDDEN' });

    const { id } = req.params as { id: string };
    const body = req.body as { providerReference?: string };
    try {
      const result = await service.completeManualRefund({
        refundId: id,
        providerReference: body.providerReference ?? '',
      });
      return reply.send({
        payment: toPaymentDto(result.payment),
        refund: toRefundDto(result.refund),
      });
    } catch (err) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code === 'NOT_FOUND') return reply.status(404).send({ error: 'NOT_FOUND' });
      if (code === 'VALIDATION_ERROR') return reply.status(400).send({ error: 'VALIDATION_ERROR' });
      if (code === 'REFUND_AMOUNT_EXCEEDS_BALANCE') return reply.status(422).send({ error: 'REFUND_AMOUNT_EXCEEDS_BALANCE' });
      logger.error({ err }, 'POST /refunds/:id/complete failed');
      return reply.status(500).send({ error: 'INTERNAL_ERROR' });
    }
  });

  app.get('/api/v1/payments', async (req, reply) => {
    const userRole = req.headers['x-user-role'] as string;
    if (userRole !== 'admin') return reply.status(403).send({ error: 'FORBIDDEN' });

    const query = req.query as { status?: string; page?: string; page_size?: string };
    const page = Number.parseInt(query.page ?? '1', 10);
    const pageSize = Number.parseInt(query.page_size ?? '50', 10);
    const result = await service.listPayments({
      status: query.status,
      page: Number.isFinite(page) ? page : 1,
      pageSize: Number.isFinite(pageSize) ? pageSize : 50,
    });

    return reply.send({
      items: result.items.map(toPaymentDto),
      pagination: {
        page: result.page,
        page_size: result.pageSize,
        total_count: result.totalCount,
        total_pages: Math.ceil(result.totalCount / result.pageSize),
        has_next: result.page * result.pageSize < result.totalCount,
        has_previous: result.page > 1,
      },
    });
  });

  app.post('/api/v1/payments/initiate', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });

    const body = req.body as {
      bookingId: string;
      amountTzs: number;
      method: string;
      payerPhone: string;
      idempotencyKey: string;
    };

    try {
      const result = await service.initiatePayment({
        bookingId: body.bookingId,
        userId,
        amountTzs: body.amountTzs,
        method: body.method,
        payerPhone: body.payerPhone,
        idempotencyKey: body.idempotencyKey,
      });
      return reply.status(201).send({
        paymentId: result.payment.id,
        status: result.payment.status,
        instructions: result.instructions,
        expiresInSeconds: result.expiresInSeconds,
        internalReference: result.payment.internal_reference,
      });
    } catch (err) {
      logger.error({ err }, 'POST /payments/initiate failed');
      return reply.status(502).send({
        error: 'PAYMENT_INITIATION_FAILED',
        message: 'Payment provider is temporarily unavailable. Please try again.',
      });
    }
  });

  app.get('/api/v1/payments/:id', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string | undefined;
    const userRole = req.headers['x-user-role'] as string | undefined;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });

    const { id } = req.params as { id: string };
    const payment = await service.getPayment(id);
    if (!payment) return reply.status(404).send({ error: 'NOT_FOUND' });
    if (userRole !== 'admin' && payment.user_id !== userId) {
      return reply.status(403).send({ error: 'FORBIDDEN' });
    }

    const refunds = await service.listRefundsForPayment(id);
    return reply.send({
      ...toPaymentDto(payment),
      refunds: refunds.map(toRefundDto),
    });
  });

  app.get('/api/v1/payments/:id/refunds', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string | undefined;
    const userRole = req.headers['x-user-role'] as string | undefined;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });

    const { id } = req.params as { id: string };
    const payment = await service.getPayment(id);
    if (!payment) return reply.status(404).send({ error: 'NOT_FOUND' });
    if (userRole !== 'admin' && payment.user_id !== userId) {
      return reply.status(403).send({ error: 'FORBIDDEN' });
    }

    const refunds = await service.listRefundsForPayment(id);
    return reply.send({ refunds: refunds.map(toRefundDto) });
  });

  app.get('/api/v1/payments/:id/ledger', async (req, reply) => {
    const userRole = req.headers['x-user-role'] as string | undefined;
    if (userRole !== 'admin') return reply.status(403).send({ error: 'FORBIDDEN' });

    const { id } = req.params as { id: string };
    const payment = await service.getPayment(id);
    if (!payment) return reply.status(404).send({ error: 'NOT_FOUND' });
    const journals = await ledgerRepository.listJournalsForPayment(id);

    return reply.send({
      payment: toPaymentDto(payment),
      journals: journals.map((journal) => ({
        journal_id: journal.id,
        journal_type: journal.journal_type,
        status: journal.status,
        source_type: journal.source_type,
        source_id: journal.source_id,
        idempotency_key: journal.idempotency_key,
        currency: journal.currency,
        metadata: journal.metadata,
        created_at: journal.created_at,
        entries: journal.entries.map((entry) => ({
          entry_id: entry.id,
          account_id: entry.account_id,
          direction: entry.direction,
          amount_tzs: Number(entry.amount_tzs),
          currency: entry.currency,
          booking_id: entry.booking_id,
          payment_id: entry.payment_id,
          settlement_id: entry.settlement_id,
          source_type: entry.source_type,
          source_id: entry.source_id,
          created_at: entry.created_at,
        })),
      })),
    });
  });

  app.get('/api/v1/payments/:id/status', async (req, reply) => {
    const { id } = req.params as { id: string };
    const payment = await service.getPayment(id);
    if (!payment) return reply.status(404).send({ error: 'NOT_FOUND' });
    return reply.send({
      paymentId: payment.id,
      status: payment.status,
      providerReference: payment.provider_reference,
      amountTzs: payment.amount_tzs,
      refundedAmountTzs: payment.refunded_amount_tzs,
    });
  });

  // POST /api/v1/payments/:id/refund
  app.post('/api/v1/payments/:id/refund', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    const userRole = req.headers['x-user-role'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });

    const { id } = req.params as { id: string };
    const body = req.body as {
      reason: string;
      departureTime?: string;
      cancelledAt?: string;
      forceFullRefund?: boolean;
    };

    const forceFullRefund = userRole === 'admin' ? (body.forceFullRefund ?? true) : false;

    try {
      const result = await service.refund({
        paymentId: id,
        reason: body.reason ?? 'PASSENGER_CANCELLED',
        initiatedBy: userId,
        departuretime: body.departureTime ? new Date(body.departureTime) : undefined,
        cancelledAt: body.cancelledAt ? new Date(body.cancelledAt) : new Date(),
        forceFullRefund,
      });
      return reply.send({
        paymentId: result.payment.id,
        refundedAmountTzs: result.refundedAmount,
        policy: result.policy,
        refundReference: result.refundReference,
        refundStatus: result.refundStatus,
        status: result.payment.status,
      });
    } catch (err) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code === 'NOT_FOUND') return reply.status(404).send({ error: 'NOT_FOUND' });
      if (code === 'NOT_REFUNDABLE') return reply.status(422).send({ error: 'NOT_REFUNDABLE' });
      if (code === 'ALREADY_REFUNDED') return reply.status(422).send({ error: 'ALREADY_REFUNDED' });
      if (code === 'REFUND_PROVIDER_FAILED') return reply.status(502).send({ error: 'REFUND_PROVIDER_FAILED' });
      logger.error({ err }, 'POST /payments/:id/refund failed');
      return reply.status(500).send({ error: 'INTERNAL_ERROR' });
    }
  });

  // Webhook — no auth, signature verified in service
  app.post('/api/v1/webhooks/azampay', async (req, reply) => {
    const rawBody = JSON.stringify(req.body);
    const signature = (req.headers['x-azampay-signature'] as string) ?? '';
    try {
      const result = await service.processCallback('azampay', rawBody, signature);
      return reply.send({ processed: true, paymentId: result.paymentId, status: result.newStatus });
    } catch (err) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code === 'INVALID_SIGNATURE') return reply.status(401).send({ processed: false, error: 'INVALID_SIGNATURE' });
      if (code === 'INVALID_CALLBACK_PAYLOAD') return reply.status(400).send({ processed: false, error: 'INVALID_CALLBACK_PAYLOAD' });
      logger.error({ err }, 'Azampay callback processing failed');
      return reply.status(500).send({ processed: false });
    }
  });
}

function toPaymentDto(payment: PaymentRow) {
  return {
    payment_id: payment.id,
    booking_id: payment.booking_id,
    user_id: payment.user_id,
    amount: payment.amount_tzs,
    amount_tzs: payment.amount_tzs,
    method: payment.method,
    status: payment.status,
    provider: payment.provider,
    provider_reference: payment.provider_reference,
    internal_reference: payment.internal_reference,
    payer_phone: payment.payer_phone,
    failure_code: payment.failure_code,
    failure_message: payment.failure_message,
    refunded_amount: payment.refunded_amount_tzs,
    refunded_amount_tzs: payment.refunded_amount_tzs,
    initiated_at: payment.initiated_at,
    completed_at: payment.completed_at,
    failed_at: payment.failed_at,
    last_refund_at: payment.last_refund_at,
  };
}

function toRefundDto(refund: RefundRow) {
  return {
    refund_id: refund.id,
    payment_id: refund.payment_id,
    booking_id: refund.booking_id,
    user_id: refund.user_id,
    amount_tzs: refund.amount_tzs,
    status: refund.status,
    reason: refund.reason,
    policy: refund.policy,
    provider_reference: refund.provider_reference,
    failure_reason: refund.failure_reason,
    requested_by: refund.requested_by,
    requested_at: refund.requested_at,
    completed_at: refund.completed_at,
    failed_at: refund.failed_at,
  };
}
