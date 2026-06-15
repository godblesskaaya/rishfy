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

export interface RefundRow {
  id: string;
  payment_id: string;
  booking_id: string;
  user_id: string;
  amount_tzs: number;
  status: 'requested' | 'processing' | 'completed' | 'failed' | 'manual_required';
  reason: string;
  policy: string;
  provider_reference: string | null;
  failure_reason: string | null;
  requested_by: string;
  requested_at: Date;
  completed_at: Date | null;
  failed_at: Date | null;
  metadata: Record<string, unknown>;
  created_at: Date;
  updated_at: Date;
}

export interface PaymentListResult {
  items: PaymentRow[];
  totalCount: number;
}

export interface PaymentOutboxEventInput {
  eventKey: string;
  topic: string;
  messageKey: string;
  payload: Record<string, unknown>;
}

export interface PaymentOutboxEventRow {
  id: string;
  event_key: string;
  topic: string;
  message_key: string;
  payload: Record<string, unknown>;
  status: 'pending' | 'publishing' | 'published' | 'dead';
  attempts: number;
  next_attempt_at: Date;
  locked_at: Date | null;
  published_at: Date | null;
  last_error: string | null;
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

  async createRefund(data: {
    paymentId: string;
    bookingId: string;
    userId: string;
    amountTzs: number;
    reason: string;
    policy: string;
    requestedBy: string;
  }): Promise<RefundRow> {
    const { rows } = await this.pool.query<RefundRow>(
      `INSERT INTO refunds (payment_id, booking_id, user_id, amount_tzs, reason, policy, requested_by)
       VALUES ($1,$2,$3,$4,$5,$6,$7)
       RETURNING *`,
      [
        data.paymentId,
        data.bookingId,
        data.userId,
        data.amountTzs,
        data.reason,
        data.policy,
        data.requestedBy,
      ],
    );
    return rows[0]!;
  }

  async markRefundCompleted(id: string, providerReference: string): Promise<RefundRow> {
    const { rows } = await this.pool.query<RefundRow>(
      `UPDATE refunds
       SET status='completed', provider_reference=$2, completed_at=now(), updated_at=now()
       WHERE id=$1 RETURNING *`,
      [id, providerReference],
    );
    return rows[0]!;
  }

  async markRefundFailed(id: string, failureReason: string): Promise<RefundRow> {
    const { rows } = await this.pool.query<RefundRow>(
      `UPDATE refunds
       SET status='failed', failure_reason=$2, failed_at=now(), updated_at=now()
       WHERE id=$1 RETURNING *`,
      [id, failureReason],
    );
    return rows[0]!;
  }

  async markRefundManualRequired(id: string, failureReason: string): Promise<RefundRow> {
    const { rows } = await this.pool.query<RefundRow>(
      `UPDATE refunds
       SET status='manual_required', failure_reason=$2, failed_at=now(), updated_at=now()
       WHERE id=$1 RETURNING *`,
      [id, failureReason],
    );
    return rows[0]!;
  }

  async listRefundsForPayment(paymentId: string): Promise<RefundRow[]> {
    const { rows } = await this.pool.query<RefundRow>(
      `SELECT *
       FROM refunds
       WHERE payment_id=$1
       ORDER BY requested_at DESC, id DESC`,
      [paymentId],
    );
    return rows;
  }

  async findRefundById(id: string): Promise<RefundRow | null> {
    const { rows } = await this.pool.query<RefundRow>(
      'SELECT * FROM refunds WHERE id=$1',
      [id],
    );
    return rows[0] ?? null;
  }

  async listRefunds(params: {
    status?: string;
    limit: number;
    offset: number;
  }): Promise<{ items: RefundRow[]; totalCount: number }> {
    const values: unknown[] = [];
    const where: string[] = [];
    if (params.status) {
      values.push(params.status);
      where.push(`status=$${values.length}`);
    }
    const whereClause = where.length > 0 ? `WHERE ${where.join(' AND ')}` : '';
    const count = await this.pool.query<{ total_count: string }>(
      `SELECT COUNT(*)::bigint AS total_count FROM refunds ${whereClause}`,
      values,
    );
    const { rows } = await this.pool.query<RefundRow>(
      `SELECT *
       FROM refunds
       ${whereClause}
       ORDER BY requested_at DESC, id DESC
       LIMIT $${values.length + 1} OFFSET $${values.length + 2}`,
      [...values, params.limit, params.offset],
    );
    return {
      items: rows,
      totalCount: Number(count.rows[0]?.total_count ?? 0),
    };
  }

