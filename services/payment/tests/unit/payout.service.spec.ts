import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PayoutService } from '../../src/services/payout.service.js';

const payout = {
  id: 'payout-1',
  driver_user_id: 'driver-1',
  amount_tzs: '8500',
  currency: 'TZS',
  status: 'pending_review',
  payout_method: 'mpesa_tz',
  payout_phone: '+255700000001',
  requested_by: 'driver-1',
  reviewed_by: null,
  provider_reference: null,
  failure_reason: null,
  requested_at: new Date(),
  reviewed_at: null,
  processing_at: null,
  completed_at: null,
  failed_at: null,
  cancelled_at: null,
  metadata: {},
  created_at: new Date(),
  updated_at: new Date(),
} as const;

const payoutHold = {
  id: 'hold-1',
  driver_user_id: 'driver-1',
  ledger_entry_id: 'entry-1',
  booking_id: 'booking-1',
  amount_tzs: '8500',
  reason: 'dispute',
  note: 'Passenger dispute under review',
  created_by: 'admin-1',
  released_by: null,
  released_at: null,
  created_at: new Date(),
  updated_at: new Date(),
} as const;

const payoutHoldRequest = {
  id: 'hold-request-1',
  booking_id: 'booking-1',
  driver_user_id: 'driver-1',
  requested_by: 'passenger-1',
  reason: 'safety_report',
  note: 'passenger: UNSAFE_DRIVER',
  status: 'pending',
  payout_hold_id: null,
  applied_at: null,
  created_at: new Date(),
  updated_at: new Date(),
} as const;

function makeRepo() {
  return {
    getDriverBalance: vi.fn().mockResolvedValue({
      available_tzs: 8500,
      pending_payout_tzs: 0,
      held_tzs: 0,
      paid_out_tzs: 0,
      total_earned_tzs: 8500,
      total_platform_fees_tzs: 1500,
      trip_count: 1,
    }),
    list: vi.fn().mockResolvedValue({ items: [payout], totalCount: 1 }),
    listForDriver: vi.fn().mockResolvedValue({ items: [payout], totalCount: 1 }),
    findById: vi.fn().mockResolvedValue({ ...payout, status: 'processing' }),
    createRequest: vi.fn().mockResolvedValue(payout),
    approve: vi.fn().mockResolvedValue({ ...payout, status: 'processing', reviewed_by: 'admin-1' }),
    markCompleted: vi.fn().mockResolvedValue({ ...payout, status: 'completed', provider_reference: 'MM-1' }),
    markFailed: vi.fn().mockResolvedValue({ ...payout, status: 'failed', failure_reason: 'provider failed' }),
    createHold: vi.fn().mockResolvedValue(payoutHold),
    releaseHold: vi.fn().mockResolvedValue({ ...payoutHold, released_by: 'admin-2', released_at: new Date() }),
    createSafetyHoldRequest: vi.fn().mockResolvedValue(payoutHoldRequest),
    applyPendingHoldRequestForBooking: vi.fn().mockResolvedValue(payoutHold),
  };
}

function makeLedger() {
  return {
    recordPayoutCompleted: vi.fn().mockResolvedValue({ id: 'journal-1' }),
  };
}

