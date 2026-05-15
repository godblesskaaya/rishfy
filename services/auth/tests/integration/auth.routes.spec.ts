import { buildApp } from '@/app.js';
import { clearRateLimitBuckets } from '@/middleware/rate-limit.js';
import { InMemoryAuthRepository } from '@/repositories/auth.repository.js';
import { AuthService } from '@/services/auth.service.js';

describe('auth routes', () => {
  beforeEach(() => {
    clearRateLimitBuckets();
  });

  it('completes the happy path auth flow', async () => {
    const app = await buildApp();

    const registerResponse = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: {
        email: 'happy@example.com',
        phoneNumber: '+255700000003',
        password: 'Password123',
      },
    });

    expect(registerResponse.statusCode).toBe(201);
    const registered = registerResponse.json();

    const verifyResponse = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/verify-otp',
      payload: {
        userId: registered.user.id,
        otpCode: registered.otpCode,
      },
    });

    expect(verifyResponse.statusCode).toBe(200);
    expect(verifyResponse.json().tokens.refreshToken).toBeTruthy();

    const loginResponse = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      payload: {
        identifier: 'happy@example.com',
        password: 'Password123',
      },
    });

    expect(loginResponse.statusCode).toBe(200);

    const refreshResponse = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/refresh-token',
      payload: {
        refreshToken: loginResponse.json().tokens.refreshToken,
      },
    });

    expect(refreshResponse.statusCode).toBe(200);

    const logoutResponse = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/logout',
      payload: {
        refreshToken: refreshResponse.json().tokens.refreshToken,
      },
    });

    expect(logoutResponse.statusCode).toBe(200);
    await app.close();
  });

  it('verifies access tokens at the internal endpoint', async () => {
    const app = await buildApp();
    const register = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { phoneNumber: '+255700000010', password: 'Password123' },
    });
    const registered = register.json();
    const verify = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/verify-otp',
      payload: { userId: registered.user.id, otpCode: registered.otpCode },
    });
    const accessToken = verify.json().tokens.accessToken as string;

    const ok = await app.inject({
      method: 'GET',
      url: '/internal/verify-token',
      headers: { authorization: `Bearer ${accessToken}` },
    });
    expect(ok.statusCode).toBe(200);
    expect(ok.headers['x-user-id']).toBe(registered.user.id);

    const missing = await app.inject({ method: 'GET', url: '/internal/verify-token' });
    expect(missing.statusCode).toBe(401);

    const bad = await app.inject({
      method: 'GET',
      url: '/internal/verify-token',
      headers: { authorization: 'Bearer not-a-real-jwt' },
    });
    expect(bad.statusCode).toBe(401);
    await app.close();
  });

  it('validates register input and enforces the register rate limit', async () => {
    const app = await buildApp();

    const invalid = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { password: 'short' },
    });

    expect(invalid.statusCode).toBe(400);
    clearRateLimitBuckets();

    const payload = { phoneNumber: '+255700000004', password: 'Password123' };
    expect((await app.inject({ method: 'POST', url: '/api/v1/auth/register', payload })).statusCode).toBe(201);
    expect((await app.inject({ method: 'POST', url: '/api/v1/auth/register', payload: { ...payload, phoneNumber: '+255700000005' } })).statusCode).toBe(201);

    const limited = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { ...payload, phoneNumber: '+255700000006' },
    });

    expect(limited.statusCode).toBe(429);
    await app.close();
  });

  it('emits user.registered once on register route', async () => {
    const userRegisteredPublisher = vi.fn().mockResolvedValue(undefined);
    const app = await buildApp({
      authService: new AuthService({
        repository: new InMemoryAuthRepository(),
        userRegisteredPublisher,
      }),
    });

    const registerResponse = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: {
        phoneNumber: '+255700000210',
        password: 'Password123',
        fullName: 'Integration Event',
      },
    });

    expect(registerResponse.statusCode).toBe(201);
    const registered = registerResponse.json();
    expect(userRegisteredPublisher).toHaveBeenCalledTimes(1);
    expect(userRegisteredPublisher).toHaveBeenCalledWith({
      user_id: registered.user.id,
      profile_id: registered.user.id,
      phone_number: '+255700000210',
      full_name: 'Integration Event',
      role: 'passenger',
      created_at: registered.user.createdAt,
    });
    await app.close();
  });

  it('keeps register route successful when event publish fails', async () => {
    const userRegisteredPublisher = vi.fn().mockRejectedValue(new Error('event bus unavailable'));
    const app = await buildApp({
      authService: new AuthService({
        repository: new InMemoryAuthRepository(),
        userRegisteredPublisher,
      }),
    });

    const registerResponse = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: {
        phoneNumber: '+255700000211',
        password: 'Password123',
      },
    });

    expect(registerResponse.statusCode).toBe(201);
    expect(userRegisteredPublisher).toHaveBeenCalledTimes(1);
    await app.close();
  });
});
