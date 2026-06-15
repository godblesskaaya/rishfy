import type { Pool, PoolClient } from 'pg';

export interface UserRow {
  id: string;
  phone_number: string;
  full_name: string;
  email: string | null;
  role: 'passenger' | 'driver' | 'admin';
  status: 'active' | 'suspended' | 'pending_verification';
  profile_picture_url: string | null;
  average_rating: string;
  total_ratings: number;
  created_at: Date;
  updated_at: Date;
}

interface UserRegistrationUpsertInput {
  id: string;       // profile_id UUID — used as users.id primary key
  auth_id: string;
  phone_number: string;
  full_name: string;
  email?: string | null;
  role?: 'passenger' | 'driver' | 'admin';
  status?: 'active' | 'suspended' | 'pending_verification';
}

export interface DriverProfileRow {
  id: string;
  user_id: string;
  license_number: string;
  license_expiry: Date;
  latra_permit_number: string | null;
  is_verified: boolean;
  verified_at: Date | null;
  created_at: Date;
  updated_at: Date;
}

export interface VehicleRow {
  id: string;
  driver_profile_id: string;
  make: string;
  model: string;
  year: number;
  color: string;
  plate_number: string;
  capacity: number;
  status: 'pending' | 'approved' | 'rejected';
  is_active: boolean;
  created_at: Date;
  updated_at: Date;
}

export interface DeviceRow {
  id: string;
  user_id: string;
  fcm_token: string;
  platform: string;
  device_id: string;
  is_active: boolean;
  last_seen_at: Date;
  created_at: Date;
}

export interface RecordRatingInput {
  rateeId: string;
  raterId: string;
  bookingId: string;
  score: number;
  comment?: string | null;
}

export interface RecordRatingResult {
  applied: boolean;
  user: UserRow | null;
}

export interface RatingRow {
  id: string;
  ratee_id: string;
  rater_id: string;
  booking_id: string;
  score: number;
  comment: string | null;
  moderation_status: 'pending' | 'approved' | 'hidden';
  moderated_by: string | null;
  moderated_at: Date | null;
  hidden_reason: string | null;
  created_at: Date;
}

export interface UserBlockRow {
  id: string;
  blocker_id: string;
  blocked_id: string;
  reason: string | null;
  created_at: Date;
  deleted_at: Date | null;
}

export interface UserBlockSummaryRow extends UserBlockRow {
  blocked_full_name: string | null;
  blocked_role: UserRow['role'] | null;
  blocked_average_rating: string | null;
  blocked_total_ratings: number | null;
  blocked_profile_picture_url: string | null;
}

export interface FavoriteDriverRow {
  id: string;
  passenger_user_id: string;
  driver_user_id: string;
  created_at: Date;
  deleted_at: Date | null;
}

export interface FavoriteDriverSummaryRow extends FavoriteDriverRow {
  driver_full_name: string | null;
  driver_average_rating: string | null;
  driver_total_ratings: number | null;
  driver_profile_picture_url: string | null;
}

export interface PaymentMethodRow {
  id: string;
  user_id: string;
  label: string;
  provider: string;
  phone: string;
  is_default: boolean;
  created_at: Date;
  updated_at: Date;
  deleted_at: Date | null;
}

export interface EmergencyContactRow {
  id: string;
  user_id: string;
  name: string;
  phone: string;
  relationship: string | null;
  created_at: Date;
  updated_at: Date;
  deleted_at: Date | null;
}

export interface SupportCaseRow {
  id: string;
  user_id: string;
  booking_id: string | null;
  subject: string;
  message: string;
  category: string;
  status: 'open' | 'waiting' | 'resolved' | 'closed';
  priority: 'low' | 'normal' | 'high' | 'urgent';
  last_user_message_at: Date;
  last_support_response_at: Date | null;
  resolved_at: Date | null;
  closed_at: Date | null;
  metadata: Record<string, unknown>;
  created_at: Date;
  updated_at: Date;
}

export class UserRepository {
  constructor(private readonly pool: Pool) {}

  async findById(id: string): Promise<UserRow | null> {
    const { rows } = await this.pool.query<UserRow>(
      'SELECT * FROM users WHERE id = $1',
      [id],
    );
    return rows[0] ?? null;
  }

