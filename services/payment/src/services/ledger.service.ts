import type {
  LedgerAccountInput,
  LedgerEntryInput,
  LedgerJournalInput,
  LedgerJournalRow,
  LedgerRepository,
} from '../repositories/ledger.repository.js';

type LedgerPostingRepository = Pick<LedgerRepository, 'getOrCreateAccount' | 'postJournal'>;

export interface PaymentCapturedParams {
  paymentId: string;
  bookingId: string;
  amountTzs: number;
  providerClearingAccountId: string;
  passengerFundsAccountId: string;
  idempotencyKey: string;
  sourceId: string;
  metadata?: Record<string, unknown>;
  correlationId?: string | null;
}

export interface PaymentCapturedForPaymentParams {
  paymentId: string;
  bookingId: string;
  userId: string;
  provider: string;
  amountTzs: number;
  idempotencyKey: string;
  metadata?: Record<string, unknown>;
  correlationId?: string | null;
}

export interface DriverPayableAccruedParams {
  paymentId: string;
  bookingId: string;
  driverUserId: string;
  totalAmountTzs: number;
  platformFeeTzs: number;
  driverEarningsTzs: number;
  passengerFundsAccountId: string;
  platformRevenueAccountId: string;
  driverPayableAccountId: string;
  idempotencyKey: string;
  metadata?: Record<string, unknown>;
  correlationId?: string | null;
}

export interface DriverPayableAccruedForBookingParams {
  paymentId: string;
  bookingId: string;
  passengerUserId: string;
  driverUserId: string;
  totalAmountTzs: number;
  platformFeeTzs: number;
  driverEarningsTzs: number;
  idempotencyKey: string;
  metadata?: Record<string, unknown>;
  correlationId?: string | null;
}

export interface PayoutCompletedParams {
  payoutId: string;
  driverUserId: string;
  amountTzs: number;
  idempotencyKey: string;
  providerReference: string;
  metadata?: Record<string, unknown>;
  correlationId?: string | null;
}

export interface RefundCompletedForPaymentParams {
  refundId: string;
  paymentId: string;
  bookingId: string;
  passengerUserId: string;
  provider: string;
  amountTzs: number;
  providerReference: string;
  idempotencyKey: string;
  metadata?: Record<string, unknown>;
  correlationId?: string | null;
}

export class LedgerValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'LedgerValidationError';
  }
}

export class LedgerPostingService {
  constructor(private readonly repo: LedgerPostingRepository) {}

  async postJournal(input: LedgerJournalInput): Promise<LedgerJournalRow> {
    const normalized = {
      ...input,
      currency: (input.currency ?? 'TZS').toUpperCase(),
    };
    this.validateJournal(normalized);
    return this.repo.postJournal(normalized);
  }

  async recordPaymentCaptured(params: PaymentCapturedParams): Promise<LedgerJournalRow> {
    return this.postJournal({
      journalType: 'payment_captured',
      sourceType: 'payment',
      sourceId: params.sourceId,
      bookingId: params.bookingId,
      paymentId: params.paymentId,
      idempotencyKey: params.idempotencyKey,
      correlationId: params.correlationId,
      metadata: params.metadata,
      entries: [
        {
          accountId: params.providerClearingAccountId,
          direction: 'debit',
          amountTzs: params.amountTzs,
        },
        {
          accountId: params.passengerFundsAccountId,
          direction: 'credit',
          amountTzs: params.amountTzs,
        },
      ],
    });
  }

  async recordPaymentCapturedForPayment(params: PaymentCapturedForPaymentParams): Promise<LedgerJournalRow> {
    const providerClearing = await this.repo.getOrCreateAccount(this.account({
      ownerType: 'provider',
      ownerId: null,
      accountType: 'provider_clearing',
      name: 'Provider clearing',
      metadata: { provider: params.provider },
    }));
    const passengerFunds = await this.repo.getOrCreateAccount(this.account({
      ownerType: 'passenger',
      ownerId: params.userId,
      accountType: 'passenger_funds',
      name: 'Passenger funds',
    }));

    return this.recordPaymentCaptured({
      paymentId: params.paymentId,
      bookingId: params.bookingId,
      amountTzs: params.amountTzs,
      providerClearingAccountId: providerClearing.id,
      passengerFundsAccountId: passengerFunds.id,
      idempotencyKey: params.idempotencyKey,
      sourceId: params.paymentId,
      metadata: params.metadata,
      correlationId: params.correlationId,
    });
  }

  async accrueDriverPayable(params: DriverPayableAccruedParams): Promise<LedgerJournalRow> {
    return this.postJournal({
      journalType: 'driver_payable_accrued',
      sourceType: 'booking',
      sourceId: params.bookingId,
      bookingId: params.bookingId,
      paymentId: params.paymentId,
      idempotencyKey: params.idempotencyKey,
      correlationId: params.correlationId,
      metadata: {
        driverUserId: params.driverUserId,
        ...params.metadata,
      },
      entries: [
        {
          accountId: params.passengerFundsAccountId,
          direction: 'debit',
          amountTzs: params.totalAmountTzs,
        },
        {
          accountId: params.platformRevenueAccountId,
          direction: 'credit',
          amountTzs: params.platformFeeTzs,
        },
        {
          accountId: params.driverPayableAccountId,
          direction: 'credit',
          amountTzs: params.driverEarningsTzs,
        },
      ],
    });
  }

