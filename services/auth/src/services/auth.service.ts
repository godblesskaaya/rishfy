import { createHash, randomInt } from 'node:crypto';

import { AuthError } from './errors.js';
import { hashPassword, verifyPassword } from './password.service.js';
import { issueAuthTokens, verifyRefreshToken } from './token.service.js';
import type {
  LoginInput,
  RefreshTokenInput,
  RegisterInput,
  ResendOtpInput,
  ResetPasswordInput,
  VerifyOtpInput,
} from '../controllers/auth.schemas.js';
import type { UserRegisteredEvent } from '../events/auth.events.js';
import { logger } from '../logger.js';
import type { AuthRepository } from '../repositories/auth.repository.js';
import type { AuthTokens, AuthUser, SafeAuthUser } from '../types/auth.js';

const OTP_EXPIRY_MS = 10 * 60 * 1000;
const LOCKOUT_MS = 15 * 60 * 1000;

export interface AuthServiceDeps {
  repository: AuthRepository;
  otpSender?: (payload: { destination: string; code: string; purpose: string }) => Promise<void>;
  userRegisteredPublisher?: (event: UserRegisteredEvent) => Promise<void>;
}

export class AuthService {
  constructor(private readonly deps: AuthServiceDeps) {}

  async register(input: RegisterInput): Promise<{ user: SafeAuthUser; otpCode: string; otpExpiresAt: string }> {
    await this.assertUniqueIdentity(input.email, input.phoneNumber);

    const user = await this.deps.repository.createUser({
      email: input.email,
      phoneNumber: input.phoneNumber,
      fullName: input.fullName,
      passwordHash: hashPassword(input.password),
    });

    await this.publishUserRegistered(user);

    const otpCode = this.generateOtpCode();
    const expiresAt = new Date(Date.now() + OTP_EXPIRY_MS);
    await this.deps.repository.createOtp(user.id, 'register', otpCode, expiresAt);
    await this.dispatchOtp(user, otpCode, 'register');

    return {
      user: this.toSafeUser(user),
      otpCode,
      otpExpiresAt: expiresAt.toISOString(),
    };
  }

  async verifyOtp(input: VerifyOtpInput): Promise<{ user: SafeAuthUser; tokens: AuthTokens }> {
    const user = await this.requireUser(input.userId);
    const otp = await this.deps.repository.getActiveOtp(user.id, 'register', input.otpCode);
    if (!otp) {
      throw new AuthError(400, 'INVALID_OTP', 'OTP is invalid or expired');
    }

    user.isVerified = true;
    user.failedLoginAttempts = 0;
    user.lockedUntil = undefined;
    const savedUser = await this.deps.repository.updateUser(user);
    await this.deps.repository.consumeOtp(otp.id);

    const tokens = await this.issueTokens(savedUser);
    return { user: this.toSafeUser(savedUser), tokens };
  }

  async login(input: LoginInput): Promise<{ user: SafeAuthUser; tokens: AuthTokens }> {
    const user = await this.findByIdentifier(input.identifier);
    if (!user) {
      throw new AuthError(401, 'INVALID_CREDENTIALS', 'Invalid credentials');
    }

    if (user.lockedUntil && user.lockedUntil.getTime() > Date.now()) {
      throw new AuthError(423, 'ACCOUNT_LOCKED', 'Account temporarily locked due to failed login attempts');
    }

    if (!verifyPassword(input.password, user.passwordHash)) {
      user.failedLoginAttempts += 1;
      if (user.failedLoginAttempts >= 5) {
        user.lockedUntil = new Date(Date.now() + LOCKOUT_MS);
      }
      await this.deps.repository.updateUser(user);
      throw new AuthError(401, 'INVALID_CREDENTIALS', 'Invalid credentials');
    }

    if (!user.isVerified) {
      throw new AuthError(403, 'UNVERIFIED_ACCOUNT', 'Verify OTP before logging in');
    }

    user.failedLoginAttempts = 0;
    user.lockedUntil = undefined;
    const savedUser = await this.deps.repository.updateUser(user);
    const tokens = await this.issueTokens(savedUser);
    return { user: this.toSafeUser(savedUser), tokens };
  }

  async refreshToken(input: RefreshTokenInput): Promise<{ user: SafeAuthUser; tokens: AuthTokens }> {
    const claims = verifyRefreshToken(input.refreshToken);
    const session = await this.deps.repository.findRefreshSession(claims.sid);
    if (
      !session ||
      session.revokedAt ||
      session.token !== this.hashRefreshToken(input.refreshToken) ||
      session.expiresAt.getTime() <= Date.now()
    ) {
      throw new AuthError(401, 'INVALID_REFRESH_TOKEN', 'Refresh token is invalid or expired');
    }

    session.revokedAt = new Date();
    const user = await this.requireUser(claims.sub);
    const rotated = await this.issueTokens(user);
    const rotatedClaims = verifyRefreshToken(rotated.refreshToken);
    session.replacedBySessionId = rotatedClaims.sid;
    await this.deps.repository.updateRefreshSession(session);

    return { user: this.toSafeUser(user), tokens: rotated };
  }

  async logout(input: RefreshTokenInput): Promise<{ success: true }> {
    const claims = verifyRefreshToken(input.refreshToken);
    const session = await this.deps.repository.findRefreshSession(claims.sid);
    if (session && !session.revokedAt && session.token === this.hashRefreshToken(input.refreshToken)) {
      session.revokedAt = new Date();
      await this.deps.repository.updateRefreshSession(session);
    }
    return { success: true };
  }

