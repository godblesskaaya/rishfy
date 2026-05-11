import type { AuthRepository, CreateUserInput } from './auth.repository.js';
import type { AuthUser, OtpCode, OtpPurpose, RefreshSession } from '../types/auth.js';
import { db } from '../db.js';

// ---------------------------------------------------------------------------
// Row → domain mappers
// ---------------------------------------------------------------------------

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function rowToUser(row: Record<string, any>): AuthUser {
  const dbRole: string = row.user_type ?? 'passenger';
  return {
    id: String(row.id),
    profileId: String(row.profile_id),
    email: row.email ?? undefined,
    phoneNumber: row.phone ?? undefined,
    passwordHash: row.password_hash,
    fullName: undefined, // auth_users has no full_name column
    role: dbRole === 'rider' ? 'passenger' : (dbRole as AuthUser['role']),
    isVerified: Boolean(row.verified),
    failedLoginAttempts: Number(row.failed_login_count ?? 0),
    lockedUntil: row.locked_until ? new Date(row.locked_until) : undefined,
    createdAt: new Date(row.created_at),
    updatedAt: new Date(row.updated_at),
  };
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function rowToOtp(row: Record<string, any>): OtpCode {
  const typeMap: Record<string, OtpPurpose> = {
    registration: 'register',
    password_reset: 'reset-password',
  };
  return {
    id: String(row.id),
    userId: String(row.user_id),
    purpose: (typeMap[row.type] ?? row.type) as OtpPurpose,
    code: row.code,
    expiresAt: new Date(row.expires_at),
    consumedAt: row.used_at ? new Date(row.used_at) : undefined,
    createdAt: new Date(row.created_at),
  };
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function rowToSession(row: Record<string, any>): RefreshSession {
  return {
    id: String(row.id),
    userId: String(row.user_id),
    token: row.token_hash, // stored directly (no hash for JWTs)
    expiresAt: new Date(row.expires_at),
    revokedAt: row.revoked_at ? new Date(row.revoked_at) : undefined,
    replacedBySessionId: undefined,
    createdAt: new Date(row.created_at),
  };
}

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

export class PgAuthRepository implements AuthRepository {
  async createUser(input: CreateUserInput): Promise<AuthUser> {
    const dbRole = (input as { role?: string }).role === 'passenger' ? 'rider' : ((input as { role?: string }).role ?? 'rider');
    const row = await db
      .insertInto('auth_users')
      .values({
        phone: input.phoneNumber ?? null,
        email: input.email?.toLowerCase() ?? null,
        password_hash: input.passwordHash,
        user_type: dbRole,
        verified: false,
        status: 'active',
      })
      .returningAll()
      .executeTakeFirstOrThrow();
    return rowToUser(row);
  }

  async findUserByEmail(email: string): Promise<AuthUser | null> {
    const row = await db
      .selectFrom('auth_users')
      .selectAll()
      .where('email', '=', email.toLowerCase())
      .executeTakeFirst();
    return row ? rowToUser(row) : null;
  }

  async findUserByPhone(phoneNumber: string): Promise<AuthUser | null> {
    const row = await db
      .selectFrom('auth_users')
      .selectAll()
      .where('phone', '=', phoneNumber)
      .executeTakeFirst();
    return row ? rowToUser(row) : null;
  }

  async findUserById(profileId: string): Promise<AuthUser | null> {
    // profileId is the UUID used as JWT sub — look up via profile_id column
    const row = await db
      .selectFrom('auth_users')
      .selectAll()
      .where('profile_id', '=', profileId)
      .executeTakeFirst();
    return row ? rowToUser(row) : null;
  }

  async updateUser(user: AuthUser): Promise<AuthUser> {
    const dbRole = user.role === 'passenger' ? 'rider' : user.role;
    const row = await db
      .updateTable('auth_users')
      .set({
        user_type: dbRole,
        verified: user.isVerified,
        failed_login_count: user.failedLoginAttempts,
        locked_until: user.lockedUntil ?? null,
        updated_at: new Date(),
      })
      .where('id', '=', parseInt(user.id, 10))
      .returningAll()
      .executeTakeFirstOrThrow();
    return rowToUser(row);
  }

  async createOtp(userId: string, purpose: OtpPurpose, code: string, expiresAt: Date): Promise<OtpCode> {
    const typeMap: Record<OtpPurpose, string> = {
      register: 'registration',
      'reset-password': 'password_reset',
    };
    const row = await db
      .insertInto('verification_codes')
      .values({
        user_id: parseInt(userId, 10),
        code,
        type: typeMap[purpose] ?? purpose,
        expires_at: expiresAt,
        used: false,
      })
      .returningAll()
      .executeTakeFirstOrThrow();
    return rowToOtp(row);
  }

  async getActiveOtp(userId: string, purpose: OtpPurpose, code: string): Promise<OtpCode | null> {
    const typeMap: Record<OtpPurpose, string> = {
      register: 'registration',
      'reset-password': 'password_reset',
    };
    const row = await db
      .selectFrom('verification_codes')
      .selectAll()
      .where('user_id', '=', parseInt(userId, 10))
      .where('type', '=', typeMap[purpose] ?? purpose)
      .where('code', '=', code)
      .where('used', '=', false)
      .where('expires_at', '>', new Date())
      .executeTakeFirst();
    return row ? rowToOtp(row) : null;
  }

  async consumeOtp(otpId: string): Promise<void> {
    await db
      .updateTable('verification_codes')
      .set({ used: true, used_at: new Date() })
      .where('id', '=', parseInt(otpId, 10))
      .execute();
  }

  async createRefreshSession(userId: string, token: string, expiresAt: Date): Promise<RefreshSession> {
    const row = await db
      .insertInto('refresh_tokens')
      .values({
        user_id: parseInt(userId, 10),
        token_hash: token,
        expires_at: expiresAt,
        revoked: false,
      })
      .returningAll()
      .executeTakeFirstOrThrow();
    return rowToSession(row);
  }

  async findRefreshSession(sessionId: string): Promise<RefreshSession | null> {
    const row = await db
      .selectFrom('refresh_tokens')
      .selectAll()
      .where('id', '=', parseInt(sessionId, 10))
      .executeTakeFirst();
    return row ? rowToSession(row) : null;
  }

  async updateRefreshSession(session: RefreshSession): Promise<RefreshSession> {
    const row = await db
      .updateTable('refresh_tokens')
      .set({
        token_hash: session.token,
        revoked: session.revokedAt != null,
        revoked_at: session.revokedAt ?? null,
      })
      .where('id', '=', parseInt(session.id, 10))
      .returningAll()
      .executeTakeFirstOrThrow();
    return rowToSession(row);
  }
}
