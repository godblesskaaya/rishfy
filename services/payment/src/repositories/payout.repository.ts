import type { Pool } from 'pg';

export interface PayoutRow {
  id: string;
  driver_user_id: string;
  amount_tzs: string;
  currency: string;
  status: 'pending_review' | 'processing' | 'completed' | 'failed' | 'cancelled';
  payout_method: string;
  payout_phone: string;
  requested_by: string;
  reviewed_by: string | null;
  provider_reference: string | null;
  failure_reason: string | null;
  requested_at: Date;
  reviewed_at: Date | null;
  processing_at: Date | null;
  completed_at: Date | null;
  failed_at: Date | null;
  cancelled_at: Date | null;
  metadata: Record<string, unknown>;
  created_at: Date;
  updated_at: Date;
}

export interface EligiblePayableRow {
  ledger_entry_id: string;
  booking_id: string | null;
  amount_tzs: string;
}

export interface PayoutItemRow {
  id: string;
  payout_id: string;
  ledger_entry_id: string;
  booking_id: string | null;
  amount_tzs: string;
  released_at: Date | null;
  created_at: Date;
}

export interface DriverBalance {
  available_tzs: number;
  pending_payout_tzs: number;
  held_tzs: number;
  paid_out_tzs: number;
  total_earned_tzs: number;
  total_platform_fees_tzs: number;
  trip_count: number;
}

export interface PayoutListResult {
  items: PayoutRow[];
  totalCount: number;
}

export type PayoutHoldReason = 'safety_report' | 'dispute' | 'no_show' | 'chargeback' | 'admin_review';

export interface PayoutHoldRow {
  id: string;
  driver_user_id: string;
  ledger_entry_id: string;
  booking_id: string | null;
  amount_tzs: string;
  reason: PayoutHoldReason;
  note: string | null;
  created_by: string;
  released_by: string | null;
  released_at: Date | null;
  created_at: Date;
  updated_at: Date;
}

export interface PayoutHoldRequestRow {
  id: string;
  booking_id: string;
  driver_user_id: string;
  requested_by: string;
  reason: PayoutHoldReason;
  note: string | null;
  status: 'pending' | 'applied' | 'ignored';
  payout_hold_id: string | null;
  applied_at: Date | null;
  created_at: Date;
  updated_at: Date;
}

export class PayoutRepository {
  constructor(private readonly pool: Pool) {}

  async getDriverBalance(driverUserId: string): Promise<DriverBalance> {
    const { rows } = await this.pool.query<{
      available_tzs: string;
      pending_payout_tzs: string;
      held_tzs: string;
      paid_out_tzs: string;
      total_platform_fees_tzs: string;
      trip_count: string;
    }>(
      `WITH driver_payables AS (
         SELECT le.id, le.amount_tzs
         FROM ledger_entries le
         JOIN ledger_accounts la ON la.id = le.account_id
         WHERE la.owner_type='driver'
           AND la.owner_id=$1
           AND la.account_type='driver_payable'
           AND le.direction='credit'
       ),
       platform_fee_entries AS (
         SELECT DISTINCT lj.id AS journal_id, le.amount_tzs
         FROM ledger_entries driver_le
         JOIN ledger_accounts driver_la ON driver_la.id = driver_le.account_id
         JOIN ledger_journals lj ON lj.id = driver_le.journal_id
         JOIN ledger_entries le ON le.journal_id = lj.id
         JOIN ledger_accounts la ON la.id = le.account_id
         WHERE driver_la.owner_type='driver'
           AND driver_la.owner_id=$1
           AND driver_la.account_type='driver_payable'
           AND driver_le.direction='credit'
           AND la.account_type='platform_revenue'
           AND le.direction='credit'
       ),
       active_items AS (
         SELECT pi.ledger_entry_id, p.status, pi.amount_tzs
         FROM payout_items pi
         JOIN payouts p ON p.id = pi.payout_id
         WHERE pi.released_at IS NULL
           AND p.driver_user_id=$1
           AND p.status IN ('pending_review','processing','completed')
       ),
       active_holds AS (
         SELECT ph.ledger_entry_id, ph.amount_tzs
         FROM payout_holds ph
         WHERE ph.released_at IS NULL
           AND ph.driver_user_id=$1
       )
       SELECT
         COALESCE((
           SELECT SUM(dp.amount_tzs)
           FROM driver_payables dp
           WHERE NOT EXISTS (SELECT 1 FROM active_items ai WHERE ai.ledger_entry_id = dp.id)
             AND NOT EXISTS (SELECT 1 FROM active_holds ah WHERE ah.ledger_entry_id = dp.id)
         ), 0)::bigint AS available_tzs,
         COALESCE((
           SELECT SUM(ai.amount_tzs)
           FROM active_items ai
           WHERE ai.status IN ('pending_review','processing')
         ), 0)::bigint AS pending_payout_tzs,
         COALESCE((SELECT SUM(ah.amount_tzs) FROM active_holds ah), 0)::bigint AS held_tzs,
         COALESCE((
           SELECT SUM(ai.amount_tzs)
           FROM active_items ai
           WHERE ai.status='completed'
         ), 0)::bigint AS paid_out_tzs,
         COALESCE((SELECT SUM(pfe.amount_tzs) FROM platform_fee_entries pfe), 0)::bigint AS total_platform_fees_tzs,
         COALESCE((SELECT COUNT(*) FROM driver_payables), 0)::int AS trip_count`,
      [driverUserId],
    );

    const row = rows[0];
    const available = Number(row?.available_tzs ?? 0);
    const pending = Number(row?.pending_payout_tzs ?? 0);
    const paidOut = Number(row?.paid_out_tzs ?? 0);
    const held = Number(row?.held_tzs ?? 0);
    const platformFees = Number(row?.total_platform_fees_tzs ?? 0);
    const tripCount = Number(row?.trip_count ?? 0);

    return {
      available_tzs: available,
      pending_payout_tzs: pending,
      held_tzs: held,
      paid_out_tzs: paidOut,
      total_earned_tzs: available + pending + held + paidOut,
      total_platform_fees_tzs: platformFees,
      trip_count: tripCount,
    };
  }

