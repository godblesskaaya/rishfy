import fastify, { type FastifyInstance } from 'fastify';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { serviceMock } = vi.hoisted(() => ({
  serviceMock: {
    listPayments: vi.fn(),
    initiatePayment: vi.fn(),
    getPayment: vi.fn(),
    listRefundsForPayment: vi.fn(),
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

  it('lists payments for admins', async () => {
    const initiatedAt = new Date('2026-06-12T09:00:00.000Z');
    serviceMock.listPayments.mockResolvedValue({
      items: [{
        id: 'payment-1',
        booking_id: 'booking-1',
        user_id: 'user-1',
        amount_tzs: 5000,
        method: 'mpesa_tz',
        status: 'completed',
        provider: 'azampay',
        provider_reference: 'TX-1',
        internal_reference: 'INT-1',
        payer_phone: '+255700000001',
        failure_code: null,
        failure_message: null,
        refunded_amount_tzs: 0,
        initiated_at: initiatedAt,
        completed_at: initiatedAt,
        failed_at: null,
        last_refund_at: null,
      }],
      page: 1,
      pageSize: 50,
      totalCount: 1,
    });

    const res = await app.inject({
      method: 'GET',
      url: '/api/v1/payments?page=1&page_size=50',
      headers: { 'x-user-id': 'admin-1', 'x-user-role': 'admin' },
    });

    expect(res.statusCode).toBe(200);
    expect(serviceMock.listPayments).toHaveBeenCalledWith({
      status: undefined,
      page: 1,
      pageSize: 50,
    });
    expect(res.json()).toMatchObject({
      items: [{
        payment_id: 'payment-1',
        booking_id: 'booking-1',
        amount: 5000,
        status: 'completed',
      }],
      pagination: {
        page: 1,
        page_size: 50,
        total_count: 1,
      },
    });
  });

  it('forbids non-admin payment listing', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/v1/payments',
      headers: { 'x-user-id': 'user-1', 'x-user-role': 'passenger' },
    });

    expect(res.statusCode).toBe(403);
  });

  it('returns payment detail with refund history for the payment owner', async () => {
    const initiatedAt = new Date('2026-06-12T09:00:00.000Z');
    const refundedAt = new Date('2026-06-12T10:00:00.000Z');
    serviceMock.getPayment.mockResolvedValue({
      id: 'payment-1',
      booking_id: 'booking-1',
      user_id: 'user-1',
      amount_tzs: 5000,
      method: 'mpesa_tz',
      status: 'partially_refunded',
      provider: 'azampay',
      provider_reference: 'TX-1',
      internal_reference: 'INT-1',
      payer_phone: '+255700000001',
      failure_code: null,
      failure_message: null,
      refunded_amount_tzs: 2500,
      initiated_at: initiatedAt,
      completed_at: initiatedAt,
      failed_at: null,
      last_refund_at: refundedAt,
    });
    serviceMock.listRefundsForPayment.mockResolvedValue([
      {
        id: 'refund-1',
        payment_id: 'payment-1',
        booking_id: 'booking-1',
        user_id: 'user-1',
        amount_tzs: 2500,
        status: 'completed',
        reason: 'PASSENGER_CANCELLED',
        policy: 'PENALTY_50',
        provider_reference: 'RF-1',
        failure_reason: null,
        requested_by: 'user-1',
        requested_at: refundedAt,
        completed_at: refundedAt,
        failed_at: null,
      },
    ]);

    const res = await app.inject({
      method: 'GET',
      url: '/api/v1/payments/payment-1',
      headers: { 'x-user-id': 'user-1', 'x-user-role': 'passenger' },
    });

    expect(res.statusCode).toBe(200);
    expect(serviceMock.listRefundsForPayment).toHaveBeenCalledWith('payment-1');
    expect(res.json()).toMatchObject({
      payment_id: 'payment-1',
      refunded_amount_tzs: 2500,
      refunds: [
        {
          refund_id: 'refund-1',
          amount_tzs: 2500,
          status: 'completed',
          policy: 'PENALTY_50',
          provider_reference: 'RF-1',
        },
      ],
    });
  });

  it('forbids payment detail for non-owners', async () => {
    serviceMock.getPayment.mockResolvedValue({
      id: 'payment-1',
      booking_id: 'booking-1',
      user_id: 'user-1',
      amount_tzs: 5000,
      method: 'mpesa_tz',
      status: 'completed',
      provider: 'azampay',
      provider_reference: 'TX-1',
      internal_reference: 'INT-1',
      payer_phone: '+255700000001',
      failure_code: null,
      failure_message: null,
      refunded_amount_tzs: 0,
      initiated_at: new Date('2026-06-12T09:00:00.000Z'),
      completed_at: new Date('2026-06-12T09:00:00.000Z'),
      failed_at: null,
      last_refund_at: null,
    });

    const res = await app.inject({
      method: 'GET',
      url: '/api/v1/payments/payment-1/refunds',
      headers: { 'x-user-id': 'user-2', 'x-user-role': 'passenger' },
    });

    expect(res.statusCode).toBe(403);
    expect(serviceMock.listRefundsForPayment).not.toHaveBeenCalled();
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

  it('hides provider internals when initiation fails', async () => {
    serviceMock.initiatePayment.mockRejectedValue(new Error('TypeError: fetch failed'));

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

    expect(res.statusCode).toBe(502);
    expect(res.json()).toEqual({
      error: 'PAYMENT_INITIATION_FAILED',
      message: 'Payment provider is temporarily unavailable. Please try again.',
    });
  });

  it('returns manual-required refund status when provider automation cannot complete immediately', async () => {
    serviceMock.refund.mockResolvedValue({
      payment: {
        id: 'payment-1',
        status: 'completed',
      },
      refundedAmount: 0,
      policy: 'FULL_REFUND',
      refundReference: 'refund-1',
      refundStatus: 'manual_required',
    });

    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/payments/payment-1/refund',
      headers: { 'x-user-id': 'admin-1', 'x-user-role': 'admin' },
      payload: {
        reason: 'PASSENGER_CANCELLED_BEFORE_BOARDING',
        forceFullRefund: true,
      },
    });

    expect(res.statusCode).toBe(200);
    expect(serviceMock.refund).toHaveBeenCalledWith({
      paymentId: 'payment-1',
      reason: 'PASSENGER_CANCELLED_BEFORE_BOARDING',
      initiatedBy: 'admin-1',
      departuretime: undefined,
      cancelledAt: expect.any(Date),
      forceFullRefund: true,
    });
    expect(res.json()).toEqual({
      paymentId: 'payment-1',
      refundedAmountTzs: 0,
      policy: 'FULL_REFUND',
      refundReference: 'refund-1',
      refundStatus: 'manual_required',
      status: 'completed',
    });
  });
});
