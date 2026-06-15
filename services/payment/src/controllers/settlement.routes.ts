import type { FastifyInstance } from 'fastify';
import { PayoutRepository } from '../repositories/payout.repository.js';
import { PayoutService } from '../services/payout.service.js';
import { LedgerRepository } from '../repositories/ledger.repository.js';
import { LedgerPostingService } from '../services/ledger.service.js';
import { ReconciliationRepository } from '../repositories/reconciliation.repository.js';
import { pgPool } from '../db.js';
import { logger } from '../logger.js';

const payoutRepository = new PayoutRepository(pgPool);
const ledgerRepository = new LedgerRepository(pgPool);
const reconciliationRepository = new ReconciliationRepository(pgPool);
const payoutService = new PayoutService(
  payoutRepository,
  new LedgerPostingService(ledgerRepository),
);

export async function settlementRoutes(app: FastifyInstance): Promise<void> {
  // GET /api/v1/drivers/:driverId/earnings
  app.get('/api/v1/drivers/:driverId/earnings', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });
    const { driverId } = req.params as { driverId: string };
    if (userId !== driverId) return reply.status(403).send({ error: 'FORBIDDEN' });

    const balance = await payoutService.getDriverBalance(driverId);
    return reply.send({
      total_earnings_tzs: balance.total_earned_tzs,
      total_platform_fees_tzs: balance.total_platform_fees_tzs,
      total_settled_tzs: balance.paid_out_tzs,
      pending_balance_tzs: balance.available_tzs,
      pending_payout_tzs: balance.pending_payout_tzs,
      held_tzs: balance.held_tzs,
      trip_count: balance.trip_count,
    });
  });

  app.get('/api/v1/drivers/:driverId/payouts', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });
    const { driverId } = req.params as { driverId: string };
    if (userId !== driverId) return reply.status(403).send({ error: 'FORBIDDEN' });

    const query = req.query as { page?: string; page_size?: string };
    const result = await payoutService.listDriverPayouts(
      driverId,
      Number(query.page ?? 1),
      Number(query.page_size ?? 20),
    );
    return reply.send({
      items: result.items.map(toPayoutDto),
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

  app.get('/api/v1/drivers/:driverId/payouts/:payoutId', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });
    const { driverId, payoutId } = req.params as { driverId: string; payoutId: string };
    if (userId !== driverId) return reply.status(403).send({ error: 'FORBIDDEN' });

    try {
      const detail = await payoutService.getDriverPayoutDetail(driverId, payoutId);
      const [ledgerJournals, reconciliationRecords] = await Promise.all([
        ledgerRepository.listJournalsForSource('payout', payoutId),
        reconciliationRepository.listForPayout(detail.payout.provider_reference, payoutId),
      ]);
      return reply.send({
        payout: toPayoutDto(detail.payout),
        items: detail.items.map(toPayoutItemDto),
        holds: detail.holds.map(toPayoutHoldDto),
        ledgerJournals: ledgerJournals.map(toLedgerJournalDto),
        reconciliationRecords: reconciliationRecords.map(toReconciliationRecordDto),
      });
    } catch (err) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code === 'NOT_FOUND') return reply.status(404).send({ error: 'NOT_FOUND' });
      if (code === 'FORBIDDEN') return reply.status(403).send({ error: 'FORBIDDEN' });
      logger.error({ err }, 'GET /drivers/:driverId/payouts/:payoutId failed');
      return reply.status(500).send({ error: 'INTERNAL_ERROR' });
    }
  });

  // POST /api/v1/drivers/:driverId/settlements
  // Compatibility path: creates a server-derived payout request. Client-provided
  // booking IDs or earning amounts are intentionally ignored.
  app.post('/api/v1/drivers/:driverId/settlements', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });
    const { driverId } = req.params as { driverId: string };
    if (userId !== driverId) return reply.status(403).send({ error: 'FORBIDDEN' });

    const body = req.body as {
      payoutMethod: string;
      payoutPhone: string;
    };

    try {
      const payout = await payoutService.requestPayout({
        driverUserId: driverId,
        payoutMethod: body.payoutMethod,
        payoutPhone: body.payoutPhone,
        requestedBy: userId,
      });
      return reply.status(201).send({
        payoutId: payout.id,
        driverUserId: payout.driver_user_id,
        amountTzs: Number(payout.amount_tzs),
        status: payout.status,
        payoutMethod: payout.payout_method,
        requestedAt: payout.requested_at,
      });
    } catch (err) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code === 'NO_PAYABLE_BALANCE') return reply.status(422).send({ error: 'NO_PAYABLE_BALANCE' });
      if (code === 'VALIDATION_ERROR') return reply.status(400).send({ error: 'VALIDATION_ERROR' });
      if (code === 'FORBIDDEN') return reply.status(403).send({ error: 'FORBIDDEN' });
      logger.error({ err }, 'POST /drivers/:driverId/settlements failed');
      return reply.status(500).send({ error: 'INTERNAL_ERROR' });
    }
  });

  app.get('/api/v1/payouts', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    const userRole = req.headers['x-user-role'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });
    if (userRole !== 'admin') return reply.status(403).send({ error: 'FORBIDDEN' });

    const query = req.query as { status?: string; page?: string; page_size?: string };
    const result = await payoutService.listPayouts({
      status: query.status,
      page: Number(query.page ?? 1),
      pageSize: Number(query.page_size ?? 50),
    });
    return reply.send({
      items: result.items.map(toPayoutDto),
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

  app.post('/api/v1/payouts/:id/approve', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    const userRole = req.headers['x-user-role'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });
    if (userRole !== 'admin') return reply.status(403).send({ error: 'FORBIDDEN' });

    try {
      const { id } = req.params as { id: string };
      const payout = await payoutService.approvePayout(id, userId);
      return reply.send(toPayoutDto(payout));
    } catch (err) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code === 'INVALID_PAYOUT_STATE') return reply.status(422).send({ error: 'INVALID_PAYOUT_STATE' });
      logger.error({ err }, 'POST /payouts/:id/approve failed');
      return reply.status(500).send({ error: 'INTERNAL_ERROR' });
    }
  });

  app.post('/api/v1/payouts/:id/complete', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    const userRole = req.headers['x-user-role'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });
    if (userRole !== 'admin') return reply.status(403).send({ error: 'FORBIDDEN' });

    const body = req.body as { providerReference?: string };
    try {
      const { id } = req.params as { id: string };
      const payout = await payoutService.completePayout(id, body.providerReference ?? '');
      return reply.send(toPayoutDto(payout));
    } catch (err) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code === 'VALIDATION_ERROR') return reply.status(400).send({ error: 'VALIDATION_ERROR' });
      if (code === 'INVALID_PAYOUT_STATE') return reply.status(422).send({ error: 'INVALID_PAYOUT_STATE' });
      logger.error({ err }, 'POST /payouts/:id/complete failed');
      return reply.status(500).send({ error: 'INTERNAL_ERROR' });
    }
  });

  app.post('/api/v1/payouts/:id/fail', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    const userRole = req.headers['x-user-role'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });
    if (userRole !== 'admin') return reply.status(403).send({ error: 'FORBIDDEN' });

    const body = req.body as { failureReason?: string };
    try {
      const { id } = req.params as { id: string };
      const payout = await payoutService.failPayout(id, body.failureReason ?? 'Manual failure');
      return reply.send(toPayoutDto(payout));
    } catch (err) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code === 'INVALID_PAYOUT_STATE') return reply.status(422).send({ error: 'INVALID_PAYOUT_STATE' });
      logger.error({ err }, 'POST /payouts/:id/fail failed');
      return reply.status(500).send({ error: 'INTERNAL_ERROR' });
    }
  });

  app.post('/api/v1/payout-holds', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    const userRole = req.headers['x-user-role'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });
    if (userRole !== 'admin') return reply.status(403).send({ error: 'FORBIDDEN' });

    const body = req.body as {
      driverUserId?: string;
      ledgerEntryId?: string;
      bookingId?: string;
      reason?: 'safety_report' | 'dispute' | 'no_show' | 'chargeback' | 'admin_review';
      note?: string | null;
    };

    try {
      const hold = await payoutService.createHold({
        driverUserId: body.driverUserId ?? '',
        ledgerEntryId: body.ledgerEntryId,
        bookingId: body.bookingId,
        reason: body.reason ?? 'admin_review',
        note: body.note,
        createdBy: userId,
      });
      return reply.status(201).send(toPayoutHoldDto(hold));
    } catch (err) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code === 'VALIDATION_ERROR') return reply.status(400).send({ error: 'VALIDATION_ERROR' });
      if (code === 'NO_HOLDABLE_PAYABLE') return reply.status(422).send({ error: 'NO_HOLDABLE_PAYABLE' });
      logger.error({ err }, 'POST /payout-holds failed');
      return reply.status(500).send({ error: 'INTERNAL_ERROR' });
    }
  });

  app.post('/api/v1/payout-holds/:id/release', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    const userRole = req.headers['x-user-role'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });
    if (userRole !== 'admin') return reply.status(403).send({ error: 'FORBIDDEN' });

    try {
      const { id } = req.params as { id: string };
      const hold = await payoutService.releaseHold(id, userId);
      return reply.send(toPayoutHoldDto(hold));
    } catch (err) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code === 'VALIDATION_ERROR') return reply.status(400).send({ error: 'VALIDATION_ERROR' });
      if (code === 'INVALID_PAYOUT_HOLD_STATE') {
        return reply.status(422).send({ error: 'INVALID_PAYOUT_HOLD_STATE' });
      }
      logger.error({ err }, 'POST /payout-holds/:id/release failed');
      return reply.status(500).send({ error: 'INTERNAL_ERROR' });
    }
  });
}

