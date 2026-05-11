import type { Pool } from 'pg';

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
      `INSERT INTO driver_profiles (user_id, license_number, license_expiry, latra_permit_number)
       VALUES ($1, $2, $3, $4)
       RETURNING *`,
      [data.user_id, data.license_number, data.license_expiry, data.latra_permit_number ?? null],
    );
    return rows[0]!;
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
}
