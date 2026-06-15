import { beforeEach, describe, expect, it, vi } from 'vitest';
import { ReconciliationService } from '../../src/services/reconciliation.service.js';

const payment = {
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
  expires_at: null,
  raw_callback_payload: {},
  metadata: {},
  created_at: new Date(),
  updated_at: new Date(),
} as const;

function makeRepo() {
  return {
    findPaymentByProviderReference: vi.fn(),
    createRecord: vi.fn(async (data: {
      provider: string;
      recordType: string;
      providerReference: string;
      amountTzs: number;
      providerStatus: string;
      matchStatus: string;
      matchedPaymentId?: string | null;
      mismatchReason?: string | null;
      importedBy: string;
    }) => ({
      id: 'rec-1',
      provider: data.provider,
      record_type: data.recordType,
      provider_reference: data.providerReference,
      amount_tzs: String(data.amountTzs),
      provider_status: data.providerStatus,
      occurred_at: null,
      match_status: data.matchStatus,
      matched_payment_id: data.matchedPaymentId ?? null,
      mismatch_reason: data.mismatchReason ?? null,
      raw_payload: {},
      imported_by: data.importedBy,
      imported_at: new Date(),
      created_at: new Date(),
    })),
    list: vi.fn(),
  };
}

describe('ReconciliationService', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('classifies matching provider payments as matched', async () => {
    const repo = makeRepo();
    repo.findPaymentByProviderReference.mockResolvedValue(payment);
    const service = new ReconciliationService(repo as never);

    const result = await service.importPaymentRecords([{
      provider: 'azampay',
      providerReference: 'TX-1',
      amountTzs: 10000,
      providerStatus: 'success',
    }], 'admin-1');

    expect(result.summary.matched).toBe(1);
    expect(repo.createRecord).toHaveBeenCalledWith(expect.objectContaining({
      matchStatus: 'matched',
      matchedPaymentId: 'payment-1',
    }));
  });

  it('classifies missing local payments as unmatched', async () => {
    const repo = makeRepo();
    repo.findPaymentByProviderReference.mockResolvedValue(null);
    const service = new ReconciliationService(repo as never);

    const result = await service.importPaymentRecords([{
      provider: 'azampay',
      providerReference: 'TX-missing',
      amountTzs: 10000,
      providerStatus: 'success',
    }], 'admin-1');

    expect(result.summary.unmatched).toBe(1);
  });

  it('classifies amount mismatches', async () => {
    const repo = makeRepo();
    repo.findPaymentByProviderReference.mockResolvedValue(payment);
    const service = new ReconciliationService(repo as never);

    const result = await service.importPaymentRecords([{
      provider: 'azampay',
      providerReference: 'TX-1',
      amountTzs: 9000,
      providerStatus: 'success',
    }], 'admin-1');

    expect(result.summary.amount_mismatch).toBe(1);
  });

  it('classifies provider status mismatches', async () => {
    const repo = makeRepo();
    repo.findPaymentByProviderReference.mockResolvedValue(payment);
    const service = new ReconciliationService(repo as never);

    const result = await service.importPaymentRecords([{
      provider: 'azampay',
      providerReference: 'TX-1',
      amountTzs: 10000,
      providerStatus: 'failed',
    }], 'admin-1');

    expect(result.summary.status_mismatch).toBe(1);
  });
});
