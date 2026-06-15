import { beforeEach, describe, expect, it, vi } from 'vitest';
import { LedgerPostingService, LedgerValidationError } from '../../src/services/ledger.service.js';

const postedJournal = {
  id: 'journal-1',
  journal_type: 'payment_captured',
  status: 'posted',
  source_type: 'payment',
  source_id: 'payment-1',
  booking_id: 'booking-1',
  payment_id: 'payment-1',
  settlement_id: null,
  idempotency_key: 'payment:payment-1:captured',
  currency: 'TZS',
  metadata: {},
  created_by: null,
  correlation_id: null,
  created_at: new Date(),
} as const;

function makeRepo() {
  return {
    getOrCreateAccount: vi.fn(async (input) => ({
      id: `${input.ownerType}-${input.accountType}`,
      owner_type: input.ownerType,
      owner_id: input.ownerId ?? null,
      account_type: input.accountType,
      currency: input.currency ?? 'TZS',
      name: input.name,
      metadata: input.metadata ?? {},
      created_at: new Date(),
      updated_at: new Date(),
    })),
    postJournal: vi.fn().mockResolvedValue(postedJournal),
  };
}

describe('LedgerPostingService', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('posts a balanced journal', async () => {
    const repo = makeRepo();
    const service = new LedgerPostingService(repo);

    await service.postJournal({
      journalType: 'payment_captured',
      sourceType: 'payment',
      sourceId: 'payment-1',
      paymentId: 'payment-1',
      bookingId: 'booking-1',
      idempotencyKey: 'payment:payment-1:captured',
      entries: [
        { accountId: 'provider-clearing', direction: 'debit', amountTzs: 10000 },
        { accountId: 'passenger-funds', direction: 'credit', amountTzs: 10000 },
      ],
    });

    expect(repo.postJournal).toHaveBeenCalledWith(expect.objectContaining({
      currency: 'TZS',
      idempotencyKey: 'payment:payment-1:captured',
    }));
  });

  it('rejects unbalanced journals before repository writes', async () => {
    const repo = makeRepo();
    const service = new LedgerPostingService(repo);

    await expect(service.postJournal({
      journalType: 'payment_captured',
      sourceType: 'payment',
      sourceId: 'payment-1',
      idempotencyKey: 'payment:payment-1:captured',
      entries: [
        { accountId: 'provider-clearing', direction: 'debit', amountTzs: 10000 },
        { accountId: 'passenger-funds', direction: 'credit', amountTzs: 9000 },
      ],
    })).rejects.toThrow(LedgerValidationError);

    expect(repo.postJournal).not.toHaveBeenCalled();
  });

  it('rejects zero, negative, and non-integer amounts', async () => {
    const repo = makeRepo();
    const service = new LedgerPostingService(repo);

    await expect(service.postJournal({
      journalType: 'adjustment',
      sourceType: 'admin_adjustment',
      sourceId: 'adjustment-1',
      idempotencyKey: 'adjustment:1',
      entries: [
        { accountId: 'a', direction: 'debit', amountTzs: 0 },
        { accountId: 'b', direction: 'credit', amountTzs: 0 },
      ],
    })).rejects.toThrow('positive integer');

    await expect(service.postJournal({
      journalType: 'adjustment',
      sourceType: 'admin_adjustment',
      sourceId: 'adjustment-2',
      idempotencyKey: 'adjustment:2',
      entries: [
        { accountId: 'a', direction: 'debit', amountTzs: 10.5 },
        { accountId: 'b', direction: 'credit', amountTzs: 10.5 },
      ],
    })).rejects.toThrow('positive integer');
  });

  it('builds payment captured entries with provider clearing debit and passenger funds credit', async () => {
    const repo = makeRepo();
    const service = new LedgerPostingService(repo);

    await service.recordPaymentCaptured({
      paymentId: 'payment-1',
      bookingId: 'booking-1',
      amountTzs: 10000,
      providerClearingAccountId: 'provider-clearing',
      passengerFundsAccountId: 'passenger-funds',
      idempotencyKey: 'payment:payment-1:captured',
      sourceId: 'payment-1',
    });

    expect(repo.postJournal).toHaveBeenCalledWith(expect.objectContaining({
      journalType: 'payment_captured',
      sourceType: 'payment',
      sourceId: 'payment-1',
      entries: [
        { accountId: 'provider-clearing', direction: 'debit', amountTzs: 10000 },
        { accountId: 'passenger-funds', direction: 'credit', amountTzs: 10000 },
      ],
    }));
  });

  it('builds driver payable accrual entries using passenger funds, platform revenue, and driver payable', async () => {
    const repo = makeRepo();
    const service = new LedgerPostingService(repo);

    await service.accrueDriverPayable({
      paymentId: 'payment-1',
      bookingId: 'booking-1',
      driverUserId: 'driver-1',
      totalAmountTzs: 10000,
      platformFeeTzs: 1500,
      driverEarningsTzs: 8500,
      passengerFundsAccountId: 'passenger-funds',
      platformRevenueAccountId: 'platform-revenue',
      driverPayableAccountId: 'driver-payable',
      idempotencyKey: 'booking:booking-1:driver-payable',
    });

    expect(repo.postJournal).toHaveBeenCalledWith(expect.objectContaining({
      journalType: 'driver_payable_accrued',
      sourceType: 'booking',
      sourceId: 'booking-1',
      entries: [
        { accountId: 'passenger-funds', direction: 'debit', amountTzs: 10000 },
        { accountId: 'platform-revenue', direction: 'credit', amountTzs: 1500 },
        { accountId: 'driver-payable', direction: 'credit', amountTzs: 8500 },
      ],
    }));
  });

  it('rejects driver payable accruals when fee plus earnings does not equal total', async () => {
    const repo = makeRepo();
    const service = new LedgerPostingService(repo);

    await expect(service.accrueDriverPayable({
      paymentId: 'payment-1',
      bookingId: 'booking-1',
      driverUserId: 'driver-1',
      totalAmountTzs: 10000,
      platformFeeTzs: 1500,
      driverEarningsTzs: 8000,
      passengerFundsAccountId: 'passenger-funds',
      platformRevenueAccountId: 'platform-revenue',
      driverPayableAccountId: 'driver-payable',
      idempotencyKey: 'booking:booking-1:driver-payable',
    })).rejects.toThrow('unbalanced');
  });

  it('builds refund completed entries by reducing passenger funds and provider clearing', async () => {
    const repo = makeRepo();
    const service = new LedgerPostingService(repo);

    await service.recordRefundCompletedForPayment({
      refundId: 'refund-1',
      paymentId: 'payment-1',
      bookingId: 'booking-1',
      passengerUserId: 'user-1',
      provider: 'azampay',
      amountTzs: 10000,
      providerReference: 'RF-1',
      idempotencyKey: 'refund:refund-1:completed',
    });

    expect(repo.postJournal).toHaveBeenCalledWith(expect.objectContaining({
      journalType: 'refund_completed',
      sourceType: 'refund',
      sourceId: 'refund-1',
      paymentId: 'payment-1',
      bookingId: 'booking-1',
      entries: [
        { accountId: 'passenger-passenger_funds', direction: 'debit', amountTzs: 10000 },
        { accountId: 'provider-provider_clearing', direction: 'credit', amountTzs: 10000 },
      ],
    }));
  });
});
