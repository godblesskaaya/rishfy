import fastify, { type FastifyInstance } from 'fastify';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { serviceMock } = vi.hoisted(() => ({
  serviceMock: {
    initiatePayment: vi.fn(),
    getPayment: vi.fn(),
    refund: vi.fn(),
    processCallback: vi.fn(),
  },
}));

vi.mock('../../src/db.js', () => ({
  pgPool: {},
}));

vi.mock('../../src/repositories/payment.repository.js', () => ({
  PaymentRepository: vi.fn().mockImplementation(() => ({})),
}));

vi.mock('../../src/services/payment.service.js', () => ({
  PaymentService: vi.fn().mockImplementation(() => serviceMock),
}));

vi.mock('../../src/logger.js', () => ({
  logger: { error: vi.fn(), warn: vi.fn(), info: vi.fn() },
}));

const { paymentRoutes } = await import('../../src/controllers/payment.routes.js');

describe('payment routes integration', () => {
  let app: FastifyInstance;

  beforeEach(async () => {
    vi.clearAllMocks();
    app = fastify();
    await app.register(paymentRoutes);
  });

  afterEach(async () => {
    await app.close();
  });

  it('initiates payment for authenticated user', async () => {
    serviceMock.initiatePayment.mockResolvedValue({
      payment: {
        id: 'payment-1',
        status: 'processing',
        internal_reference: 'internal-1',
      },
      instructions: { ussdCode: '*150*00#' },
      expiresInSeconds: 120,
    });

    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/payments/initiate',
      headers: { 'x-user-id': 'user-1' },
      payload: {
        bookingId: 'booking-1',
        amountTzs: 5000,
        method: 'mpesa_tz',
        payerPhone: '+255700000001',
        idempotencyKey: 'idem-1',
      },
    });

    expect(res.statusCode).toBe(201);
    expect(serviceMock.initiatePayment).toHaveBeenCalledTimes(1);
    expect(res.json()).toEqual({
      paymentId: 'payment-1',
      status: 'processing',
      instructions: { ussdCode: '*150*00#' },
      expiresInSeconds: 120,
      internalReference: 'internal-1',
    });
  });

  it('maps invalid webhook signature to 401', async () => {
    serviceMock.processCallback.mockRejectedValue(
      Object.assign(new Error('bad signature'), { code: 'INVALID_SIGNATURE' }),
    );

    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/webhooks/azampay',
      headers: { 'x-azampay-signature': 'bad' },
      payload: { event: 'callback' },
    });

    expect(res.statusCode).toBe(401);
    expect(res.json()).toEqual({
      processed: false,
      error: 'INVALID_SIGNATURE',
    });
  });
});
