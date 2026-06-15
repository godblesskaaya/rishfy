import type { Pool } from 'pg';

export type LedgerOwnerType = 'platform' | 'driver' | 'passenger' | 'provider';
export type LedgerAccountType =
  | 'cash'
  | 'provider_clearing'
  | 'passenger_funds'
  | 'driver_payable'
  | 'platform_revenue'
  | 'refund_liability'
  | 'payout_clearing'
  | 'dispute_hold';
export type LedgerJournalType =
  | 'payment_captured'
  | 'driver_payable_accrued'
  | 'refund_requested'
  | 'refund_completed'
  | 'payout_initiated'
  | 'payout_completed'
  | 'payout_failed'
  | 'reversal'
  | 'adjustment';
export type LedgerEntryDirection = 'debit' | 'credit';

export interface LedgerAccountRow {
  id: string;
  owner_type: LedgerOwnerType;
  owner_id: string | null;
  account_type: LedgerAccountType;
  currency: string;
  name: string;
  metadata: Record<string, unknown>;
  created_at: Date;
  updated_at: Date;
}

export interface LedgerJournalRow {
  id: string;
  journal_type: LedgerJournalType;
  status: 'posted' | 'reversed';
  source_type: string;
  source_id: string;
  booking_id: string | null;
  payment_id: string | null;
  settlement_id: string | null;
  idempotency_key: string;
  currency: string;
  metadata: Record<string, unknown>;
  created_by: string | null;
  correlation_id: string | null;
  created_at: Date;
}

export interface LedgerEntryRow {
  id: string;
  journal_id: string;
  account_id: string;
  direction: LedgerEntryDirection;
  amount_tzs: string;
  currency: string;
  booking_id: string | null;
  payment_id: string | null;
  settlement_id: string | null;
  source_type: string;
  source_id: string;
  created_at: Date;
}

export interface LedgerJournalWithEntries extends LedgerJournalRow {
  entries: LedgerEntryRow[];
}

export interface LedgerAccountInput {
  ownerType: LedgerOwnerType;
  ownerId?: string | null;
  accountType: LedgerAccountType;
  currency?: string;
  name: string;
  metadata?: Record<string, unknown>;
}

export interface LedgerJournalInput {
  journalType: LedgerJournalType;
  sourceType: string;
  sourceId: string;
  bookingId?: string | null;
  paymentId?: string | null;
  settlementId?: string | null;
  idempotencyKey: string;
  currency?: string;
  metadata?: Record<string, unknown>;
  createdBy?: string | null;
  correlationId?: string | null;
  entries: LedgerEntryInput[];
}

export interface LedgerEntryInput {
  accountId: string;
  direction: LedgerEntryDirection;
  amountTzs: number;
}

interface Queryable {
  query: Pool['query'];
}

export class LedgerRepository {
  constructor(private readonly pool: Pool) {}

