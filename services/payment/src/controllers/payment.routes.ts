import type { FastifyInstance } from 'fastify';
import { PaymentService } from '../services/payment.service.js';
import { PaymentRepository } from '../repositories/payment.repository.js';
import { pgPool } from '../db.js';
import { logger } from '../logger.js';

const service = new PaymentService(new PaymentRepository(pgPool));

export async function paymentRoutes(app: FastifyInstance): Promise<void> {
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
      return reply.status(502).send({ error: 'PAYMENT_INITIATION_FAILED', message: String(err) });
    }
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
        status: result.payment.status,
      });
    } catch (err) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code === 'NOT_FOUND') return reply.status(404).send({ error: 'NOT_FOUND' });
      if (code === 'NOT_REFUNDABLE') return reply.status(422).send({ error: 'NOT_REFUNDABLE' });
      if (code === 'ALREADY_REFUNDED') return reply.status(422).send({ error: 'ALREADY_REFUNDED' });
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
      logger.error({ err }, 'Azampay callback processing failed');
      return reply.status(500).send({ processed: false });
    }
  });
}