  async createRequest(data: {
    driverUserId: string;
    payoutMethod: string;
    payoutPhone: string;
    requestedBy: string;
  }): Promise<PayoutRow> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const payables = await this.listEligiblePayablesForUpdate(client, data.driverUserId);
      if (payables.length === 0) {
        throw Object.assign(new Error('No payable balance available'), { code: 'NO_PAYABLE_BALANCE' });
      }

      const amountTzs = payables.reduce((sum, item) => sum + Number(item.amount_tzs), 0);
      const { rows } = await client.query<PayoutRow>(
        `INSERT INTO payouts (driver_user_id, amount_tzs, payout_method, payout_phone, requested_by)
         VALUES ($1,$2,$3,$4,$5)
         RETURNING *`,
        [data.driverUserId, amountTzs, data.payoutMethod, data.payoutPhone, data.requestedBy],
      );
      const payout = rows[0]!;

      for (const item of payables) {
        await client.query(
          `INSERT INTO payout_items (payout_id, ledger_entry_id, booking_id, amount_tzs)
           VALUES ($1,$2,$3,$4)`,
          [payout.id, item.ledger_entry_id, item.booking_id, item.amount_tzs],
        );
      }

      await client.query('COMMIT');
      return payout;
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  async findById(id: string): Promise<PayoutRow | null> {
    const { rows } = await this.pool.query<PayoutRow>(
      'SELECT * FROM payouts WHERE id=$1',
      [id],
    );
    return rows[0] ?? null;
  }

  async list(params: { status?: string; limit: number; offset: number }): Promise<PayoutListResult> {
    const values: unknown[] = [];
    const where: string[] = [];
    if (params.status) {
      values.push(params.status);
      where.push(`status = $${values.length}`);
    }
    const whereClause = where.length > 0 ? `WHERE ${where.join(' AND ')}` : '';

    const count = await this.pool.query<{ total_count: string }>(
      `SELECT COUNT(*)::bigint AS total_count FROM payouts ${whereClause}`,
      values,
    );

    const itemValues = [...values, params.limit, params.offset];
    const { rows } = await this.pool.query<PayoutRow>(
      `SELECT *
       FROM payouts
       ${whereClause}
       ORDER BY requested_at DESC
       LIMIT $${values.length + 1} OFFSET $${values.length + 2}`,
      itemValues,
    );

    return {
      items: rows,
      totalCount: Number(count.rows[0]?.total_count ?? 0),
    };
  }

  async listForDriver(params: {
    driverUserId: string;
    limit: number;
    offset: number;
  }): Promise<PayoutListResult> {
    const count = await this.pool.query<{ total_count: string }>(
      'SELECT COUNT(*)::bigint AS total_count FROM payouts WHERE driver_user_id=$1',
      [params.driverUserId],
    );

    const { rows } = await this.pool.query<PayoutRow>(
      `SELECT *
       FROM payouts
       WHERE driver_user_id=$1
       ORDER BY requested_at DESC
       LIMIT $2 OFFSET $3`,
      [params.driverUserId, params.limit, params.offset],
    );

    return {
      items: rows,
      totalCount: Number(count.rows[0]?.total_count ?? 0),
    };
  }