  async findByPhone(phone: string): Promise<UserRow | null> {
    const { rows } = await this.pool.query<UserRow>(
      'SELECT * FROM users WHERE phone_number = $1',
      [phone],
    );
    return rows[0] ?? null;
  }

  async upsertFromRegistration(data: UserRegistrationUpsertInput): Promise<UserRow> {
    const { rows } = await this.pool.query<UserRow>(
      `INSERT INTO users (id, auth_id, phone_number, full_name, email, role, status)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       ON CONFLICT (id) DO UPDATE
       SET auth_id = EXCLUDED.auth_id,
           phone_number = EXCLUDED.phone_number,
           full_name = EXCLUDED.full_name,
           email = EXCLUDED.email,
           role = CASE
                    WHEN users.role = 'driver' AND EXCLUDED.role = 'passenger' THEN users.role
                    WHEN users.role = 'admin' AND EXCLUDED.role IN ('passenger', 'driver') THEN users.role
                    ELSE EXCLUDED.role
                  END,
           status = CASE
                      WHEN users.status = 'suspended' AND EXCLUDED.status = 'active' THEN users.status
                      ELSE EXCLUDED.status
                    END,
           updated_at = now()
       RETURNING *`,
      [
        data.id,
        data.auth_id,
        data.phone_number,
        data.full_name,
        data.email ?? null,
        data.role ?? 'passenger',
        data.status ?? 'active',
      ],
    );
    return rows[0]!;
  }

  async update(
    id: string,
    data: { full_name?: string; email?: string; profile_picture_url?: string },
  ): Promise<UserRow | null> {
    const fields: string[] = [];
    const values: unknown[] = [];
    let idx = 1;
    for (const [k, v] of Object.entries(data)) {
      if (v !== undefined) {
        fields.push(`${k} = $${idx++}`);
        values.push(v);
      }
    }
    if (fields.length === 0) return this.findById(id);
    fields.push(`updated_at = now()`);
    values.push(id);
    const { rows } = await this.pool.query<UserRow>(
      `UPDATE users SET ${fields.join(', ')} WHERE id = $${idx} RETURNING *`,
      values,
    );
    return rows[0] ?? null;
  }

  async upgradeToDriver(id: string): Promise<UserRow | null> {
    const { rows } = await this.pool.query<UserRow>(
      `UPDATE users SET role = 'driver', updated_at = now() WHERE id = $1 AND role = 'passenger' RETURNING *`,
      [id],
    );
    return rows[0] ?? null;
  }

  async updateRating(id: string, newScore: number): Promise<UserRow | null> {
    const { rows } = await this.pool.query<UserRow>(
      `UPDATE users
         SET average_rating = (average_rating * total_ratings + $2) / (total_ratings + 1),
             total_ratings   = total_ratings + 1,
             updated_at      = now()
       WHERE id = $1
       RETURNING *`,
      [id, newScore],
    );
    return rows[0] ?? null;
  }

  async recordRating(input: RecordRatingInput): Promise<RecordRatingResult> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const inserted = await client.query<{ id: string }>(
        `INSERT INTO ratings (ratee_id, rater_id, booking_id, score, comment)
         VALUES ($1,$2,$3,$4,$5)
         ON CONFLICT (booking_id, ratee_id) DO NOTHING
         RETURNING id`,
        [input.rateeId, input.raterId, input.bookingId, input.score, input.comment ?? null],
      );

      if (inserted.rows.length === 0) {
        const user = await this.findByIdWithClient(client, input.rateeId);
        await client.query('COMMIT');
        return { applied: false, user };
      }

      const user = await this.updateRatingWithClient(client, input.rateeId, input.score);
      await client.query('COMMIT');
      return { applied: true, user };
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  private async findByIdWithClient(client: PoolClient, id: string): Promise<UserRow | null> {
    const { rows } = await client.query<UserRow>(
      'SELECT * FROM users WHERE id = $1',
      [id],
    );
    return rows[0] ?? null;
  }