  async accrueDriverPayableForBooking(params: DriverPayableAccruedForBookingParams): Promise<LedgerJournalRow> {
    const passengerFunds = await this.repo.getOrCreateAccount(this.account({
      ownerType: 'passenger',
      ownerId: params.passengerUserId,
      accountType: 'passenger_funds',
      name: 'Passenger funds',
    }));
    const platformRevenue = await this.repo.getOrCreateAccount(this.account({
      ownerType: 'platform',
      ownerId: null,
      accountType: 'platform_revenue',
      name: 'Platform revenue',
    }));
    const driverPayable = await this.repo.getOrCreateAccount(this.account({
      ownerType: 'driver',
      ownerId: params.driverUserId,
      accountType: 'driver_payable',
      name: 'Driver payable',
    }));

    return this.accrueDriverPayable({
      paymentId: params.paymentId,
      bookingId: params.bookingId,
      driverUserId: params.driverUserId,
      totalAmountTzs: params.totalAmountTzs,
      platformFeeTzs: params.platformFeeTzs,
      driverEarningsTzs: params.driverEarningsTzs,
      passengerFundsAccountId: passengerFunds.id,
      platformRevenueAccountId: platformRevenue.id,
      driverPayableAccountId: driverPayable.id,
      idempotencyKey: params.idempotencyKey,
      metadata: params.metadata,
      correlationId: params.correlationId,
    });
  }

  async recordPayoutCompleted(params: PayoutCompletedParams): Promise<LedgerJournalRow> {
    const driverPayable = await this.repo.getOrCreateAccount(this.account({
      ownerType: 'driver',
      ownerId: params.driverUserId,
      accountType: 'driver_payable',
      name: 'Driver payable',
    }));
    const providerClearing = await this.repo.getOrCreateAccount(this.account({
      ownerType: 'provider',
      ownerId: null,
      accountType: 'provider_clearing',
      name: 'Provider clearing',
    }));

    return this.postJournal({
      journalType: 'payout_completed',
      sourceType: 'payout',
      sourceId: params.payoutId,
      idempotencyKey: params.idempotencyKey,
      correlationId: params.correlationId,
      metadata: {
        providerReference: params.providerReference,
        driverUserId: params.driverUserId,
        ...params.metadata,
      },
      entries: [
        {
          accountId: driverPayable.id,
          direction: 'debit',
          amountTzs: params.amountTzs,
        },
        {
          accountId: providerClearing.id,
          direction: 'credit',
          amountTzs: params.amountTzs,
        },
      ],
    });
  }

  async recordRefundCompletedForPayment(params: RefundCompletedForPaymentParams): Promise<LedgerJournalRow> {
    const passengerFunds = await this.repo.getOrCreateAccount(this.account({
      ownerType: 'passenger',
      ownerId: params.passengerUserId,
      accountType: 'passenger_funds',
      name: 'Passenger funds',
    }));
    const providerClearing = await this.repo.getOrCreateAccount(this.account({
      ownerType: 'provider',
      ownerId: null,
      accountType: 'provider_clearing',
      name: 'Provider clearing',
      metadata: { provider: params.provider },
    }));

    return this.postJournal({
      journalType: 'refund_completed',
      sourceType: 'refund',
      sourceId: params.refundId,
      bookingId: params.bookingId,
      paymentId: params.paymentId,
      idempotencyKey: params.idempotencyKey,
      correlationId: params.correlationId,
      metadata: {
        providerReference: params.providerReference,
        passengerUserId: params.passengerUserId,
        ...params.metadata,
      },
      entries: [
        {
          accountId: passengerFunds.id,
          direction: 'debit',
          amountTzs: params.amountTzs,
        },
        {
          accountId: providerClearing.id,
          direction: 'credit',
          amountTzs: params.amountTzs,
        },
      ],
    });
  }


  private validateJournal(input: LedgerJournalInput): void {
    if (!input.idempotencyKey.trim()) {
      throw new LedgerValidationError('Ledger journal requires an idempotency key');
    }
    if (!input.sourceType.trim() || !input.sourceId.trim()) {
      throw new LedgerValidationError('Ledger journal requires source type and source id');
    }
    if (!input.currency || input.currency.length !== 3) {
      throw new LedgerValidationError('Ledger journal currency must be a 3-letter code');
    }
    if (input.entries.length < 2) {
      throw new LedgerValidationError('Ledger journal requires at least two entries');
    }

    let debitTotal = 0;
    let creditTotal = 0;
    for (const entry of input.entries) {
      this.validateEntry(entry);
      if (entry.direction === 'debit') {
        debitTotal += entry.amountTzs;
      } else {
        creditTotal += entry.amountTzs;
      }
    }

    if (debitTotal !== creditTotal) {
      throw new LedgerValidationError(`Ledger journal is unbalanced: debit=${debitTotal}, credit=${creditTotal}`);
    }
  }

  private validateEntry(entry: LedgerEntryInput): void {
    if (!entry.accountId.trim()) {
      throw new LedgerValidationError('Ledger entry requires an account id');
    }
    if (!Number.isSafeInteger(entry.amountTzs) || entry.amountTzs <= 0) {
      throw new LedgerValidationError('Ledger entry amount must be a positive integer');
    }
  }

  private account(input: LedgerAccountInput): LedgerAccountInput {
    return input;
  }
}
