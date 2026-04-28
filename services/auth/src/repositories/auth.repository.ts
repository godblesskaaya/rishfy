import { randomUUID } from 'node:crypto';

import type { AuthIdentifier, AuthUser, OtpCode, OtpPurpose, RefreshSession } from '../types/auth.js';

export interface CreateUserInput extends AuthIdentifier {
  passwordHash: string;
  fullName?: string;
}

export interface AuthRepository {
  createUser(input: CreateUserInput): Promise<AuthUser>;
  findUserByEmail(email: string): Promise<AuthUser | null>;
  findUserByPhone(phoneNumber: string): Promise<AuthUser | null>;
  findUserById(userId: string): Promise<AuthUser | null>;
  updateUser(user: AuthUser): Promise<AuthUser>;
  createOtp(userId: string, purpose: OtpPurpose, code: string, expiresAt: Date): Promise<OtpCode>;
  getActiveOtp(userId: string, purpose: OtpPurpose, code: string): Promise<OtpCode | null>;
  consumeOtp(otpId: string): Promise<void>;
  createRefreshSession(userId: string, token: string, expiresAt: Date): Promise<RefreshSession>;
  findRefreshSession(sessionId: string): Promise<RefreshSession | null>;
  updateRefreshSession(session: RefreshSession): Promise<RefreshSession>;
}

export class InMemoryAuthRepository implements AuthRepository {
  private readonly users = new Map<string, AuthUser>();
  private readonly emailIndex = new Map<string, string>();
  private readonly phoneIndex = new Map<string, string>();
  private readonly otps = new Map<string, OtpCode>();
  private readonly sessions = new Map<string, RefreshSession>();

  async createUser(input: CreateUserInput): Promise<AuthUser> {
    const now = new Date();
    const user: AuthUser = {
      id: randomUUID(),
      email: input.email?.toLowerCase(),
      phoneNumber: input.phoneNumber,
      passwordHash: input.passwordHash,
      fullName: input.fullName,
      role: 'passenger',
      isVerified: false,
      failedLoginAttempts: 0,
      createdAt: now,
      updatedAt: now,
    };

    this.users.set(user.id, user);
    if (user.email) this.emailIndex.set(user.email, user.id);
    if (user.phoneNumber) this.phoneIndex.set(user.phoneNumber, user.id);
    return structuredClone(user);
  }

  async findUserByEmail(email: string): Promise<AuthUser | null> {
    const id = this.emailIndex.get(email.toLowerCase());
    return id ? structuredClone(this.users.get(id) ?? null) : null;
  }

  async findUserByPhone(phoneNumber: string): Promise<AuthUser | null> {
    const id = this.phoneIndex.get(phoneNumber);
    return id ? structuredClone(this.users.get(id) ?? null) : null;
  }

  async findUserById(userId: string): Promise<AuthUser | null> {
    return structuredClone(this.users.get(userId) ?? null);
  }

  async updateUser(user: AuthUser): Promise<AuthUser> {
    const next = { ...user, updatedAt: new Date() };
    this.users.set(user.id, structuredClone(next));
    return structuredClone(next);
  }

  async createOtp(userId: string, purpose: OtpPurpose, code: string, expiresAt: Date): Promise<OtpCode> {
    const otp: OtpCode = {
      id: randomUUID(),
      userId,
      purpose,
      code,
      expiresAt,
      createdAt: new Date(),
    };
    this.otps.set(otp.id, otp);
    return structuredClone(otp);
  }

  async getActiveOtp(userId: string, purpose: OtpPurpose, code: string): Promise<OtpCode | null> {
    const now = Date.now();
    for (const otp of this.otps.values()) {
      if (
        otp.userId === userId &&
        otp.purpose === purpose &&
        otp.code === code &&
        !otp.consumedAt &&
        otp.expiresAt.getTime() > now
      ) {
        return structuredClone(otp);
      }
    }
    return null;
  }

  async consumeOtp(otpId: string): Promise<void> {
    const otp = this.otps.get(otpId);
    if (otp) {
      otp.consumedAt = new Date();
      this.otps.set(otpId, otp);
    }
  }

  async createRefreshSession(userId: string, token: string, expiresAt: Date): Promise<RefreshSession> {
    const session: RefreshSession = {
      id: randomUUID(),
      userId,
      token,
      expiresAt,
      createdAt: new Date(),
    };
    this.sessions.set(session.id, session);
    return structuredClone(session);
  }

  async findRefreshSession(sessionId: string): Promise<RefreshSession | null> {
    return structuredClone(this.sessions.get(sessionId) ?? null);
  }

  async updateRefreshSession(session: RefreshSession): Promise<RefreshSession> {
    this.sessions.set(session.id, structuredClone(session));
    return structuredClone(session);
  }
}
