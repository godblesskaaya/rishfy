import type { Pool } from 'pg';
import type { PaymentRow } from './payment.repository.js';

export type ReconciliationRecordType = 'payment' | 'refund' | 'payout';
export type ReconciliationStatus = 'matched' | 'unmatched' | 'amount_mismatch' | 'status_mismatch';

export interface ReconciliationRecordRow {
  id: string;
  provider: string;
  record_type: ReconciliationRecordType;
  provider_reference: string;
  amount_tzs: string;
  provider_status: string;
  occurred_at: Date | null;
  match_status: ReconciliationStatus;
  matched_payment_id: string | null;
  mismatch_reason: string | null;
  raw_payload: Record<string, unknown>;
  imported_by: string;
  imported_at: Date;
  created_at: Date;
}

export class ReconciliationRepository {
  constructor(private readonly pool: Pool) {}

  async findPaymentByProviderReference(providerReference: string): Promise<PaymentRow | null> {
    const { rows } = await this.pool.query<PaymentRow>(
      'SELECT * FROM payments WHERE provider_reference=$1 ORDER BY completed_at DESC NULLS LAST LIMIT 1',
      [providerReference],
    );
    return rows[0] ?? null;
  }

  async findRefundByProviderReference(providerReference: string): Promise<{
    id: string;
    payment_id: string;
    amount_tzs: number;
    status: string;
  } | null> {
    const { rows } = await this.pool.query<{
      id: string;
      payment_id: string;
      amount_tzs: number;
      status: string;
    }>(
      'SELECT id, payment_id, amount_tzs, status FROM refunds WHERE provider_reference=$1 ORDER BY completed_at DESC NULLS LAST LIMIT 1',
      [providerReference],
    );
    return rows[0] ?? null;
  }

  async findPayoutByProviderReference(providerReference: string): Promise<{
    id: string;
    amount_tzs: string;
    status: string;
  } | null> {
    const { rows } = await this.pool.query<{
      id: string;
      amount_tzs: string;
      status: string;
    }>(
      'SELECT id, amount_tzs, status FROM payouts WHERE provider_reference=$1 OR id::text=$1 ORDER BY completed_at DESC NULLS LAST LIMIT 1',
      [providerReference],
    );
    return rows[0] ?? null;
  }

  async createRecord(data: {
    provider: string;
    recordType: ReconciliationRecordType;
    providerReference: string;
    amountTzs: number;
    providerStatus: string;
    occurredAt?: Date | null;
    matchStatus: ReconciliationStatus;
    matchedPaymentId?: string | null;
    mismatchReason?: string | null;
    rawPayload?: Record<string, unknown>;
    importedBy: string;
  }): Promise<ReconciliationRecordRow> {
    const { rows } = await this.pool.query<ReconciliationRecordRow>(
      `INSERT INTO provider_reconciliation_records (
         provider, record_type, provider_reference, amount_tzs, provider_status,
         occurred_at, match_status, matched_payment_id, mismatch_reason, raw_payload, imported_by
       )
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
       ON CONFLICT (provider, record_type, provider_reference)
       DO UPDATE SET
         amount_tzs=EXCLUDED.amount_tzs,
         provider_status=EXCLUDED.provider_status,
         occurred_at=EXCLUDED.occurred_at,
         match_status=EXCLUDED.match_status,
         matched_payment_id=EXCLUDED.matched_payment_id,
         mismatch_reason=EXCLUDED.mismatch_reason,
         raw_payload=EXCLUDED.raw_payload,
         imported_by=EXCLUDED.imported_by,
         imported_at=now()
       RETURNING *`,
      [
        data.provider,
        data.recordType,
        data.providerReference,
        data.amountTzs,
        data.providerStatus,
        data.occurredAt ?? null,
        data.matchStatus,
        data.matchedPaymentId ?? null,
        data.mismatchReason ?? null,
        JSON.stringify(data.rawPayload ?? {}),
        data.importedBy,
      ],
    );
    return rows[0]!;
  }

  async list(params: { status?: ReconciliationStatus; limit: number; offset: number }): Promise<ReconciliationRecordRow[]> {
    const values: unknown[] = [];
    const where: string[] = [];
    if (params.status) {
      values.push(params.status);
      where.push(`match_status=$${values.length}`);
    }
    const whereClause = where.length > 0 ? `WHERE ${where.join(' AND ')}` : '';
    const { rows } = await this.pool.query<ReconciliationRecordRow>(
      `SELECT *
       FROM provider_reconciliation_records
       ${whereClause}
       ORDER BY imported_at DESC
       LIMIT $${values.length + 1} OFFSET $${values.length + 2}`,
      [...values, params.limit, params.offset],
    );
    return rows;
  }

  async listForPayout(providerReference: string | null, payoutId: string): Promise<ReconciliationRecordRow[]> {
    const references = [providerReference, payoutId].filter((value): value is string => Boolean(value));
    if (references.length === 0) return [];
    const { rows } = await this.pool.query<ReconciliationRecordRow>(
      `SELECT *
       FROM provider_reconciliation_records
       WHERE record_type='payout'
         AND provider_reference = ANY($1::text[])
       ORDER BY imported_at DESC`,
      [references],
    );
    return rows;
  }
}