function toPayoutDto(payout: {
  id: string;
  driver_user_id: string;
  amount_tzs: string;
  status: string;
  payout_method: string;
  payout_phone: string;
  provider_reference: string | null;
  requested_at: Date;
  completed_at: Date | null;
}) {
  return {
    payoutId: payout.id,
    driverUserId: payout.driver_user_id,
    amountTzs: Number(payout.amount_tzs),
    status: payout.status,
    payoutMethod: payout.payout_method,
    payoutPhone: payout.payout_phone,
    providerReference: payout.provider_reference,
    requestedAt: payout.requested_at,
    completedAt: payout.completed_at,
  };
}

function toPayoutItemDto(item: {
  id: string;
  payout_id: string;
  ledger_entry_id: string;
  booking_id: string | null;
  amount_tzs: string;
  released_at: Date | null;
  created_at: Date;
}) {
  return {
    itemId: item.id,
    payoutId: item.payout_id,
    ledgerEntryId: item.ledger_entry_id,
    bookingId: item.booking_id,
    amountTzs: Number(item.amount_tzs),
    releasedAt: item.released_at,
    createdAt: item.created_at,
  };
}

function toPayoutHoldDto(hold: {
  id: string;
  driver_user_id: string;
  ledger_entry_id: string;
  booking_id: string | null;
  amount_tzs: string;
  reason: string;
  note: string | null;
  created_by: string;
  released_by: string | null;
  released_at: Date | null;
  created_at: Date;
}) {
  return {
    holdId: hold.id,
    driverUserId: hold.driver_user_id,
    ledgerEntryId: hold.ledger_entry_id,
    bookingId: hold.booking_id,
    amountTzs: Number(hold.amount_tzs),
    reason: hold.reason,
    note: hold.note,
    createdBy: hold.created_by,
    releasedBy: hold.released_by,
    releasedAt: hold.released_at,
    createdAt: hold.created_at,
  };
}