  private async updateRatingWithClient(client: PoolClient, id: string, newScore: number): Promise<UserRow | null> {
    const { rows } = await client.query<UserRow>(
      `UPDATE users
         SET average_rating = (average_rating * total_ratings + $2) / (total_ratings + 1),
             total_ratings   = total_ratings + 1,
             updated_at      = now()
       WHERE id = $1
       RETURNING *`,
      [id, newScore],
    );
    return rows[0] ?? null;
  }

  // DriverProfile -----------------------------------------------------------

  async findDriverProfile(userId: string): Promise<DriverProfileRow | null> {
    const { rows } = await this.pool.query<DriverProfileRow>(
      `SELECT dp.* FROM driver_profiles dp WHERE dp.user_id = $1`,
      [userId],
    );
    return rows[0] ?? null;
  }

  async createDriverProfile(data: {
    user_id: string;
    license_number: string;
    license_expiry: string;
    latra_permit_number?: string;
  }): Promise<DriverProfileRow> {
    const { rows } = await this.pool.query<DriverProfileRow>(
      `INSERT INTO driver_profiles (user_id, license_number, license_expiry, latra_permit_number, is_verified, verified_at)
       VALUES ($1, $2, $3, $4, true, now())
       RETURNING *`,
      [data.user_id, data.license_number, data.license_expiry, data.latra_permit_number ?? null],
    );
    return rows[0]!;
  }

  async verifyDriverProfile(userId: string): Promise<DriverProfileRow | null> {
    const { rows } = await this.pool.query<DriverProfileRow>(
      `UPDATE driver_profiles SET is_verified = true, verified_at = now(), updated_at = now()
       WHERE user_id = $1 RETURNING *`,
      [userId],
    );
    return rows[0] ?? null;
  }

  async rejectDriverProfile(userId: string): Promise<DriverProfileRow | null> {
    const { rows } = await this.pool.query<DriverProfileRow>(
      `UPDATE driver_profiles SET is_verified = false, verified_at = null, updated_at = now()
       WHERE user_id = $1 RETURNING *`,
      [userId],
    );
    return rows[0] ?? null;
  }

  async listPendingDrivers(limit: number, offset: number): Promise<Array<DriverProfileRow & { user: UserRow }>> {
    const { rows } = await this.pool.query<DriverProfileRow & { user: UserRow }>(
      `SELECT dp.*, row_to_json(u.*) as user
       FROM driver_profiles dp
       JOIN users u ON u.id = dp.user_id
       WHERE dp.is_verified = false
       ORDER BY dp.created_at ASC
       LIMIT $1 OFFSET $2`,
      [limit, offset],
    );
    return rows;
  }

  // Vehicle -----------------------------------------------------------------

  async createVehicle(data: {
    driver_profile_id: string;
    make: string;
    model: string;
    year: number;
    color: string;
    plate_number: string;
    capacity: number;
  }): Promise<VehicleRow> {
    const { rows } = await this.pool.query<VehicleRow>(
      `INSERT INTO vehicles (driver_profile_id, make, model, year, color, plate_number, capacity)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING *`,
      [data.driver_profile_id, data.make, data.model, data.year, data.color, data.plate_number, data.capacity],
    );
    return rows[0]!;
  }

  async findVehicle(id: string): Promise<VehicleRow | null> {
    const { rows } = await this.pool.query<VehicleRow>(
      'SELECT * FROM vehicles WHERE id = $1',
      [id],
    );
    return rows[0] ?? null;
  }

  async listDriverVehicles(driverProfileId: string): Promise<VehicleRow[]> {
    const { rows } = await this.pool.query<VehicleRow>(
      'SELECT * FROM vehicles WHERE driver_profile_id = $1 ORDER BY is_active DESC, created_at DESC',
      [driverProfileId],
    );
    return rows;
  }

  async listApprovedRatingsForUser(userId: string, limit: number): Promise<RatingRow[]> {
    const { rows } = await this.pool.query<RatingRow>(
      `SELECT *
       FROM ratings
       WHERE ratee_id=$1
         AND moderation_status='approved'
       ORDER BY created_at DESC
       LIMIT $2`,
      [userId, Math.min(Math.max(limit, 1), 20)],
    );
    return rows;
  }

