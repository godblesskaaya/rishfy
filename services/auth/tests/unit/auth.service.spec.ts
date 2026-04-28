import { InMemoryAuthRepository } from '@/repositories/auth.repository.js';
import { AuthService } from '@/services/auth.service.js';

describe('AuthService', () => {
  it('registers, verifies, logs in, refreshes, and logs out a user', async () => {
    const authService = new AuthService({ repository: new InMemoryAuthRepository() });

    const registered = await authService.register({
      email: 'rider@example.com',
      phoneNumber: '+255700000001',
      password: 'Password123',
      fullName: 'Test Rider',
    });

    const verified = await authService.verifyOtp({
      userId: registered.user.id,
      otpCode: registered.otpCode,
    });

    expect(verified.user.isVerified).toBe(true);
    expect(verified.tokens.accessToken).toBeTruthy();

    const loggedIn = await authService.login({
      identifier: 'rider@example.com',
      password: 'Password123',
    });

    expect(loggedIn.tokens.refreshToken).toBeTruthy();

    const refreshed = await authService.refreshToken({
      refreshToken: loggedIn.tokens.refreshToken,
    });

    expect(refreshed.tokens.refreshToken).not.toBe(loggedIn.tokens.refreshToken);

    await expect(authService.logout({ refreshToken: refreshed.tokens.refreshToken })).resolves.toEqual({ success: true });
  });

  it('locks the account after repeated failed logins', async () => {
    const authService = new AuthService({ repository: new InMemoryAuthRepository() });
    const registered = await authService.register({
      email: 'driver@example.com',
      password: 'Password123',
    });
    await authService.verifyOtp({ userId: registered.user.id, otpCode: registered.otpCode });

    for (let attempt = 0; attempt < 5; attempt += 1) {
      await expect(authService.login({ identifier: 'driver@example.com', password: 'WrongPass123' })).rejects.toMatchObject({
        code: 'INVALID_CREDENTIALS',
      });
    }

    await expect(authService.login({ identifier: 'driver@example.com', password: 'Password123' })).rejects.toMatchObject({
      code: 'ACCOUNT_LOCKED',
    });
  });

  it('supports reset password via OTP', async () => {
    const authService = new AuthService({ repository: new InMemoryAuthRepository() });
    const registered = await authService.register({
      phoneNumber: '+255700000002',
      password: 'Password123',
    });
    await authService.verifyOtp({ userId: registered.user.id, otpCode: registered.otpCode });

    const resetRequest = await authService.resetPassword({ identifier: '+255700000002' });
    expect(resetRequest.status).toBe('otp_sent');
    expect(resetRequest.otpCode).toBeTruthy();

    await expect(
      authService.resetPassword({
        identifier: '+255700000002',
        otpCode: resetRequest.otpCode,
        newPassword: 'BetterPass123',
      }),
    ).resolves.toEqual({ status: 'password_reset' });

    await expect(authService.login({ identifier: '+255700000002', password: 'BetterPass123' })).resolves.toMatchObject({
      user: { isVerified: true },
    });
  });
});