function toLedgerJournalDto(journal: {
  id: string;
  journal_type: string;
  status: string;
  source_type: string;
  source_id: string;
  booking_id: string | null;
  payment_id: string | null;
  settlement_id: string | null;
  currency: string;
  metadata: Record<string, unknown>;
  idempotency_key: string;
  created_by: string | null;
  correlation_id: string | null;
  created_at: Date;
  entries: Array<{
    id: string;
    journal_id: string;
    account_id: string;
    direction: string;
    amount_tzs: string;
    currency: string;
    booking_id: string | null;
    payment_id: string | null;
    settlement_id: string | null;
    source_type: string | null;
    source_id: string | null;
    created_at: Date;
  }>;
}) {
  return {
    journalId: journal.id,
    journalType: journal.journal_type,
    status: journal.status,
    sourceType: journal.source_type,
    sourceId: journal.source_id,
    bookingId: journal.booking_id,
    paymentId: journal.payment_id,
    settlementId: journal.settlement_id,
    currency: journal.currency,
    metadata: journal.metadata,
    idempotencyKey: journal.idempotency_key,
    createdBy: journal.created_by,
    correlationId: journal.correlation_id,
    createdAt: journal.created_at,
    entries: journal.entries.map((entry) => ({
      entryId: entry.id,
      journalId: entry.journal_id,
      accountId: entry.account_id,
      direction: entry.direction,
      amountTzs: Number(entry.amount_tzs),
      currency: entry.currency,
      bookingId: entry.booking_id,
      paymentId: entry.payment_id,
      settlementId: entry.settlement_id,
      sourceType: entry.source_type,
      sourceId: entry.source_id,
      createdAt: entry.created_at,
    })),
  };
}

function toReconciliationRecordDto(record: {
  id: string;
  provider: string;
  record_type: string;
  provider_reference: string;
  amount_tzs: string;
  provider_status: string;
  occurred_at: Date | null;
  match_status: string;
  mismatch_reason: string | null;
  imported_at: Date;
}) {
  return {
    recordId: record.id,
    provider: record.provider,
    recordType: record.record_type,
    providerReference: record.provider_reference,
    amountTzs: Number(record.amount_tzs),
    providerStatus: record.provider_status,
    occurredAt: record.occurred_at,
    matchStatus: record.match_status,
    mismatchReason: record.mismatch_reason,
    importedAt: record.imported_at,
  };
}
