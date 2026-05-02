import type { Pool } from 'pg';

export interface NotificationRow {
  id: string;
  user_id: string;
  template_key: string;
  channel: 'sms' | 'push' | 'in_app' | 'email';
  status: 'pending' | 'queued' | 'delivered' | 'failed' | 'skipped';
  title: string | null;
  body: string;
  data: Record<string, unknown>;
  is_read: boolean;
  read_at: Date | null;
  provider_message_id: string | null;
  failure_reason: string | null;
  retry_count: number;
  source_event_type: string | null;
  source_event_id: string | null;
  scheduled_for: Date | null;
  sent_at: Date | null;
  created_at: Date;
  updated_at: Date;
}

export interface TemplateRow {
  id: string;
  key: string;
  lang: string;
  channel: string;
  subject: string | null;
  body_template: string;
  variables: string[];
  is_active: boolean;
}

export class NotificationRepository {
  constructor(private readonly pool: Pool) {}

  async getTemplate(key: string, lang: string, channel: string): Promise<TemplateRow | null> {
    // Try exact lang first, fall back to 'en'
    const { rows } = await this.pool.query<TemplateRow>(
      `SELECT * FROM notification_templates
       WHERE key=$1 AND channel=$2 AND is_active=true
       ORDER BY CASE WHEN lang=$3 THEN 0 ELSE 1 END
       LIMIT 1`,
      [key, channel, lang],
    );
    return rows[0] ?? null;
  }

  async create(data: {
    userId: string;
    templateKey: string;
    channel: string;
    title?: string;
    body: string;
    data?: Record<string, unknown>;
    sourceEventType?: string;
    sourceEventId?: string;
  }): Promise<NotificationRow> {
    const { rows } = await this.pool.query<NotificationRow>(
      `INSERT INTO notifications
         (user_id, template_key, channel, title, body, data, source_event_type, source_event_id)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
       RETURNING *`,
      [
        data.userId, data.templateKey, data.channel,
        data.title ?? null, data.body,
        JSON.stringify(data.data ?? {}),
        data.sourceEventType ?? null, data.sourceEventId ?? null,
      ],
    );
    return rows[0]!;
  }

  async markDelivered(id: string, providerMessageId?: string): Promise<void> {
    await this.pool.query(
      `UPDATE notifications SET status='delivered', sent_at=now(), provider_message_id=$2, updated_at=now() WHERE id=$1`,
      [id, providerMessageId ?? null],
    );
  }

  async markFailed(id: string, reason: string): Promise<void> {
    await this.pool.query(
      `UPDATE notifications SET status='failed', failure_reason=$2, retry_count=retry_count+1, updated_at=now() WHERE id=$1`,
      [id, reason],
    );
  }

  async markRead(id: string, userId: string): Promise<void> {
    await this.pool.query(
      `UPDATE notifications SET is_read=true, read_at=now(), updated_at=now() WHERE id=$1 AND user_id=$2`,
      [id, userId],
    );
  }

  async markAllRead(userId: string): Promise<void> {
    await this.pool.query(
      `UPDATE notifications SET is_read=true, read_at=now(), updated_at=now() WHERE user_id=$1 AND is_read=false`,
      [userId],
    );
  }

  async listByUser(userId: string, limit = 30, offset = 0): Promise<NotificationRow[]> {
    const { rows } = await this.pool.query<NotificationRow>(
      `SELECT * FROM notifications WHERE user_id=$1 ORDER BY created_at DESC LIMIT $2 OFFSET $3`,
      [userId, limit, offset],
    );
    return rows;
  }

  async countUnread(userId: string): Promise<number> {
    const { rows } = await this.pool.query<{ count: string }>(
      'SELECT COUNT(*) as count FROM notifications WHERE user_id=$1 AND is_read=false',
      [userId],
    );
    return parseInt(rows[0]?.count ?? '0');
  }
}