  async setActiveVehicle(driverProfileId: string, vehicleId: string): Promise<VehicleRow | null> {
    const { rows } = await this.pool.query<VehicleRow>(
      `UPDATE vehicles
       SET is_active = CASE WHEN id = $2 THEN true ELSE false END,
           updated_at = now()
       WHERE driver_profile_id = $1
       RETURNING *`,
      [driverProfileId, vehicleId],
    );
    return rows.find((row) => row.id === vehicleId) ?? null;
  }

  async updateVehicle(id: string, data: Partial<Omit<VehicleRow, 'id' | 'driver_profile_id' | 'created_at' | 'updated_at'>>): Promise<VehicleRow | null> {
    const fields: string[] = [];
    const values: unknown[] = [];
    let idx = 1;
    for (const [k, v] of Object.entries(data)) {
      if (v !== undefined) { fields.push(`${k} = $${idx++}`); values.push(v); }
    }
    if (fields.length === 0) return this.findVehicle(id);
    fields.push('updated_at = now()');
    values.push(id);
    const { rows } = await this.pool.query<VehicleRow>(
      `UPDATE vehicles SET ${fields.join(', ')} WHERE id = $${idx} RETURNING *`,
      values,
    );
    return rows[0] ?? null;
  }

  async deleteVehicle(id: string): Promise<boolean> {
    const { rowCount } = await this.pool.query('DELETE FROM vehicles WHERE id = $1', [id]);
    return (rowCount ?? 0) > 0;
  }

  // Device ------------------------------------------------------------------

  async upsertDevice(data: {
    user_id: string;
    fcm_token: string;
    platform: string;
    device_id: string;
  }): Promise<DeviceRow> {
    const { rows } = await this.pool.query<DeviceRow>(
      `INSERT INTO devices (user_id, fcm_token, platform, device_id)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (user_id, device_id) DO UPDATE
         SET fcm_token = EXCLUDED.fcm_token,
             is_active = true,
             last_seen_at = now()
       RETURNING *`,
      [data.user_id, data.fcm_token, data.platform, data.device_id],
    );
    return rows[0]!;
  }

  async deactivateDevice(userId: string, deviceId: string): Promise<void> {
    await this.pool.query(
      `UPDATE devices SET is_active = false WHERE user_id = $1 AND device_id = $2`,
      [userId, deviceId],
    );
  }

  // Social trust ------------------------------------------------------------

  async listRatingsForModeration(params: {
    status?: 'pending' | 'approved' | 'hidden';
    limit: number;
    offset: number;
  }): Promise<RatingRow[]> {
    const values: unknown[] = [];
    const where: string[] = [];
    if (params.status) {
      values.push(params.status);
      where.push(`moderation_status = $${values.length}`);
    }
    values.push(params.limit, params.offset);
    const whereClause = where.length > 0 ? `WHERE ${where.join(' AND ')}` : '';
    const { rows } = await this.pool.query<RatingRow>(
      `SELECT *
       FROM ratings
       ${whereClause}
       ORDER BY created_at DESC
       LIMIT $${values.length - 1} OFFSET $${values.length}`,
      values,
    );
    return rows;
  }

  async moderateRating(data: {
    ratingId: string;
    status: 'approved' | 'hidden';
    moderatedBy: string;
    hiddenReason?: string | null;
  }): Promise<RatingRow | null> {
    const { rows } = await this.pool.query<RatingRow>(
      `UPDATE ratings
       SET moderation_status=$2,
           moderated_by=$3,
           moderated_at=now(),
           hidden_reason=CASE WHEN $2='hidden' THEN $4 ELSE NULL END
       WHERE id=$1
       RETURNING *`,
      [data.ratingId, data.status, data.moderatedBy, data.hiddenReason ?? null],
    );
    return rows[0] ?? null;
  }

  async blockUser(data: { blockerId: string; blockedId: string; reason?: string | null }): Promise<UserBlockRow> {
    const { rows } = await this.pool.query<UserBlockRow>(
      `INSERT INTO user_blocks (blocker_id, blocked_id, reason)
       VALUES ($1,$2,$3)
       ON CONFLICT (blocker_id, blocked_id) WHERE deleted_at IS NULL
       DO UPDATE SET reason=EXCLUDED.reason
       RETURNING *`,
      [data.blockerId, data.blockedId, data.reason ?? null],
    );
    return rows[0]!;
  }

