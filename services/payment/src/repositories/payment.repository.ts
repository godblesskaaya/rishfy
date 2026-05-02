import type { Pool } from 'pg';
import { randomUUID } from 'crypto';

export interface PaymentRow {
  id: string;
  booking_id: string;
  user_id: string;
  idempotency_key: string | null;
  amount_tzs: number;
  method: string;
  status: 'pending' | 'processing' | 'completed' | 'failed' | 'refunded' | 'partially_refunded';
  provider: string;
  provider_reference: string | null;
  internal_reference: string;
  payer_phone: string;
  failure_code: string | null;
  failure_message: string | null;
  refunded_amount_tzs: number;
  initiated_at: Date;
  completed_at: Date | null;
  failed_at: Date | null;
  last_refund_at: Date | null;
  expires_at: Date | null;
  raw_callback_payload: unknown;
  metadata: Record<string, unknown>;
  created_at: Date;
  updated_at: Date;
}

export class PaymentRepository {
  constructor(private readonly pool: Pool) {}

  async create(data: {
    bookingId: string;
    userId: string;
    idempotencyKey: string;
    amountTzs: number;
    method: string;
    provider: string;
    payerPhone: string;
    expiresAt: Date;
  }): Promise<PaymentRow> {
    const internalRef = `RSHFY-${randomUUID().replace(/-/g, '').slice(0, 16).toUpperCase()}`;
    const { rows } = await this.pool.query<PaymentRow>(
      `INSERT INTO payments
         (booking_id, user_id, idempotency_key, amount_tzs, method, provider,
          internal_reference, payer_phone, expires_at, status)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,'pending')
       ON CONFLICT (idempotency_key) DO UPDATE SET updated_at = now()
       RETURNING *`,
      [data.bookingId, data.userId, data.idempotencyKey, data.amountTzs,
       data.method, data.provider, internalRef, data.payerPhone, data.expiresAt],
    );
    return rows[0]!;
  }

  async findById(id: string): Promise<PaymentRow | null> {
    const { rows } = await this.pool.query<PaymentRow>('SELECT * FROM payments WHERE id = $1', [id]);
    return rows[0] ?? null;
  }

  async findByInternalRef(ref: string): Promise<PaymentRow | null> {
    const { rows } = await this.pool.query<PaymentRow>('SELECT * FROM payments WHERE internal_reference = $1', [ref]);
    return rows[0] ?? null;
  }

  async findByBookingId(bookingId: string): Promise<PaymentRow | null> {
    const { rows } = await this.pool.query<PaymentRow>(
      'SELECT * FROM payments WHERE booking_id = $1 ORDER BY initiated_at DESC LIMIT 1',
      [bookingId],
    );
    return rows[0] ?? null;
  }

  async markCompleted(id: string, providerReference: string): Promise<PaymentRow> {
    const { rows } = await this.pool.query<PaymentRow>(
      `UPDATE payments SET status='completed', provider_reference=$2, completed_at=now(), updated_at=now()
       WHERE id=$1 RETURNING *`,
      [id, providerReference],
    );
    return rows[0]!;
  }

  async markFailed(id: string, code: string, message: string): Promise<PaymentRow> {
    const { rows } = await this.pool.query<PaymentRow>(
      `UPDATE payments SET status='failed', failure_code=$2, failure_message=$3, failed_at=now(), updated_at=now()
       WHERE id=$1 RETURNING *`,
      [id, code, message],
    );
    return rows[0]!;
  }

  async markRefunded(id: string, amountTzs: number, partial: boolean): Promise<PaymentRow> {
    const newStatus = partial ? 'partially_refunded' : 'refunded';
    const { rows } = await this.pool.query<PaymentRow>(
      `UPDATE payments
       SET status=$2, refunded_amount_tzs=refunded_amount_tzs+$3, last_refund_at=now(), updated_at=now()
       WHERE id=$1 RETURNING *`,
      [id, newStatus, amountTzs],
    );
    return rows[0]!;
  }

  async setProviderReference(id: string, providerRef: string): Promise<void> {
    await this.pool.query(
      'UPDATE payments SET provider_reference=$2, status=\'processing\', updated_at=now() WHERE id=$1',
      [id, providerRef],
    );
  }

  async saveCallback(paymentId: string | null, provider: string, rawPayload: string, signature: string, verified: boolean): Promise<void> {
    await this.pool.query(
      `INSERT INTO payment_callbacks (payment_id, provider, raw_payload, signature, verified)
       VALUES ($1, $2, $3, $4, $5)`,
      [paymentId, provider, rawPayload, signature, verified],
    );
  }

  async listByUser(userId: string, limit = 20, offset = 0): Promise<PaymentRow[]> {
    const { rows } = await this.pool.query<PaymentRow>(
      'SELECT * FROM payments WHERE user_id=$1 ORDER BY initiated_at DESC LIMIT $2 OFFSET $3',
      [userId, limit, offset],
    );
    return rows;
  }
}
