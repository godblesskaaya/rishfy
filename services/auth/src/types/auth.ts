export type AuthIdentifier = {
  email?: string;
  phoneNumber?: string;
};

export type UserRole = 'passenger' | 'driver' | 'admin';
export type OtpPurpose = 'register' | 'reset-password';

export interface AuthUser extends AuthIdentifier {
  id: string;       // auth_db integer id (string-cast) — internal use only
  profileId: string; // UUID shared with user_db as users.id — used in JWTs
  passwordHash: string;
  fullName?: string;
  role: UserRole;
  isVerified: boolean;
  failedLoginAttempts: number;
  lockedUntil?: Date;
  createdAt: Date;
  updatedAt: Date;
}

export interface OtpCode {
  id: string;
  userId: string;
  purpose: OtpPurpose;
  code: string;
  expiresAt: Date;
  consumedAt?: Date;
  createdAt: Date;
}

export interface RefreshSession {
  id: string;
  userId: string;
  token: string;
  expiresAt: Date;
  revokedAt?: Date;
  replacedBySessionId?: string;
  createdAt: Date;
}

export interface AuthTokens {
  accessToken: string;
  refreshToken: string;
  expiresInSeconds: number;
  refreshExpiresInSeconds: number;
}

export interface SafeAuthUser extends AuthIdentifier {
  id: string;
  fullName?: string;
  role: UserRole;
  isVerified: boolean;
  createdAt: string;
  updatedAt: string;
}