  async unblockUser(blockerId: string, blockedId: string): Promise<boolean> {
    const { rowCount } = await this.pool.query(
      `UPDATE user_blocks
       SET deleted_at=now()
       WHERE blocker_id=$1 AND blocked_id=$2 AND deleted_at IS NULL`,
      [blockerId, blockedId],
    );
    return (rowCount ?? 0) > 0;
  }

  async listBlockedUsers(blockerId: string): Promise<UserBlockSummaryRow[]> {
    const { rows } = await this.pool.query<UserBlockSummaryRow>(
      `SELECT ub.*,
              u.full_name AS blocked_full_name,
              u.role AS blocked_role,
              u.average_rating AS blocked_average_rating,
              u.total_ratings AS blocked_total_ratings,
              u.profile_picture_url AS blocked_profile_picture_url
       FROM user_blocks ub
       LEFT JOIN users u ON u.id = ub.blocked_id
       WHERE ub.blocker_id=$1 AND ub.deleted_at IS NULL
       ORDER BY ub.created_at DESC`,
      [blockerId],
    );
    return rows;
  }

  async addFavoriteDriver(passengerUserId: string, driverUserId: string): Promise<FavoriteDriverRow> {
    const { rows } = await this.pool.query<FavoriteDriverRow>(
      `INSERT INTO favorite_drivers (passenger_user_id, driver_user_id)
       VALUES ($1,$2)
       ON CONFLICT (passenger_user_id, driver_user_id) WHERE deleted_at IS NULL
       DO UPDATE SET deleted_at=NULL
       RETURNING *`,
      [passengerUserId, driverUserId],
    );
    return rows[0]!;
  }

  async removeFavoriteDriver(passengerUserId: string, driverUserId: string): Promise<boolean> {
    const { rowCount } = await this.pool.query(
      `UPDATE favorite_drivers
       SET deleted_at=now()
       WHERE passenger_user_id=$1 AND driver_user_id=$2 AND deleted_at IS NULL`,
      [passengerUserId, driverUserId],
    );
    return (rowCount ?? 0) > 0;
  }

  async listFavoriteDrivers(passengerUserId: string): Promise<FavoriteDriverSummaryRow[]> {
    const { rows } = await this.pool.query<FavoriteDriverSummaryRow>(
      `SELECT fd.*,
              u.full_name AS driver_full_name,
              u.average_rating AS driver_average_rating,
              u.total_ratings AS driver_total_ratings,
              u.profile_picture_url AS driver_profile_picture_url
       FROM favorite_drivers fd
       LEFT JOIN users u ON u.id = fd.driver_user_id
       WHERE fd.passenger_user_id=$1 AND fd.deleted_at IS NULL
       ORDER BY fd.created_at DESC`,
      [passengerUserId],
    );
    return rows;
  }

  async listPaymentMethods(userId: string): Promise<PaymentMethodRow[]> {
    const { rows } = await this.pool.query<PaymentMethodRow>(
      `SELECT *
       FROM user_payment_methods
       WHERE user_id=$1 AND deleted_at IS NULL
       ORDER BY is_default DESC, created_at DESC`,
      [userId],
    );
    return rows;
  }