  async listItems(payoutId: string): Promise<PayoutItemRow[]> {
    const { rows } = await this.pool.query<PayoutItemRow>(
      'SELECT * FROM payout_items WHERE payout_id=$1 ORDER BY id ASC',
      [payoutId],
    );
    return rows;
  }

  async listHoldsForPayout(payoutId: string): Promise<PayoutHoldRow[]> {
    const { rows } = await this.pool.query<PayoutHoldRow>(
      `SELECT DISTINCT ph.*
       FROM payout_holds ph
       JOIN payout_items pi ON pi.ledger_entry_id = ph.ledger_entry_id
       WHERE pi.payout_id=$1
       ORDER BY ph.created_at DESC`,
      [payoutId],
    );
    return rows;
  }

  async approve(id: string, reviewedBy: string): Promise<PayoutRow | null> {
    const { rows } = await this.pool.query<PayoutRow>(
      `UPDATE payouts
       SET status='processing', reviewed_by=$2, reviewed_at=now(), processing_at=now(), updated_at=now()
       WHERE id=$1 AND status='pending_review'
       RETURNING *`,
      [id, reviewedBy],
    );
    return rows[0] ?? null;
  }

  async markCompleted(id: string, providerReference: string): Promise<PayoutRow | null> {
    const { rows } = await this.pool.query<PayoutRow>(
      `UPDATE payouts
       SET status='completed', provider_reference=$2, completed_at=now(), updated_at=now()
       WHERE id=$1 AND status='processing'
       RETURNING *`,
      [id, providerReference],
    );
    return rows[0] ?? null;
  }

  async markFailed(id: string, failureReason: string): Promise<PayoutRow | null> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const { rows } = await client.query<PayoutRow>(
        `UPDATE payouts
         SET status='failed', failure_reason=$2, failed_at=now(), updated_at=now()
         WHERE id=$1 AND status IN ('pending_review','processing')
         RETURNING *`,
        [id, failureReason],
      );
      const payout = rows[0] ?? null;
      if (payout) {
        await client.query(
          `UPDATE payout_items SET released_at=now() WHERE payout_id=$1 AND released_at IS NULL`,
          [id],
        );
      }
      await client.query('COMMIT');
      return payout;
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  async createHold(data: {
    driverUserId: string;
    ledgerEntryId?: string;
    bookingId?: string;
    reason: PayoutHoldReason;
    note?: string | null;
    createdBy: string;
  }): Promise<PayoutHoldRow> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const payable = await this.findHoldablePayableForUpdate(client, {
        driverUserId: data.driverUserId,
        ledgerEntryId: data.ledgerEntryId,
        bookingId: data.bookingId,
      });
      if (!payable) {
        throw Object.assign(new Error('No holdable payable entry found'), { code: 'NO_HOLDABLE_PAYABLE' });
      }

      const { rows } = await client.query<PayoutHoldRow>(
        `INSERT INTO payout_holds
           (driver_user_id, ledger_entry_id, booking_id, amount_tzs, reason, note, created_by)
         VALUES ($1,$2,$3,$4,$5,$6,$7)
         RETURNING *`,
        [
          data.driverUserId,
          payable.ledger_entry_id,
          payable.booking_id,
          payable.amount_tzs,
          data.reason,
          data.note ?? null,
          data.createdBy,
        ],
      );

      await client.query('COMMIT');
      return rows[0]!;
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  async releaseHold(id: string, releasedBy: string): Promise<PayoutHoldRow | null> {
    const { rows } = await this.pool.query<PayoutHoldRow>(
      `UPDATE payout_holds
       SET released_by=$2, released_at=now(), updated_at=now()
       WHERE id=$1 AND released_at IS NULL
       RETURNING *`,
      [id, releasedBy],
    );
    return rows[0] ?? null;
  }

  async createSafetyHoldRequest(data: {
    bookingId: string;
    driverUserId: string;
    requestedBy: string;
    note: string;
  }): Promise<PayoutHoldRequestRow> {
    const { rows } = await this.pool.query<PayoutHoldRequestRow>(
      `INSERT INTO payout_hold_requests (booking_id, driver_user_id, requested_by, reason, note)
       VALUES ($1,$2,$3,'safety_report',$4)
       ON CONFLICT (booking_id) WHERE status='pending'
       DO UPDATE SET note=EXCLUDED.note, updated_at=now()
       RETURNING *`,
      [data.bookingId, data.driverUserId, data.requestedBy, data.note],
    );
    return rows[0]!;
  }