describe('PayoutService', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('returns driver balance from repository', async () => {
    const repo = makeRepo();
    const service = new PayoutService(repo as never);

    await expect(service.getDriverBalance('driver-1')).resolves.toEqual({
      available_tzs: 8500,
      pending_payout_tzs: 0,
      held_tzs: 0,
      paid_out_tzs: 0,
      total_earned_tzs: 8500,
      total_platform_fees_tzs: 1500,
      trip_count: 1,
    });
  });

  it('creates a payout request for the requesting driver', async () => {
    const repo = makeRepo();
    const service = new PayoutService(repo as never);

    const result = await service.requestPayout({
      driverUserId: 'driver-1',
      requestedBy: 'driver-1',
      payoutMethod: 'mpesa_tz',
      payoutPhone: '+255700000001',
    });

    expect(result).toEqual(payout);
    expect(repo.createRequest).toHaveBeenCalledWith({
      driverUserId: 'driver-1',
      requestedBy: 'driver-1',
      payoutMethod: 'mpesa_tz',
      payoutPhone: '+255700000001',
    });
  });

  it('lists payouts with bounded pagination', async () => {
    const repo = makeRepo();
    const service = new PayoutService(repo as never);

    const result = await service.listPayouts({ status: 'pending_review', page: 0, pageSize: 500 });

    expect(result).toEqual({
      items: [payout],
      totalCount: 1,
      page: 1,
      pageSize: 100,
    });
    expect(repo.list).toHaveBeenCalledWith({
      status: 'pending_review',
      limit: 100,
      offset: 0,
    });
  });

  it('lists driver payouts with bounded pagination', async () => {
    const repo = makeRepo();
    const service = new PayoutService(repo as never);

    const result = await service.listDriverPayouts('driver-1', -1, 500);

    expect(result).toEqual({
      items: [payout],
      totalCount: 1,
      page: 1,
      pageSize: 100,
    });
    expect(repo.listForDriver).toHaveBeenCalledWith({
      driverUserId: 'driver-1',
      limit: 100,
      offset: 0,
    });
  });

  it('rejects payout requests for a different driver', async () => {
    const repo = makeRepo();
    const service = new PayoutService(repo as never);

    await expect(service.requestPayout({
      driverUserId: 'driver-1',
      requestedBy: 'driver-2',
      payoutMethod: 'mpesa_tz',
      payoutPhone: '+255700000001',
    })).rejects.toMatchObject({ code: 'FORBIDDEN' });

    expect(repo.createRequest).not.toHaveBeenCalled();
  });

  it('rejects payout requests without a phone number', async () => {
    const repo = makeRepo();
    const service = new PayoutService(repo as never);

    await expect(service.requestPayout({
      driverUserId: 'driver-1',
      requestedBy: 'driver-1',
      payoutMethod: 'mpesa_tz',
      payoutPhone: '  ',
    })).rejects.toMatchObject({ code: 'VALIDATION_ERROR' });

    expect(repo.createRequest).not.toHaveBeenCalled();
  });

  it('approves a pending payout', async () => {
    const repo = makeRepo();
    const service = new PayoutService(repo as never);

    const result = await service.approvePayout('payout-1', 'admin-1');

    expect(result.status).toBe('processing');
    expect(repo.approve).toHaveBeenCalledWith('payout-1', 'admin-1');
  });

  it('completes a processing payout and posts a payout ledger journal', async () => {
    const repo = makeRepo();
    const ledger = makeLedger();
    const service = new PayoutService(repo as never, ledger as never);

    const result = await service.completePayout('payout-1', 'MM-1');

    expect(result.status).toBe('completed');
    expect(repo.markCompleted).toHaveBeenCalledWith('payout-1', 'MM-1');
    expect(repo.findById).toHaveBeenCalledWith('payout-1');
    expect(ledger.recordPayoutCompleted).toHaveBeenCalledWith({
      payoutId: 'payout-1',
      driverUserId: 'driver-1',
      amountTzs: 8500,
      providerReference: 'MM-1',
      idempotencyKey: 'payout:payout-1:completed',
    });
  });

  it('rejects payout completion without provider reference', async () => {
    const repo = makeRepo();
    const ledger = makeLedger();
    const service = new PayoutService(repo as never, ledger as never);

    await expect(service.completePayout('payout-1', ' ')).rejects.toMatchObject({ code: 'VALIDATION_ERROR' });

    expect(repo.markCompleted).not.toHaveBeenCalled();
    expect(ledger.recordPayoutCompleted).not.toHaveBeenCalled();
  });

  it('marks payout failed and releases it for retry at repository level', async () => {
    const repo = makeRepo();
    const service = new PayoutService(repo as never);

    const result = await service.failPayout('payout-1', 'provider failed');

    expect(result.status).toBe('failed');
    expect(repo.markFailed).toHaveBeenCalledWith('payout-1', 'provider failed');
  });

  it('creates a payout hold for a payable booking', async () => {
    const repo = makeRepo();
    const service = new PayoutService(repo as never);

    const result = await service.createHold({
      driverUserId: 'driver-1',
      bookingId: 'booking-1',
      reason: 'dispute',
      note: 'Passenger dispute under review',
      createdBy: 'admin-1',
    });

    expect(result).toEqual(payoutHold);
    expect(repo.createHold).toHaveBeenCalledWith({
      driverUserId: 'driver-1',
      ledgerEntryId: undefined,
      bookingId: 'booking-1',
      reason: 'dispute',
      note: 'Passenger dispute under review',
      createdBy: 'admin-1',
    });
  });

  it('rejects payout holds without a payable target', async () => {
    const repo = makeRepo();
    const service = new PayoutService(repo as never);

    await expect(service.createHold({
      driverUserId: 'driver-1',
      reason: 'admin_review',
      createdBy: 'admin-1',
    })).rejects.toMatchObject({ code: 'VALIDATION_ERROR' });

    expect(repo.createHold).not.toHaveBeenCalled();
  });

  it('rejects invalid payout hold reasons', async () => {
    const repo = makeRepo();
    const service = new PayoutService(repo as never);

    await expect(service.createHold({
      driverUserId: 'driver-1',
      ledgerEntryId: 'entry-1',
      reason: 'unsupported' as never,
      createdBy: 'admin-1',
    })).rejects.toMatchObject({ code: 'VALIDATION_ERROR' });

    expect(repo.createHold).not.toHaveBeenCalled();
  });

  it('releases an active payout hold', async () => {
    const repo = makeRepo();
    const service = new PayoutService(repo as never);

    const result = await service.releaseHold('hold-1', 'admin-2');

    expect(result.released_by).toBe('admin-2');
    expect(repo.releaseHold).toHaveBeenCalledWith('hold-1', 'admin-2');
  });

  it('rejects release for inactive payout holds', async () => {
    const repo = makeRepo();
    repo.releaseHold.mockResolvedValueOnce(null);
    const service = new PayoutService(repo as never);

    await expect(service.releaseHold('hold-1', 'admin-2')).rejects.toMatchObject({
      code: 'INVALID_PAYOUT_HOLD_STATE',
    });
  });

  it('records a safety hold request and applies it when a payable exists', async () => {
    const repo = makeRepo();
    const service = new PayoutService(repo as never);

    const result = await service.recordSafetyHoldRequest({
      bookingId: 'booking-1',
      driverUserId: 'driver-1',
      requestedBy: 'passenger-1',
      note: 'passenger: UNSAFE_DRIVER',
    });

    expect(result).toEqual({ request: payoutHoldRequest, hold: payoutHold });
    expect(repo.createSafetyHoldRequest).toHaveBeenCalledWith({
      bookingId: 'booking-1',
      driverUserId: 'driver-1',
      requestedBy: 'passenger-1',
      note: 'passenger: UNSAFE_DRIVER',
    });
    expect(repo.applyPendingHoldRequestForBooking).toHaveBeenCalledWith('booking-1');
  });

  it('keeps a safety hold request pending when no payable exists yet', async () => {
    const repo = makeRepo();
    repo.applyPendingHoldRequestForBooking.mockResolvedValueOnce(null);
    const service = new PayoutService(repo as never);

    const result = await service.recordSafetyHoldRequest({
      bookingId: 'booking-1',
      driverUserId: 'driver-1',
      requestedBy: 'passenger-1',
      note: 'passenger: UNSAFE_DRIVER',
    });

    expect(result).toEqual({ request: payoutHoldRequest, hold: null });
  });

  it('applies a pending safety hold after booking payable accrual', async () => {
    const repo = makeRepo();
    const service = new PayoutService(repo as never);

    const result = await service.applyPendingHoldForBooking('booking-1');

    expect(result).toEqual(payoutHold);
    expect(repo.applyPendingHoldRequestForBooking).toHaveBeenCalledWith('booking-1');
  });
});
