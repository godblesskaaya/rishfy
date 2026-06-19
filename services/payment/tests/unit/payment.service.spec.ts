import { beforeEach, describe, expect, it, vi } from 'vitest';

const providerMock = {
  name: 'azampay',
  initiatePayment: vi.fn(),
  verifyCallback: vi.fn(),
  parseCallback: vi.fn(),
  refund: vi.fn(),
};

vi.mock('../../src/providers/provider.factory.js', () => ({
  createPaymentProvider: vi.fn(() => providerMock),
}));

vi.mock('../../src/config.js', () => ({
  config: {
    NODE_ENV: 'test',
    SERVICE_NAME: 'payment-service',
    HTTP_PORT: 8085,
    GRPC_PORT: 50055,
    LOG_LEVEL: 'silent',
    DATABASE_URL: 'postgresql://test:test@localhost/test',
    REDIS_URL: 'redis://localhost:6379',
    KAFKA_BROKERS: 'localhost:9092',
    PAYMENT_PROVIDER: 'azampay',
    AZAMPAY_BASE_URL: 'https://sandbox.azampay.co.tz',
    AZAMPAY_AUTH_URL: 'https://authenticator-sandbox.azampay.co.tz',
    AZAMPAY_APP_NAME: '',
    AZAMPAY_CLIENT_ID: '',
    AZAMPAY_CLIENT_SECRET: '',
    AZAMPAY_CALLBACK_SECRET: 'secret',
  },
  isProduction: false, isDevelopment: false, isTest: true,
}));

vi.mock('../../src/events/payment.events.js', () => ({
  buildPaymentInitiatedEvent: vi.fn((data) => ({
    eventKey: `payment:${data.paymentId}:initiated`,
    topic: 'payment.initiated',
    messageKey: data.paymentId,
    payload: data,
  })),
  buildPaymentCompletedEvent: vi.fn((data) => ({
    eventKey: `payment:${data.paymentId}:completed`,
    topic: 'payment.completed',
    messageKey: data.paymentId,
    payload: data,
  })),
  buildPaymentFailedEvent: vi.fn((data) => ({
    eventKey: `payment:${data.paymentId}:failed`,
    topic: 'payment.failed',
    messageKey: data.paymentId,
    payload: data,
  })),
  buildPaymentRefundedEvent: vi.fn((data) => ({
    eventKey: `payment:${data.paymentId}:refunded:${data.refundedAmountTzs}`,
    topic: 'payment.refunded',
    messageKey: data.paymentId,
    payload: data,
  })),
}));

const { PaymentService } = await import('../../src/services/payment.service.js');

function makeRepo() {
  return {
    create: vi.fn(),
    findById: vi.fn(),
    findByInternalRef: vi.fn(),
    findByBookingId: vi.fn(),
    markCompleted: vi.fn(),
    markFailed: vi.fn(),
    markRefunded: vi.fn(),
    createRefund: vi.fn(),
    markRefundCompleted: vi.fn(),
    markRefundFailed: vi.fn(),
    markRefundManualRequired: vi.fn(),
    enqueueOutboxEvent: vi.fn().mockResolvedValue({ id: 'outbox-1' }),
    saveCallback: vi.fn().mockResolvedValue(undefined),
    setProviderReference: vi.fn().mockResolvedValue(undefined),
  } as const;
}

function makeLedger() {
  return {
    recordPaymentCapturedForPayment: vi.fn().mockResolvedValue({ id: 'journal-1' }),
    accrueDriverPayableForBooking: vi.fn().mockResolvedValue({ id: 'journal-2' }),
    recordRefundCompletedForPayment: vi.fn().mockResolvedValue({ id: 'journal-3' }),
  } as const;
}

const basePayment = {
  id: 'payment-1',
  booking_id: 'booking-1',
  user_id: 'user-1',
  idempotency_key: 'idem-1',
  amount_tzs: 10000,
  method: 'mpesa_tz',
  status: 'completed',
  provider: 'azampay',
  provider_reference: 'TX-1',
  internal_reference: 'INT-1',
  payer_phone: '+255700000001',
  failure_code: null,
  failure_message: null,
  refunded_amount_tzs: 0,
  initiated_at: new Date(),
  completed_at: new Date(),
  failed_at: null,
  last_refund_at: null,
  expires_at: new Date(),
  raw_callback_payload: {},
  metadata: {},
  created_at: new Date(),
  updated_at: new Date(),
} as const;