  async getOrCreateAccount(input: LedgerAccountInput): Promise<LedgerAccountRow> {
    const currency = input.currency ?? 'TZS';
    const existing = await this.findAccount(input.ownerType, input.ownerId ?? null, input.accountType, currency);
    if (existing) return existing;

    try {
      const { rows } = await this.pool.query<LedgerAccountRow>(
        `INSERT INTO ledger_accounts (owner_type, owner_id, account_type, currency, name, metadata)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING *`,
        [
          input.ownerType,
          input.ownerId ?? null,
          input.accountType,
          currency,
          input.name,
          JSON.stringify(input.metadata ?? {}),
        ],
      );
      return rows[0]!;
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code !== '23505') throw err;
      const account = await this.findAccount(input.ownerType, input.ownerId ?? null, input.accountType, currency);
      if (!account) throw err;
      return account;
    }
  }

  async findAccount(
    ownerType: LedgerOwnerType,
    ownerId: string | null,
    accountType: LedgerAccountType,
    currency = 'TZS',
  ): Promise<LedgerAccountRow | null> {
    const { rows } = await this.pool.query<LedgerAccountRow>(
      `SELECT *
       FROM ledger_accounts
       WHERE owner_type=$1
         AND owner_id IS NOT DISTINCT FROM $2::uuid
         AND account_type=$3
         AND currency=$4`,
      [ownerType, ownerId, accountType, currency],
    );
    return rows[0] ?? null;
  }

  async findJournalByIdempotencyKey(idempotencyKey: string): Promise<LedgerJournalRow | null> {
    const { rows } = await this.pool.query<LedgerJournalRow>(
      'SELECT * FROM ledger_journals WHERE idempotency_key=$1',
      [idempotencyKey],
    );
    return rows[0] ?? null;
  }

  async postJournal(input: LedgerJournalInput): Promise<LedgerJournalRow> {
    const existing = await this.findJournalByIdempotencyKey(input.idempotencyKey);
    if (existing) return existing;

    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const journal = await this.insertJournal(client, input);
      for (const entry of input.entries) {
        await this.insertEntry(client, journal, entry);
      }
      await client.query('COMMIT');
      return journal;
    } catch (err) {
      await client.query('ROLLBACK');
      if ((err as NodeJS.ErrnoException).code === '23505') {
        const duplicate = await this.findJournalByIdempotencyKey(input.idempotencyKey);
        if (duplicate) return duplicate;
      }
      throw err;
    } finally {
      client.release();
    }
  }

  async listEntriesForJournal(journalId: string): Promise<LedgerEntryRow[]> {
    const { rows } = await this.pool.query<LedgerEntryRow>(
      'SELECT * FROM ledger_entries WHERE journal_id=$1 ORDER BY created_at, id',
      [journalId],
    );
    return rows;
  }

  async listJournalsForPayment(paymentId: string): Promise<LedgerJournalWithEntries[]> {
    const { rows } = await this.pool.query<LedgerJournalRow>(
      `SELECT *
       FROM ledger_journals
       WHERE payment_id=$1
       ORDER BY created_at ASC, id ASC`,
      [paymentId],
    );

    const journals: LedgerJournalWithEntries[] = [];
    for (const journal of rows) {
      journals.push({
        ...journal,
        entries: await this.listEntriesForJournal(journal.id),
      });
    }
    return journals;
  }

  async listJournalsForSource(sourceType: string, sourceId: string): Promise<LedgerJournalWithEntries[]> {
    const { rows } = await this.pool.query<LedgerJournalRow>(
      `SELECT *
       FROM ledger_journals
       WHERE source_type=$1 AND source_id=$2
       ORDER BY created_at ASC, id ASC`,
      [sourceType, sourceId],
    );

    const journals: LedgerJournalWithEntries[] = [];
    for (const journal of rows) {
      journals.push({
        ...journal,
        entries: await this.listEntriesForJournal(journal.id),
      });
    }
    return journals;
  }


  async getAccountBalanceTzs(accountId: string): Promise<number> {
    const { rows } = await this.pool.query<{ balance_tzs: string }>(
      `SELECT COALESCE(SUM(
          CASE WHEN direction='credit' THEN amount_tzs ELSE -amount_tzs END
        ), 0)::bigint AS balance_tzs
       FROM ledger_entries
       WHERE account_id=$1`,
      [accountId],
    );
    return Number(rows[0]?.balance_tzs ?? 0);
  }

  private async insertJournal(queryable: Queryable, input: LedgerJournalInput): Promise<LedgerJournalRow> {
    const { rows } = await queryable.query<LedgerJournalRow>(
      `INSERT INTO ledger_journals (
         journal_type, source_type, source_id, booking_id, payment_id, settlement_id,
         idempotency_key, currency, metadata, created_by, correlation_id
       )
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
       RETURNING *`,
      [
        input.journalType,
        input.sourceType,
        input.sourceId,
        input.bookingId ?? null,
        input.paymentId ?? null,
        input.settlementId ?? null,
        input.idempotencyKey,
        input.currency ?? 'TZS',
        JSON.stringify(input.metadata ?? {}),
        input.createdBy ?? null,
        input.correlationId ?? null,
      ],
    );
    return rows[0]!;
  }

  private async insertEntry(
    queryable: Queryable,
    journal: LedgerJournalRow,
    entry: LedgerEntryInput,
  ): Promise<void> {
    await queryable.query(
      `INSERT INTO ledger_entries (
         journal_id, account_id, direction, amount_tzs, currency,
         booking_id, payment_id, settlement_id, source_type, source_id
       )
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`,
      [
        journal.id,
        entry.accountId,
        entry.direction,
        entry.amountTzs,
        journal.currency,
        journal.booking_id,
        journal.payment_id,
        journal.settlement_id,
        journal.source_type,
        journal.source_id,
      ],
    );
  }
}
