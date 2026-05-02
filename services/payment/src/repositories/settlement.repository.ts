import type { Pool } from 'pg';
export interface SettlementRow {
  id: string;
  driver_user_id: string;
  period_start: Date;
  period_end: Date;
  total_amount_tzs: number;
  platform_fee_tzs: number;
  net_amount_tzs: number;
  booking_count: number;
  payout_method: string;
  payout_phone: string;
  status: 'pending' | 'processing' | 'completed' | 'failed';
  provider_reference: string | null;
  failure_reason: string | null;
  initiated_at: Date | null;
  completed_at: Date | null;
  created_at: Date;
  updated_at: Date;
}

export interface EarningsSummary {
  total_earnings_tzs: number;
  total_platform_fees_tzs: number;
  total_settled_tzs: number;
  pending_balance_tzs: number;
  trip_count: number;
}

export class SettlementRepository {
  constructor(private readonly pool: Pool) {}

  async create(data: {
    driverUserId: string;
    periodStart: Date;
    periodEnd: Date;
    totalAmountTzs: number;
    platformFeeTzs: number;
    netAmountTzs: number;
    bookingCount: number;
    payoutMethod: string;
    payoutPhone: string;
    bookingIds: Array<{ bookingId: string; driverEarningsTzs: number }>;
  }): Promise<SettlementRow> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const { rows } = await client.query<SettlementRow>(
        `INSERT INTO settlements
           (driver_user_id, period_start, period_end, total_amount_tzs, platform_fee_tzs, net_amount_tzs, booking_count, payout_method, payout_phone)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
         RETURNING *`,
        [data.driverUserId, data.periodStart, data.periodEnd, data.totalAmountTzs,
         data.platformFeeTzs, data.netAmountTzs, data.bookingCount, data.payoutMethod, data.payoutPhone],
      );
      const settlement = rows[0]!;
      for (const b of data.bookingIds) {
        await client.query(
          'INSERT INTO settlement_bookings (settlement_id, booking_id, driver_earnings_tzs) VALUES ($1,$2,$3)',
          [settlement.id, b.bookingId, b.driverEarningsTzs],
        );
      }
      await client.query('COMMIT');
      return settlement;
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  async findById(id: string): Promise<SettlementRow | null> {
    const { rows } = await this.pool.query<SettlementRow>('SELECT * FROM settlements WHERE id=$1', [id]);
    return rows[0] ?? null;
  }

  async getDriverEarnings(driverUserId: string, fromDate: Date, toDate: Date): Promise<EarningsSummary> {
    // Query payments table for completed payments for this driver's bookings
    const { rows } = await this.pool.query<EarningsSummary>(
      `SELECT
         COALESCE(SUM(net_amount_tzs), 0)::bigint as total_earnings_tzs,
         COALESCE(SUM(platform_fee_tzs), 0)::bigint as total_platform_fees_tzs,
         COALESCE(SUM(CASE WHEN status='completed' THEN net_amount_tzs ELSE 0 END), 0)::bigint as total_settled_tzs,
         COALESCE(SUM(CASE WHEN status='pending' THEN net_amount_tzs ELSE 0 END), 0)::bigint as pending_balance_tzs,
         COUNT(*)::int as trip_count
       FROM settlements
       WHERE driver_user_id=$1 AND period_start >= $2 AND period_end <= $3`,
      [driverUserId, fromDate, toDate],
    );
    return rows[0] ?? { total_earnings_tzs: 0, total_platform_fees_tzs: 0, total_settled_tzs: 0, pending_balance_tzs: 0, trip_count: 0 };
  }
}
