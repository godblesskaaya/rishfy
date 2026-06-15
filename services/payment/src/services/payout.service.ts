import type {
  DriverBalance,
  PayoutHoldReason,
  PayoutHoldRequestRow,
  PayoutHoldRow,
  PayoutListResult,
  PayoutRow,
  PayoutRepository,
} from '../repositories/payout.repository.js';
import type { LedgerPostingService } from './ledger.service.js';

export interface RequestPayoutParams {
  driverUserId: string;
  requestedBy: string;
  payoutMethod: string;
  payoutPhone: string;
}

export interface CreatePayoutHoldParams {
  driverUserId: string;
  ledgerEntryId?: string;
  bookingId?: string;
  reason: PayoutHoldReason;
  note?: string | null;
  createdBy: string;
}

export interface RecordSafetyHoldRequestParams {
  bookingId: string;
  driverUserId: string;
  requestedBy: string;
  note: string;
}

export interface SafetyHoldRequestResult {
  request: PayoutHoldRequestRow;
  hold: PayoutHoldRow | null;
}

export interface ListPayoutsParams {
  status?: string;
  page: number;
  pageSize: number;
}

export interface ListPayoutsResult extends PayoutListResult {
  page: number;
  pageSize: number;
}

export interface PayoutDetail {
  payout: PayoutRow;
  items: Awaited<ReturnType<PayoutRepository['listItems']>>;
  holds: Awaited<ReturnType<PayoutRepository['listHoldsForPayout']>>;
}

const PAYOUT_HOLD_REASONS = new Set<PayoutHoldReason>([
  'safety_report',
  'dispute',
  'no_show',
  'chargeback',
  'admin_review',
]);

export class PayoutService {
  constructor(
    private readonly repo: PayoutRepository,
    private readonly ledger?: LedgerPostingService,
  ) {}

  async getDriverBalance(driverUserId: string): Promise<DriverBalance> {
    return this.repo.getDriverBalance(driverUserId);
  }

  async requestPayout(params: RequestPayoutParams): Promise<PayoutRow> {
    if (params.driverUserId !== params.requestedBy) {
      throw Object.assign(new Error('Drivers can only request their own payouts'), { code: 'FORBIDDEN' });
    }
    if (!params.payoutPhone.trim()) {
      throw Object.assign(new Error('Payout phone is required'), { code: 'VALIDATION_ERROR' });
    }

    return this.repo.createRequest(params);
  }

  async listPayouts(params: ListPayoutsParams): Promise<ListPayoutsResult> {
    const page = Math.max(1, params.page);
    const pageSize = Math.min(Math.max(1, params.pageSize), 100);
    const result = await this.repo.list({
      status: params.status,
      limit: pageSize,
      offset: (page - 1) * pageSize,
    });
    return {
      ...result,
      page,
      pageSize,
    };
  }

  async listDriverPayouts(driverUserId: string, page: number, pageSize: number): Promise<ListPayoutsResult> {
    const normalizedPage = Math.max(1, page);
    const normalizedPageSize = Math.min(Math.max(1, pageSize), 100);
    const result = await this.repo.listForDriver({
      driverUserId,
      limit: normalizedPageSize,
      offset: (normalizedPage - 1) * normalizedPageSize,
    });
    return {
      ...result,
      page: normalizedPage,
      pageSize: normalizedPageSize,
    };
  }

  async getDriverPayoutDetail(driverUserId: string, payoutId: string): Promise<PayoutDetail> {
    const payout = await this.repo.findById(payoutId);
    if (!payout) {
      throw Object.assign(new Error('Payout not found'), { code: 'NOT_FOUND' });
    }
    if (payout.driver_user_id !== driverUserId) {
      throw Object.assign(new Error('Drivers can only view their own payouts'), { code: 'FORBIDDEN' });
    }
    const [items, holds] = await Promise.all([
      this.repo.listItems(payoutId),
      this.repo.listHoldsForPayout(payoutId),
    ]);
    return { payout, items, holds };
  }