  async setProviderReference(id: string, providerRef: string): Promise<void> {
    await this.pool.query(
      `UPDATE payments
       SET provider_reference=$2,
           status=CASE WHEN status='pending' THEN 'processing' ELSE status END,
           updated_at=now()
       WHERE id=$1`,
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

  async list(params: { status?: string; limit: number; offset: number }): Promise<PaymentListResult> {
    const values: unknown[] = [];
    const where: string[] = [];
    if (params.status) {
      values.push(params.status);
      where.push(`status = $${values.length}`);
    }
    const whereClause = where.length > 0 ? `WHERE ${where.join(' AND ')}` : '';

    const count = await this.pool.query<{ total_count: string }>(
      `SELECT COUNT(*)::bigint AS total_count FROM payments ${whereClause}`,
      values,
    );

    const itemValues = [...values, params.limit, params.offset];
    const { rows } = await this.pool.query<PaymentRow>(
      `SELECT *
       FROM payments
       ${whereClause}
       ORDER BY initiated_at DESC
       LIMIT $${values.length + 1} OFFSET $${values.length + 2}`,
      itemValues,
    );

    return {
      items: rows,
      totalCount: Number(count.rows[0]?.total_count ?? 0),
    };
  }

  async enqueueOutboxEvent(data: PaymentOutboxEventInput): Promise<PaymentOutboxEventRow> {
    const { rows } = await this.pool.query<PaymentOutboxEventRow>(
      `INSERT INTO payment_event_outbox (event_key, topic, message_key, payload)
       VALUES ($1,$2,$3,$4::jsonb)
       ON CONFLICT (event_key) DO NOTHING
       RETURNING *`,
      [data.eventKey, data.topic, data.messageKey, JSON.stringify(data.payload)],
    );
    if (rows[0]) return rows[0];

    const existing = await this.pool.query<PaymentOutboxEventRow>(
      'SELECT * FROM payment_event_outbox WHERE event_key=$1',
      [data.eventKey],
    );
    return existing.rows[0]!;
  }

  async claimPendingOutboxEvents(limit: number): Promise<PaymentOutboxEventRow[]> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const { rows } = await client.query<PaymentOutboxEventRow>(
        `WITH next_events AS (
           SELECT id
           FROM payment_event_outbox
           WHERE status='pending'
             AND next_attempt_at <= now()
           ORDER BY created_at ASC
           LIMIT $1
           FOR UPDATE SKIP LOCKED
         )
         UPDATE payment_event_outbox poe
         SET status='publishing',
             attempts=poe.attempts + 1,
             locked_at=now(),
             updated_at=now()
         FROM next_events ne
         WHERE poe.id=ne.id
         RETURNING poe.*`,
        [limit],
      );
      await client.query('COMMIT');
      return rows;
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  async markOutboxPublished(id: string): Promise<void> {
    await this.pool.query(
      `UPDATE payment_event_outbox
       SET status='published', published_at=now(), locked_at=NULL, last_error=NULL, updated_at=now()
       WHERE id=$1`,
      [id],
    );
  }

  async markOutboxPublishFailed(id: string, error: string): Promise<void> {
    await this.pool.query(
      `UPDATE payment_event_outbox
       SET status=CASE WHEN attempts >= 10 THEN 'dead' ELSE 'pending' END,
           next_attempt_at=CASE
             WHEN attempts >= 10 THEN next_attempt_at
             ELSE now() + make_interval(secs => LEAST(300, GREATEST(5, attempts * 10)))
           END,
           locked_at=NULL,
           last_error=$2,
           updated_at=now()
       WHERE id=$1`,
      [id, error],
    );
  }
}