const baseRefund = {
  id: 'refund-1',
  payment_id: 'payment-1',
  booking_id: 'booking-1',
  user_id: 'user-1',
  amount_tzs: 10000,
  status: 'requested',
  reason: 'PASSENGER_CANCELLED',
  policy: 'FULL_REFUND',
  provider_reference: null,
  failure_reason: null,
  requested_by: 'user-1',
  requested_at: new Date(),
  completed_at: null,
  failed_at: null,
  metadata: {},
  created_at: new Date(),
  updated_at: new Date(),
} as const;

beforeEach(() => {
  vi.clearAllMocks();
  providerMock.name = 'azampay';
  providerMock.initiatePayment.mockReset();
  providerMock.verifyCallback.mockReset();
  providerMock.parseCallback.mockReset();
  providerMock.refund.mockReset();
});

describe('PaymentService.initiatePayment', () => {
  it('simulates a completed provider callback for mock payments', async () => {
    const repo = makeRepo();
    const ledger = makeLedger();
    const pendingPayment = { ...basePayment, status: 'pending', provider: 'mock', provider_reference: null };
    const completedPayment = { ...pendingPayment, status: 'completed', provider_reference: 'MOCK-1' };

    providerMock.name = 'mock';
    providerMock.initiatePayment.mockResolvedValue({
      providerReference: 'MOCK-1',
      instructions: '[MOCK] Approve payment',
      expiresInSeconds: 120,
    });
    providerMock.verifyCallback.mockReturnValue(true);
    providerMock.parseCallback.mockImplementation(({ rawBody }: { rawBody: string }) => {
      const payload = JSON.parse(rawBody) as { internalReference: string; providerReference: string };
      return {
        internalReference: payload.internalReference,
        providerReference: payload.providerReference,
        status: 'completed',
      };
    });
    repo.create.mockResolvedValue(pendingPayment);
    repo.findByInternalRef.mockResolvedValue(pendingPayment);
    repo.markCompleted.mockResolvedValue(completedPayment);
    repo.findById.mockResolvedValue(completedPayment);

    const svc = new PaymentService(repo as never, ledger as never);
    const result = await svc.initiatePayment({
      bookingId: 'booking-1',
      userId: 'user-1',
      amountTzs: 10000,
      method: 'mpesa_tz',
      payerPhone: '+255700000001',
      idempotencyKey: 'idem-1',
    });

    expect(result.payment.status).toBe('completed');
    expect(repo.markCompleted).toHaveBeenCalledWith('payment-1', 'MOCK-1');
    expect(repo.enqueueOutboxEvent).toHaveBeenCalledWith(expect.objectContaining({
      eventKey: 'payment:payment-1:initiated',
      topic: 'payment.initiated',
    }));
    expect(repo.enqueueOutboxEvent).toHaveBeenCalledWith(expect.objectContaining({
      eventKey: 'payment:payment-1:completed',
      topic: 'payment.completed',
    }));
    expect(ledger.recordPaymentCapturedForPayment).toHaveBeenCalledWith(expect.objectContaining({
      paymentId: 'payment-1',
      bookingId: 'booking-1',
      idempotencyKey: 'payment:payment-1:captured',
    }));
    expect(repo.saveCallback).toHaveBeenCalledWith(
      'payment-1',
      'mock',
      expect.stringContaining('"internalReference":"INT-1"'),
      '',
      true,
    );
  });

  it('does not mark a payment failed when post-initiation side effects fail', async () => {
    const repo = makeRepo();
    const pendingPayment = { ...basePayment, status: 'pending', provider_reference: null };

    providerMock.initiatePayment.mockResolvedValue({
      providerReference: 'TX-1',
      instructions: 'Approve payment',
      expiresInSeconds: 120,
    });
    repo.create.mockResolvedValue(pendingPayment);
    repo.enqueueOutboxEvent.mockRejectedValueOnce(new Error('outbox down'));

    const svc = new PaymentService(repo as never);
    await expect(svc.initiatePayment({
      bookingId: 'booking-1',
      userId: 'user-1',
      amountTzs: 10000,
      method: 'mpesa_tz',
      payerPhone: '+255700000001',
      idempotencyKey: 'idem-1',
    })).rejects.toThrow('outbox down');

    expect(providerMock.initiatePayment).toHaveBeenCalledTimes(1);
    expect(repo.markFailed).not.toHaveBeenCalled();
  });
});

