import type { Pool } from 'pg';

export interface DeviceTokenRow {
  id: string;
  user_id: string;
  device_id: string;
  fcm_token: string;
  platform: 'ios' | 'android';
  app_version: string | null;
  is_active: boolean;
  last_used_at: Date;
  created_at: Date;
  updated_at: Date;
}

export class DeviceTokenRepository {
  constructor(private readonly pool: Pool) {}

  async upsert(data: {
    userId: string;
    deviceId: string;
    fcmToken: string;
    platform: 'ios' | 'android';
    appVersion?: string;
  }): Promise<DeviceTokenRow> {
    const { rows } = await this.pool.query<DeviceTokenRow>(
      `INSERT INTO device_tokens (user_id, device_id, fcm_token, platform, app_version, is_active, last_used_at)
       VALUES ($1, $2, $3, $4, $5, true, now())
       ON CONFLICT (user_id, device_id) DO UPDATE SET
         fcm_token = EXCLUDED.fcm_token,
         platform = EXCLUDED.platform,
         app_version = COALESCE(EXCLUDED.app_version, device_tokens.app_version),
         is_active = true,
         last_used_at = now(),
         updated_at = now()
       RETURNING *`,
      [data.userId, data.deviceId, data.fcmToken, data.platform, data.appVersion ?? null],
    );
    return rows[0]!;
  }

  async deactivate(userId: string, deviceId: string): Promise<void> {
    await this.pool.query(
      'UPDATE device_tokens SET is_active=false, updated_at=now() WHERE user_id=$1 AND device_id=$2',
      [userId, deviceId],
    );
  }

  async deactivateByToken(fcmToken: string): Promise<void> {
    await this.pool.query(
      'UPDATE device_tokens SET is_active=false, updated_at=now() WHERE fcm_token=$1',
      [fcmToken],
    );
  }

  async deactivateAllForUser(userId: string): Promise<void> {
    await this.pool.query(
      'UPDATE device_tokens SET is_active=false, updated_at=now() WHERE user_id=$1',
      [userId],
    );
  }

  async getActiveTokensForUser(userId: string): Promise<DeviceTokenRow[]> {
    const { rows } = await this.pool.query<DeviceTokenRow>(
      'SELECT * FROM device_tokens WHERE user_id=$1 AND is_active=true ORDER BY last_used_at DESC',
      [userId],
    );
    return rows;
  }

  async refreshToken(userId: string, deviceId: string, newToken: string): Promise<void> {
    await this.pool.query(
      'UPDATE device_tokens SET fcm_token=$3, last_used_at=now(), updated_at=now() WHERE user_id=$1 AND device_id=$2',
      [userId, deviceId, newToken],
    );
  }
}