  async applyPendingHoldRequestForBooking(bookingId: string): Promise<PayoutHoldRow | null> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const requestResult = await client.query<PayoutHoldRequestRow>(
        `SELECT *
         FROM payout_hold_requests
         WHERE booking_id=$1 AND status='pending'
         ORDER BY created_at ASC
         LIMIT 1
         FOR UPDATE`,
        [bookingId],
      );
      const request = requestResult.rows[0];
      if (!request) {
        await client.query('COMMIT');
        return null;
      }

      const existingHold = await this.findActiveHoldByBooking(client, request.booking_id, request.driver_user_id);
      if (existingHold) {
        await this.markHoldRequestApplied(client, request.id, existingHold.id);
        await client.query('COMMIT');
        return existingHold;
      }

      const payable = await this.findHoldablePayableForUpdate(client, {
        driverUserId: request.driver_user_id,
        bookingId: request.booking_id,
      });
      if (!payable) {
        await client.query('COMMIT');
        return null;
      }

      const { rows } = await client.query<PayoutHoldRow>(
        `INSERT INTO payout_holds
           (driver_user_id, ledger_entry_id, booking_id, amount_tzs, reason, note, created_by)
         VALUES ($1,$2,$3,$4,$5,$6,$7)
         RETURNING *`,
        [
          request.driver_user_id,
          payable.ledger_entry_id,
          payable.booking_id,
          payable.amount_tzs,
          request.reason,
          request.note,
          request.requested_by,
        ],
      );
      const hold = rows[0]!;
      await this.markHoldRequestApplied(client, request.id, hold.id);

      await client.query('COMMIT');
      return hold;
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  private async listEligiblePayablesForUpdate(
    client: Pick<Pool, 'query'>,
    driverUserId: string,
  ): Promise<EligiblePayableRow[]> {
    const { rows } = await client.query<EligiblePayableRow>(
      `SELECT le.id AS ledger_entry_id, le.booking_id, le.amount_tzs
       FROM ledger_entries le
       JOIN ledger_accounts la ON la.id = le.account_id
       LEFT JOIN payout_items pi ON pi.ledger_entry_id = le.id AND pi.released_at IS NULL
       LEFT JOIN payout_holds ph ON ph.ledger_entry_id = le.id AND ph.released_at IS NULL
       WHERE la.owner_type='driver'
         AND la.owner_id=$1
         AND la.account_type='driver_payable'
         AND le.direction='credit'
         AND pi.id IS NULL
         AND ph.id IS NULL
       ORDER BY le.created_at ASC, le.id ASC
       FOR UPDATE OF le`,
      [driverUserId],
    );
    return rows;
  }

  private async findHoldablePayableForUpdate(
    client: Pick<Pool, 'query'>,
    data: { driverUserId: string; ledgerEntryId?: string; bookingId?: string },
  ): Promise<EligiblePayableRow | null> {
    const filter = data.ledgerEntryId ? 'le.id=$2' : 'le.booking_id=$2';
    const filterValue = data.ledgerEntryId ?? data.bookingId;
    const { rows } = await client.query<EligiblePayableRow>(
      `SELECT le.id AS ledger_entry_id, le.booking_id, le.amount_tzs
       FROM ledger_entries le
       JOIN ledger_accounts la ON la.id = le.account_id
       LEFT JOIN payout_items pi ON pi.ledger_entry_id = le.id AND pi.released_at IS NULL
       LEFT JOIN payout_holds ph ON ph.ledger_entry_id = le.id AND ph.released_at IS NULL
       WHERE la.owner_type='driver'
         AND la.owner_id=$1
         AND la.account_type='driver_payable'
         AND le.direction='credit'
         AND ${filter}
         AND pi.id IS NULL
         AND ph.id IS NULL
       ORDER BY le.created_at ASC, le.id ASC
       LIMIT 1
       FOR UPDATE OF le`,
      [data.driverUserId, filterValue],
    );
    return rows[0] ?? null;
  }

  private async findActiveHoldByBooking(
    client: Pick<Pool, 'query'>,
    bookingId: string,
    driverUserId: string,
  ): Promise<PayoutHoldRow | null> {
    const { rows } = await client.query<PayoutHoldRow>(
      `SELECT *
       FROM payout_holds
       WHERE booking_id=$1
         AND driver_user_id=$2
         AND released_at IS NULL
       ORDER BY created_at ASC
       LIMIT 1`,
      [bookingId, driverUserId],
    );
    return rows[0] ?? null;
  }

  private async markHoldRequestApplied(
    client: Pick<Pool, 'query'>,
    requestId: string,
    holdId: string,
  ): Promise<void> {
    await client.query(
      `UPDATE payout_hold_requests
       SET status='applied', payout_hold_id=$2, applied_at=now(), updated_at=now()
       WHERE id=$1`,
      [requestId, holdId],
    );
  }
}