describe('PaymentService.processCallback', () => {
  it('rejects invalid signatures and stores unverified callback', async () => {
    const repo = makeRepo();
    providerMock.verifyCallback.mockReturnValue(false);
    const ledger = makeLedger();
    const svc = new PaymentService(repo as never, ledger as never);

    await expect(svc.processCallback('azampay', '{"a":1}', 'bad-signature')).rejects.toMatchObject({ code: 'INVALID_SIGNATURE' });
    expect(repo.saveCallback).toHaveBeenCalledWith(null, 'azampay', '{"a":1}', 'bad-signature', false);
  });

  it('marks payment completed and enqueues payment.completed event', async () => {
    const repo = makeRepo();
    providerMock.verifyCallback.mockReturnValue(true);
    providerMock.parseCallback.mockReturnValue({
      internalReference: 'INT-1',
      providerReference: 'TX-2',
      status: 'completed',
    });
    repo.findByInternalRef.mockResolvedValue(basePayment);
    repo.markCompleted.mockResolvedValue({ ...basePayment, provider_reference: 'TX-2' });

    const svc = new PaymentService(repo as never);
    const result = await svc.processCallback('azampay', '{"ok":true}', 'sig');

    expect(result.newStatus).toBe('completed');
    expect(repo.markCompleted).toHaveBeenCalledWith('payment-1', 'TX-2');
    expect(repo.enqueueOutboxEvent).toHaveBeenCalledWith(expect.objectContaining({
      eventKey: 'payment:payment-1:completed',
      topic: 'payment.completed',
      messageKey: 'payment-1',
    }));
    expect(repo.saveCallback).toHaveBeenCalledWith('payment-1', 'azampay', '{"ok":true}', 'sig', true);
  });

  it('posts a payment capture ledger journal for completed callbacks', async () => {
    const repo = makeRepo();
    const ledger = makeLedger();
    providerMock.verifyCallback.mockReturnValue(true);
    providerMock.parseCallback.mockReturnValue({
      internalReference: 'INT-1',
      providerReference: 'TX-2',
      status: 'completed',
    });
    repo.findByInternalRef.mockResolvedValue(basePayment);
    repo.markCompleted.mockResolvedValue({ ...basePayment, provider_reference: 'TX-2' });

    const svc = new PaymentService(repo as never, ledger as never);
    await svc.processCallback('azampay', '{"ok":true}', 'sig');

    expect(ledger.recordPaymentCapturedForPayment).toHaveBeenCalledWith({
      paymentId: 'payment-1',
      bookingId: 'booking-1',
      userId: 'user-1',
      provider: 'azampay',
      amountTzs: 10000,
      idempotencyKey: 'payment:payment-1:captured',
      metadata: {
        providerReference: 'TX-2',
        internalReference: 'INT-1',
      },
    });
  });

  it('does not post a payment capture journal for failed callbacks', async () => {
    const repo = makeRepo();
    const ledger = makeLedger();
    providerMock.verifyCallback.mockReturnValue(true);
    providerMock.parseCallback.mockReturnValue({
      internalReference: 'INT-1',
      providerReference: 'TX-2',
      status: 'failed',
      failureCode: 'DECLINED',
      failureMessage: 'Declined',
    });
    repo.findByInternalRef.mockResolvedValue(basePayment);
    repo.markFailed.mockResolvedValue({ ...basePayment, status: 'failed', failure_code: 'DECLINED', failure_message: 'Declined' });

    const svc = new PaymentService(repo as never, ledger as never);
    await svc.processCallback('azampay', '{"ok":false}', 'sig');

    expect(ledger.recordPaymentCapturedForPayment).not.toHaveBeenCalled();
  });
});

