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
  publishPaymentInitiated: vi.fn(),
  publishPaymentCompleted: vi.fn(),
  publishPaymentFailed: vi.fn(),
  publishPaymentRefunded: vi.fn(),
}));

const { PaymentService } = await import('../../src/services/payment.service.js');
const {
  publishPaymentCompleted,
  publishPaymentFailed,
  publishPaymentRefunded,
} = await import('../../src/events/payment.events.js');

function makeRepo() {
  return {
    create: vi.fn(),
    findById: vi.fn(),
    findByInternalRef: vi.fn(),
    markCompleted: vi.fn(),
    markFailed: vi.fn(),
    markRefunded: vi.fn(),
    saveCallback: vi.fn().mockResolvedValue(undefined),
    setProviderReference: vi.fn().mockResolvedValue(undefined),
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

beforeEach(() => {
  vi.clearAllMocks();
  providerMock.initiatePayment.mockReset();
  providerMock.verifyCallback.mockReset();
  providerMock.parseCallback.mockReset();
  providerMock.refund.mockReset();
});

describe('PaymentService.processCallback', () => {
  it('rejects invalid signatures and stores unverified callback', async () => {
    const repo = makeRepo();
    providerMock.verifyCallback.mockReturnValue(false);
    const svc = new PaymentService(repo as never);

    await expect(svc.processCallback('azampay', '{"a":1}', 'bad-signature')).rejects.toMatchObject({ code: 'INVALID_SIGNATURE' });
    expect(repo.saveCallback).toHaveBeenCalledWith(null, 'azampay', '{"a":1}', 'bad-signature', false);
  });

  it('marks payment completed and emits payment.completed event', async () => {
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
    expect(vi.mocked(publishPaymentCompleted)).toHaveBeenCalledTimes(1);
    expect(repo.saveCallback).toHaveBeenCalledWith('payment-1', 'azampay', '{"ok":true}', 'sig', true);
  });
});

describe('PaymentService.refund', () => {
  it('emits payment.refunded after refund processing', async () => {
    const repo = makeRepo();
    repo.findById.mockResolvedValue(basePayment);
    providerMock.refund.mockResolvedValue({ refundReference: 'RF-1' });
    repo.markRefunded.mockResolvedValue({ ...basePayment, status: 'refunded', refunded_amount_tzs: 10000 });

    const svc = new PaymentService(repo as never);
    const result = await svc.refund({
      paymentId: 'payment-1',
      reason: 'PASSENGER_CANCELLED',
      initiatedBy: 'user-1',
      forceFullRefund: true,
    });

    expect(result.refundedAmount).toBe(10000);
    expect(vi.mocked(publishPaymentRefunded)).toHaveBeenCalledTimes(1);
    expect(vi.mocked(publishPaymentFailed)).not.toHaveBeenCalled();
  });
});