  async resendOtp(input: ResendOtpInput): Promise<{ status: 'otp_sent'; otpExpiresAt: string }> {
    const user = await this.requireUser(input.userId);
    if (input.purpose === 'register' && user.isVerified) {
      // Idempotent — verified accounts don't need another register-OTP.
      return { status: 'otp_sent', otpExpiresAt: new Date(Date.now() + OTP_EXPIRY_MS).toISOString() };
    }
    const otpCode = this.generateOtpCode();
    const expiresAt = new Date(Date.now() + OTP_EXPIRY_MS);
    await this.deps.repository.createOtp(user.id, input.purpose, otpCode, expiresAt);
    await this.dispatchOtp(user, otpCode, input.purpose);
    return { status: 'otp_sent', otpExpiresAt: expiresAt.toISOString() };
  }

  async resetPassword(input: ResetPasswordInput): Promise<{ status: 'otp_sent' | 'password_reset'; otpCode?: string }> {
    const user = await this.findByIdentifier(input.identifier);
    if (!user) {
      return { status: 'otp_sent' };
    }

    if (!input.otpCode || !input.newPassword) {
      const otpCode = this.generateOtpCode();
      const expiresAt = new Date(Date.now() + OTP_EXPIRY_MS);
      await this.deps.repository.createOtp(user.id, 'reset-password', otpCode, expiresAt);
      await this.dispatchOtp(user, otpCode, 'reset-password');
      return { status: 'otp_sent', otpCode };
    }

    const otp = await this.deps.repository.getActiveOtp(user.id, 'reset-password', input.otpCode);
    if (!otp) {
      throw new AuthError(400, 'INVALID_OTP', 'OTP is invalid or expired');
    }

    user.passwordHash = hashPassword(input.newPassword);
    user.failedLoginAttempts = 0;
    user.lockedUntil = undefined;
    await this.deps.repository.updateUser(user);
    await this.deps.repository.consumeOtp(otp.id);
    return { status: 'password_reset' };
  }

  private async assertUniqueIdentity(email?: string, phoneNumber?: string): Promise<void> {
    if (email && (await this.deps.repository.findUserByEmail(email))) {
      throw new AuthError(409, 'EMAIL_ALREADY_EXISTS', 'Email is already registered');
    }
    if (phoneNumber && (await this.deps.repository.findUserByPhone(phoneNumber))) {
      throw new AuthError(409, 'PHONE_ALREADY_EXISTS', 'Phone number is already registered');
    }
  }

  private async findByIdentifier(identifier: string): Promise<AuthUser | null> {
    return identifier.includes('@')
      ? this.deps.repository.findUserByEmail(identifier)
      : this.deps.repository.findUserByPhone(identifier);
  }

  private async issueTokens(user: AuthUser): Promise<AuthTokens> {
    // JWT sub = profileId (UUID) — consistent with user_db users.id
    const provisional = issueAuthTokens({ userId: user.profileId, role: user.role, sessionId: 'pending' });
    const session = await this.deps.repository.createRefreshSession(
      user.id, // auth_db integer id for the FK in refresh_tokens
      this.hashRefreshToken(provisional.refreshToken),
      new Date(Date.now() + provisional.refreshExpiresInSeconds * 1000),
    );
    const finalTokens = issueAuthTokens({ userId: user.profileId, role: user.role, sessionId: session.id });
    session.token = this.hashRefreshToken(finalTokens.refreshToken);
    await this.deps.repository.updateRefreshSession(session);
    return finalTokens;
  }

  private hashRefreshToken(token: string): string {
    return createHash('sha256').update(token).digest('hex');
  }

  private async requireUser(userId: string): Promise<AuthUser> {
    const user = await this.deps.repository.findUserById(userId);
    if (!user) {
      throw new AuthError(404, 'USER_NOT_FOUND', 'User not found');
    }
    return user;
  }

  private toSafeUser(user: AuthUser): SafeAuthUser {
    return {
      id: user.profileId, // expose UUID — clients use this as their stable user ID
      email: user.email,
      phoneNumber: user.phoneNumber,
      fullName: user.fullName,
      role: user.role,
      isVerified: user.isVerified,
      createdAt: user.createdAt.toISOString(),
      updatedAt: user.updatedAt.toISOString(),
    };
  }

  private generateOtpCode(): string {
    return `${randomInt(0, 1_000_000)}`.padStart(6, '0');
  }

  private async dispatchOtp(user: AuthUser, code: string, purpose: string): Promise<void> {
    const destination = user.phoneNumber ?? user.email;
    if (!destination) {
      throw new AuthError(400, 'MISSING_DESTINATION', 'User requires email or phone number');
    }

    await this.deps.otpSender?.({ destination, code, purpose });
  }

  private async publishUserRegistered(user: AuthUser): Promise<void> {
    if (!this.deps.userRegisteredPublisher) {
      return;
    }

    try {
      await this.deps.userRegisteredPublisher({
        user_id: user.id,
        profile_id: user.profileId,
        phone_number: user.phoneNumber ?? '',
        full_name: user.fullName ?? 'Rishfy User',
        role: user.role,
        created_at: user.createdAt.toISOString(),
      });
    } catch (err) {
      logger.error({ err, userId: user.id }, 'Failed to publish user.registered event');
    }
  }
}
