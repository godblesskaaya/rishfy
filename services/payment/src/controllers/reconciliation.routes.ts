import type { FastifyInstance } from 'fastify';
import { ReconciliationRepository, type ReconciliationStatus } from '../repositories/reconciliation.repository.js';
import { ReconciliationService } from '../services/reconciliation.service.js';
import { pgPool } from '../db.js';
import { logger } from '../logger.js';

const service = new ReconciliationService(new ReconciliationRepository(pgPool));

export async function reconciliationRoutes(app: FastifyInstance): Promise<void> {
  app.post('/api/v1/reconciliation/provider-refunds', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    const userRole = req.headers['x-user-role'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });
    if (userRole !== 'admin') return reply.status(403).send({ error: 'FORBIDDEN' });

    try {
      const result = await service.importRefundRecords(readRecords(req.body), userId);
      return reply.status(201).send({
        summary: result.summary,
        items: result.imported.map(toDto),
      });
    } catch (err) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code === 'VALIDATION_ERROR' || code === 'INVALID_MONEY_AMOUNT') {
        return reply.status(400).send({ error: code });
      }
      logger.error({ err }, 'POST /reconciliation/provider-refunds failed');
      return reply.status(500).send({ error: 'INTERNAL_ERROR' });
    }
  });

  app.post('/api/v1/reconciliation/provider-payouts', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    const userRole = req.headers['x-user-role'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });
    if (userRole !== 'admin') return reply.status(403).send({ error: 'FORBIDDEN' });

    try {
      const result = await service.importPayoutRecords(readRecords(req.body), userId);
      return reply.status(201).send({
        summary: result.summary,
        items: result.imported.map(toDto),
      });
    } catch (err) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code === 'VALIDATION_ERROR' || code === 'INVALID_MONEY_AMOUNT') {
        return reply.status(400).send({ error: code });
      }
      logger.error({ err }, 'POST /reconciliation/provider-payouts failed');
      return reply.status(500).send({ error: 'INTERNAL_ERROR' });
    }
  });

  app.post('/api/v1/reconciliation/provider-payments', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    const userRole = req.headers['x-user-role'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });
    if (userRole !== 'admin') return reply.status(403).send({ error: 'FORBIDDEN' });

    try {
      const result = await service.importPaymentRecords(
        readRecords(req.body),
        userId,
      );
      return reply.status(201).send({
        summary: result.summary,
        items: result.imported.map(toDto),
      });
    } catch (err) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code === 'VALIDATION_ERROR' || code === 'INVALID_MONEY_AMOUNT') {
        return reply.status(400).send({ error: code });
      }
      logger.error({ err }, 'POST /reconciliation/provider-payments failed');
      return reply.status(500).send({ error: 'INTERNAL_ERROR' });
    }
  });

  app.get('/api/v1/reconciliation/provider-payments', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    const userRole = req.headers['x-user-role'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });
    if (userRole !== 'admin') return reply.status(403).send({ error: 'FORBIDDEN' });

    const query = req.query as { status?: ReconciliationStatus; limit?: string; offset?: string };
    const limit = Number.parseInt(query.limit ?? '50', 10);
    const offset = Number.parseInt(query.offset ?? '0', 10);
    const rows = await service.list({
      status: query.status,
      limit: Number.isFinite(limit) ? Math.min(Math.max(limit, 1), 100) : 50,
      offset: Number.isFinite(offset) ? Math.max(offset, 0) : 0,
    });
    return reply.send({ items: rows.map(toDto) });
  });
}

function readRecords(body: unknown): Array<{
  provider: string;
  providerReference: string;
  amountTzs: number;
  providerStatus: string;
  occurredAt?: Date | null;
  rawPayload?: Record<string, unknown>;
}> {
  const payload = body as {
    records?: Array<{
      provider: string;
      providerReference: string;
      amountTzs: number;
      providerStatus: string;
      occurredAt?: string;
      rawPayload?: Record<string, unknown>;
    }>;
  };
  return (payload.records ?? []).map((record) => ({
    provider: record.provider,
    providerReference: record.providerReference,
    amountTzs: record.amountTzs,
    providerStatus: record.providerStatus,
    occurredAt: record.occurredAt ? new Date(record.occurredAt) : null,
    rawPayload: record.rawPayload,
  }));
}

function toDto(row: {
  id: string;
  provider: string;
  record_type: string;
  provider_reference: string;
  amount_tzs: string;
  provider_status: string;
  occurred_at: Date | null;
  match_status: string;
  matched_payment_id: string | null;
  mismatch_reason: string | null;
  imported_at: Date;
}) {
  return {
    id: row.id,
    provider: row.provider,
    recordType: row.record_type,
    providerReference: row.provider_reference,
    amountTzs: Number(row.amount_tzs),
    providerStatus: row.provider_status,
    occurredAt: row.occurred_at,
    matchStatus: row.match_status,
    matchedPaymentId: row.matched_payment_id,
    mismatchReason: row.mismatch_reason,
    importedAt: row.imported_at,
  };
}