describe('PaymentService.refund', () => {
  it('enqueues payment.refunded after refund processing', async () => {
    const repo = makeRepo();
    repo.findById.mockResolvedValue(basePayment);
    providerMock.refund.mockResolvedValue({ refundReference: 'RF-1' });
    repo.createRefund.mockResolvedValue(baseRefund);
    repo.markRefunded.mockResolvedValue({ ...basePayment, status: 'refunded', refunded_amount_tzs: 10000 });
    repo.markRefundCompleted.mockResolvedValue({ ...baseRefund, status: 'completed', provider_reference: 'RF-1' });

    const ledger = makeLedger();
    const svc = new PaymentService(repo as never, ledger as never);
    const result = await svc.refund({
      paymentId: 'payment-1',
      reason: 'PASSENGER_CANCELLED',
      initiatedBy: 'user-1',
      forceFullRefund: true,
    });

    expect(result.refundedAmount).toBe(10000);
    expect(result.refundReference).toBe('RF-1');
    expect(result.refundStatus).toBe('completed');
    expect(repo.createRefund).toHaveBeenCalledWith({
      paymentId: 'payment-1',
      bookingId: 'booking-1',
      userId: 'user-1',
      amountTzs: 10000,
      reason: 'PASSENGER_CANCELLED',
      policy: 'FULL_REFUND',
      requestedBy: 'user-1',
    });
    expect(repo.markRefundCompleted).toHaveBeenCalledWith('refund-1', 'RF-1');
    expect(ledger.recordRefundCompletedForPayment).toHaveBeenCalledWith({
      refundId: 'refund-1',
      paymentId: 'payment-1',
      bookingId: 'booking-1',
      passengerUserId: 'user-1',
      provider: 'azampay',
      amountTzs: 10000,
      providerReference: 'RF-1',
      idempotencyKey: 'refund:refund-1:completed',
      metadata: {
        reason: 'PASSENGER_CANCELLED',
        policy: 'FULL_REFUND',
      },
    });
    expect(repo.enqueueOutboxEvent).toHaveBeenCalledWith(expect.objectContaining({
      eventKey: 'payment:payment-1:refunded:10000',
      topic: 'payment.refunded',
      messageKey: 'payment-1',
    }));
  });

  it('marks provider refund failures as manual-required without marking payment refunded', async () => {
    const repo = makeRepo();
    repo.findById.mockResolvedValue(basePayment);
    repo.createRefund.mockResolvedValue(baseRefund);
    providerMock.refund.mockRejectedValue(new Error('provider unavailable'));
    repo.markRefundManualRequired.mockResolvedValue({
      ...baseRefund,
      status: 'manual_required',
      failure_reason: 'Error: provider unavailable',
    });

    const svc = new PaymentService(repo as never);
    const result = await svc.refund({
      paymentId: 'payment-1',
      reason: 'PASSENGER_CANCELLED',
      initiatedBy: 'user-1',
      forceFullRefund: true,
    });

    expect(result).toEqual({
      payment: basePayment,
      refundedAmount: 0,
      policy: 'FULL_REFUND',
      refundReference: 'refund-1',
      refundStatus: 'manual_required',
    });
    expect(repo.markRefundManualRequired).toHaveBeenCalledWith('refund-1', expect.stringContaining('provider unavailable'));
    expect(repo.markRefunded).not.toHaveBeenCalled();
    expect(repo.enqueueOutboxEvent).not.toHaveBeenCalled();
  });
});

describe('PaymentService.handleBookingCompleted', () => {
  it('accrues driver payable for completed paid bookings', async () => {
    const repo = makeRepo();
    const ledger = makeLedger();
    repo.findByBookingId.mockResolvedValue(basePayment);

    const svc = new PaymentService(repo as never, ledger as never);
    const result = await svc.handleBookingCompleted({
      bookingId: 'booking-1',
      passengerId: 'user-1',
      driverId: 'driver-1',
      totalPrice: 10000,
      driverEarnings: 8500,
    });

    expect(result).toEqual({ posted: true });
    expect(ledger.accrueDriverPayableForBooking).toHaveBeenCalledWith({
      paymentId: 'payment-1',
      bookingId: 'booking-1',
      passengerUserId: 'user-1',
      driverUserId: 'driver-1',
      totalAmountTzs: 10000,
      platformFeeTzs: 1500,
      driverEarningsTzs: 8500,
      idempotencyKey: 'booking:booking-1:driver-payable',
      metadata: {
        paymentInternalReference: 'INT-1',
      },
    });
  });

  it('skips accrual when booking has no completed payment', async () => {
    const repo = makeRepo();
    const ledger = makeLedger();
    repo.findByBookingId.mockResolvedValue({ ...basePayment, status: 'failed' });

    const svc = new PaymentService(repo as never, ledger as never);
    const result = await svc.handleBookingCompleted({
      bookingId: 'booking-1',
      passengerId: 'user-1',
      driverId: 'driver-1',
      totalPrice: 10000,
      driverEarnings: 8500,
    });

    expect(result).toEqual({ posted: false, reason: 'payment_not_completed' });
    expect(ledger.accrueDriverPayableForBooking).not.toHaveBeenCalled();
  });

  it('rejects payable accrual when booking total does not match payment amount', async () => {
    const repo = makeRepo();
    const ledger = makeLedger();
    repo.findByBookingId.mockResolvedValue(basePayment);

    const svc = new PaymentService(repo as never, ledger as never);
    await expect(svc.handleBookingCompleted({
      bookingId: 'booking-1',
      passengerId: 'user-1',
      driverId: 'driver-1',
      totalPrice: 9000,
      driverEarnings: 7650,
    })).rejects.toMatchObject({ code: 'PAYMENT_AMOUNT_MISMATCH' });

    expect(ledger.accrueDriverPayableForBooking).not.toHaveBeenCalled();
  });
});
