import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

describe('AzampayProvider', () => {
  beforeEach(() => {
    vi.resetModules();
    process.env['NODE_ENV'] = 'test';
    process.env['DATABASE_URL'] = 'https://example.com/db';
    process.env['REDIS_URL'] = 'https://example.com/redis';
    process.env['KAFKA_BROKERS'] = 'localhost:9092';
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('uses nested token response fields and mno checkout with api key header', async () => {
    const { AzampayProvider } = await import('../../src/providers/azampay.provider.js');
    const provider = new AzampayProvider({
      baseUrl: 'https://sandbox.azampay.co.tz',
      authUrl: 'https://authenticator-sandbox.azampay.co.tz',
      appName: 'app',
      clientId: 'client-id',
      clientSecret: 'client-secret',
      apiKey: 'api-key',
      callbackSecret: 'callback-secret',
    });

    const fetchMock = vi.fn()
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          data: {
            accessToken: 'token-123',
            expire: '2030-01-01T00:00:00Z',
          },
        }),
      })
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          transactionId: 'txn-123',
          message: 'Success',
        }),
      });

    vi.stubGlobal('fetch', fetchMock);

    const result = await provider.initiatePayment({
      bookingId: 'booking-1',
      userId: 'user-1',
      amountTzs: 5000,
      method: 'mpesa_tz',
      payerPhone: '+255700000002',
      idempotencyKey: 'idem-1',
      internalReference: 'RSHFY-REF-1',
    });

    expect(result.providerReference).toBe('txn-123');
    expect(fetchMock).toHaveBeenNthCalledWith(
      2,
      'https://sandbox.azampay.co.tz/azampay/mno/checkout',
      expect.objectContaining({
        headers: expect.objectContaining({
          Authorization: 'Bearer token-123',
          'X-API-Key': 'api-key',
        }),
      }),
    );
  });

  it('parses callback success from transactionStatus field', async () => {
    const { AzampayProvider } = await import('../../src/providers/azampay.provider.js');
    const provider = new AzampayProvider({
      baseUrl: 'https://sandbox.azampay.co.tz',
      authUrl: 'https://authenticator-sandbox.azampay.co.tz',
      appName: 'app',
      clientId: 'client-id',
      clientSecret: 'client-secret',
      apiKey: 'api-key',
      callbackSecret: 'callback-secret',
    });

    const result = provider.parseCallback({
      provider: 'azampay',
      signature: 'sig',
      rawBody: JSON.stringify({
        transactionStatus: 'Success',
        transactionId: 'txn-1',
        utilityref: 'RSHFY-REF-1',
        message: 'Completed',
      }),
    });

    expect(result).toEqual({
      internalReference: 'RSHFY-REF-1',
      providerReference: 'txn-1',
      status: 'completed',
      failureCode: undefined,
      failureMessage: undefined,
    });
  });

  it('accepts unsigned callbacks outside production', async () => {
    const { AzampayProvider } = await import('../../src/providers/azampay.provider.js');
    const provider = new AzampayProvider({
      baseUrl: 'https://sandbox.azampay.co.tz',
      authUrl: 'https://authenticator-sandbox.azampay.co.tz',
      appName: 'app',
      clientId: 'client-id',
      clientSecret: 'client-secret',
      apiKey: 'api-key',
      callbackSecret: 'callback-secret',
    });

    expect(provider.verifyCallback({
      provider: 'azampay',
      signature: '',
      rawBody: '{"message":"success"}',
    })).toBe(true);
  });
});
