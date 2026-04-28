import { randomInt } from 'node:crypto';

import { AuthError } from './errors.js';
import { hashPassword, verifyPassword } from './password.service.js';
import { issueAuthTokens, verifyRefreshToken } from './token.service.js';
import type {
  LoginInput,
  RefreshTokenInput,
  RegisterInput,
  ResetPasswordInput,
  VerifyOtpInput,
} from '../controllers/auth.schemas.js';
import type { AuthRepository } from '../repositories/auth.repository.js';
import type { AuthTokens, AuthUser, SafeAuthUser } from '../types/auth.js';

const OTP_EXPIRY_MS = 10 * 60 * 1000;
const LOCKOUT_MS = 15 * 60 * 1000;

export interface AuthServiceDeps {
  repository: AuthRepository;
  otpSender?: (payload: { destination: string; code: string; purpose: string }) => Promise<void>;
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
    if (!session || session.revokedAt || session.token !== input.refreshToken || session.expiresAt.getTime() <= Date.now()) {
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
    if (session && !session.revokedAt) {
      session.revokedAt = new Date();
      await this.deps.repository.updateRefreshSession(session);
    }
    return { success: true };
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
    const provisional = issueAuthTokens({ userId: user.id, role: user.role, sessionId: 'pending' });
    const session = await this.deps.repository.createRefreshSession(
      user.id,
      provisional.refreshToken,
      new Date(Date.now() + provisional.refreshExpiresInSeconds * 1000),
    );
    const finalTokens = issueAuthTokens({ userId: user.id, role: user.role, sessionId: session.id });
    session.token = finalTokens.refreshToken;
    await this.deps.repository.updateRefreshSession(session);
    return finalTokens;
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
      id: user.id,
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
}