  async addPaymentMethod(data: {
    userId: string;
    label?: string;
    provider: string;
    phone: string;
    isDefault?: boolean;
  }): Promise<PaymentMethodRow> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const makeDefault = data.isDefault ?? false;
      if (makeDefault) {
        await client.query(
          `UPDATE user_payment_methods
           SET is_default=false, updated_at=now()
           WHERE user_id=$1 AND deleted_at IS NULL`,
          [data.userId],
        );
      }
      const { rows } = await client.query<PaymentMethodRow>(
        `INSERT INTO user_payment_methods (user_id, label, provider, phone, is_default)
         VALUES ($1,$2,$3,$4,$5)
         ON CONFLICT (user_id, provider, phone) WHERE deleted_at IS NULL
         DO UPDATE SET label=EXCLUDED.label,
                       is_default=EXCLUDED.is_default,
                       updated_at=now()
         RETURNING *`,
        [data.userId, data.label ?? '', data.provider, data.phone, makeDefault],
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

  async updatePaymentMethod(
    userId: string,
    methodId: string,
    data: { label?: string; provider?: string; phone?: string; isDefault?: boolean },
  ): Promise<PaymentMethodRow | null> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      if (data.isDefault === true) {
        await client.query(
          `UPDATE user_payment_methods
           SET is_default=false, updated_at=now()
           WHERE user_id=$1 AND deleted_at IS NULL`,
          [userId],
        );
      }

      const fields: string[] = [];
      const values: unknown[] = [];
      let idx = 1;
      for (const [key, value] of Object.entries({
        label: data.label,
        provider: data.provider,
        phone: data.phone,
        is_default: data.isDefault,
      })) {
        if (value !== undefined) {
          fields.push(`${key}=$${idx++}`);
          values.push(value);
        }
      }
      if (fields.length === 0) {
        const existing = await client.query<PaymentMethodRow>(
          `SELECT * FROM user_payment_methods
           WHERE id=$1 AND user_id=$2 AND deleted_at IS NULL`,
          [methodId, userId],
        );
        await client.query('COMMIT');
        return existing.rows[0] ?? null;
      }

      fields.push('updated_at=now()');
      values.push(methodId, userId);
      const { rows } = await client.query<PaymentMethodRow>(
        `UPDATE user_payment_methods
         SET ${fields.join(', ')}
         WHERE id=$${idx} AND user_id=$${idx + 1} AND deleted_at IS NULL
         RETURNING *`,
        values,
      );
      await client.query('COMMIT');
      return rows[0] ?? null;
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  async deletePaymentMethod(userId: string, methodId: string): Promise<boolean> {
    const { rowCount } = await this.pool.query(
      `UPDATE user_payment_methods
       SET deleted_at=now(), is_default=false, updated_at=now()
       WHERE id=$1 AND user_id=$2 AND deleted_at IS NULL`,
      [methodId, userId],
    );
    return (rowCount ?? 0) > 0;
  }

  async listEmergencyContacts(userId: string): Promise<EmergencyContactRow[]> {
    const { rows } = await this.pool.query<EmergencyContactRow>(
      `SELECT *
       FROM user_emergency_contacts
       WHERE user_id=$1 AND deleted_at IS NULL
       ORDER BY created_at DESC`,
      [userId],
    );
    return rows;
  }

  async addEmergencyContact(data: {
    userId: string;
    name: string;
    phone: string;
    relationship?: string | null;
  }): Promise<EmergencyContactRow> {
    const { rows } = await this.pool.query<EmergencyContactRow>(
      `INSERT INTO user_emergency_contacts (user_id, name, phone, relationship)
       VALUES ($1,$2,$3,$4)
       RETURNING *`,
      [data.userId, data.name, data.phone, data.relationship ?? null],
    );
    return rows[0]!;
  }

  async updateEmergencyContact(
    userId: string,
    contactId: string,
    data: { name?: string; phone?: string; relationship?: string | null },
  ): Promise<EmergencyContactRow | null> {
    const fields: string[] = [];
    const values: unknown[] = [];
    let idx = 1;
    for (const [key, value] of Object.entries(data)) {
      if (value !== undefined) {
        fields.push(`${key}=$${idx++}`);
        values.push(value);
      }
    }
    if (fields.length === 0) {
      const { rows } = await this.pool.query<EmergencyContactRow>(
        `SELECT * FROM user_emergency_contacts
         WHERE id=$1 AND user_id=$2 AND deleted_at IS NULL`,
        [contactId, userId],
      );
      return rows[0] ?? null;
    }
    fields.push('updated_at=now()');
    values.push(contactId, userId);
    const { rows } = await this.pool.query<EmergencyContactRow>(
      `UPDATE user_emergency_contacts
       SET ${fields.join(', ')}
       WHERE id=$${idx} AND user_id=$${idx + 1} AND deleted_at IS NULL
       RETURNING *`,
      values,
    );
    return rows[0] ?? null;
  }

  async deleteEmergencyContact(userId: string, contactId: string): Promise<boolean> {
    const { rowCount } = await this.pool.query(
      `UPDATE user_emergency_contacts
       SET deleted_at=now(), updated_at=now()
       WHERE id=$1 AND user_id=$2 AND deleted_at IS NULL`,
      [contactId, userId],
    );
    return (rowCount ?? 0) > 0;
  }

  async listSupportCases(userId: string): Promise<SupportCaseRow[]> {
    const { rows } = await this.pool.query<SupportCaseRow>(
      `SELECT *
       FROM user_support_cases
       WHERE user_id=$1
       ORDER BY
         CASE status
           WHEN 'open' THEN 0
           WHEN 'waiting' THEN 1
           WHEN 'resolved' THEN 2
           ELSE 3
         END,
         created_at DESC`,
      [userId],
    );
    return rows;
  }

  async createSupportCase(data: {
    userId: string;
    subject: string;
    message: string;
    category: string;
    priority: SupportCaseRow['priority'];
    bookingId?: string | null;
  }): Promise<SupportCaseRow> {
    const { rows } = await this.pool.query<SupportCaseRow>(
      `INSERT INTO user_support_cases
         (user_id, booking_id, subject, message, category, priority)
       VALUES ($1,$2,$3,$4,$5,$6)
       RETURNING *`,
      [
        data.userId,
        data.bookingId ?? null,
        data.subject,
        data.message,
        data.category,
        data.priority,
      ],
    );
    return rows[0]!;
  }

  async listSupportCasesForStaff(params: {
    status?: SupportCaseRow['status'];
    priority?: SupportCaseRow['priority'];
    limit: number;
    offset: number;
  }): Promise<SupportCaseRow[]> {
    const values: unknown[] = [];
    const where: string[] = [];
    if (params.status) {
      values.push(params.status);
      where.push(`status=$${values.length}`);
    }
    if (params.priority) {
      values.push(params.priority);
      where.push(`priority=$${values.length}`);
    }
    const whereClause = where.length > 0 ? `WHERE ${where.join(' AND ')}` : '';
    const { rows } = await this.pool.query<SupportCaseRow>(
      `SELECT *
       FROM user_support_cases
       ${whereClause}
       ORDER BY
         CASE priority
           WHEN 'urgent' THEN 0
           WHEN 'high' THEN 1
           WHEN 'normal' THEN 2
           ELSE 3
         END,
         created_at DESC
       LIMIT $${values.length + 1} OFFSET $${values.length + 2}`,
      [...values, params.limit, params.offset],
    );
    return rows;
  }

  async updateSupportCaseForStaff(data: {
    caseId: string;
    status?: SupportCaseRow['status'];
    priority?: SupportCaseRow['priority'];
    supportResponded?: boolean;
  }): Promise<SupportCaseRow | null> {
    const fields: string[] = [];
    const values: unknown[] = [];
    let idx = 1;
    if (data.status !== undefined) {
      fields.push(`status=$${idx++}`);
      values.push(data.status);
      if (data.status === 'resolved') fields.push('resolved_at=COALESCE(resolved_at, now())');
      if (data.status === 'closed') fields.push('closed_at=COALESCE(closed_at, now())');
    }
    if (data.priority !== undefined) {
      fields.push(`priority=$${idx++}`);
      values.push(data.priority);
    }
    if (data.supportResponded) {
      fields.push('last_support_response_at=now()');
      if (data.status === undefined) fields.push("status='waiting'");
    }
    if (fields.length === 0) {
      const { rows } = await this.pool.query<SupportCaseRow>(
        'SELECT * FROM user_support_cases WHERE id=$1',
        [data.caseId],
      );
      return rows[0] ?? null;
    }
    fields.push('updated_at=now()');
    values.push(data.caseId);
    const { rows } = await this.pool.query<SupportCaseRow>(
      `UPDATE user_support_cases
       SET ${fields.join(', ')}
       WHERE id=$${idx}
       RETURNING *`,
      values,
    );
    return rows[0] ?? null;
  }
}