  async approvePayout(id: string, reviewedBy: string): Promise<PayoutRow> {
    const payout = await this.repo.approve(id, reviewedBy);
    if (!payout) {
      throw Object.assign(new Error('Payout is not pending review'), { code: 'INVALID_PAYOUT_STATE' });
    }
    return payout;
  }

  async completePayout(id: string, providerReference: string): Promise<PayoutRow> {
    if (!providerReference.trim()) {
      throw Object.assign(new Error('Provider reference is required'), { code: 'VALIDATION_ERROR' });
    }

    const pendingPayout = await this.repo.findById(id);
    if (!pendingPayout || pendingPayout.status !== 'processing') {
      throw Object.assign(new Error('Payout is not processing'), { code: 'INVALID_PAYOUT_STATE' });
    }

    await this.ledger?.recordPayoutCompleted({
      payoutId: pendingPayout.id,
      driverUserId: pendingPayout.driver_user_id,
      amountTzs: Number(pendingPayout.amount_tzs),
      providerReference,
      idempotencyKey: `payout:${pendingPayout.id}:completed`,
    });

    const payout = await this.repo.markCompleted(id, providerReference);
    if (!payout) {
      throw Object.assign(new Error('Payout is not processing'), { code: 'INVALID_PAYOUT_STATE' });
    }

    return payout;
  }

  async failPayout(id: string, failureReason: string): Promise<PayoutRow> {
    const payout = await this.repo.markFailed(id, failureReason);
    if (!payout) {
      throw Object.assign(new Error('Payout cannot be failed in current state'), { code: 'INVALID_PAYOUT_STATE' });
    }
    return payout;
  }

  async createHold(params: CreatePayoutHoldParams): Promise<PayoutHoldRow> {
    if (!params.driverUserId.trim() || !params.createdBy.trim()) {
      throw Object.assign(new Error('Driver and creator are required'), { code: 'VALIDATION_ERROR' });
    }
    if (!params.ledgerEntryId && !params.bookingId) {
      throw Object.assign(new Error('Ledger entry or booking is required'), { code: 'VALIDATION_ERROR' });
    }
    if (!PAYOUT_HOLD_REASONS.has(params.reason)) {
      throw Object.assign(new Error('Invalid hold reason'), { code: 'VALIDATION_ERROR' });
    }

    return this.repo.createHold({
      driverUserId: params.driverUserId,
      ledgerEntryId: params.ledgerEntryId,
      bookingId: params.bookingId,
      reason: params.reason,
      note: params.note,
      createdBy: params.createdBy,
    });
  }

  async releaseHold(id: string, releasedBy: string): Promise<PayoutHoldRow> {
    if (!releasedBy.trim()) {
      throw Object.assign(new Error('Releasing user is required'), { code: 'VALIDATION_ERROR' });
    }

    const hold = await this.repo.releaseHold(id, releasedBy);
    if (!hold) {
      throw Object.assign(new Error('Payout hold is not active'), { code: 'INVALID_PAYOUT_HOLD_STATE' });
    }
    return hold;
  }

  async recordSafetyHoldRequest(params: RecordSafetyHoldRequestParams): Promise<SafetyHoldRequestResult> {
    if (!params.bookingId.trim() || !params.driverUserId.trim() || !params.requestedBy.trim()) {
      throw Object.assign(new Error('Booking, driver, and requester are required'), { code: 'VALIDATION_ERROR' });
    }

    const request = await this.repo.createSafetyHoldRequest({
      bookingId: params.bookingId,
      driverUserId: params.driverUserId,
      requestedBy: params.requestedBy,
      note: params.note,
    });
    const hold = await this.repo.applyPendingHoldRequestForBooking(params.bookingId);
    return { request, hold };
  }

  async applyPendingHoldForBooking(bookingId: string): Promise<PayoutHoldRow | null> {
    if (!bookingId.trim()) {
      throw Object.assign(new Error('Booking is required'), { code: 'VALIDATION_ERROR' });
    }
    return this.repo.applyPendingHoldRequestForBooking(bookingId);
  }
}
