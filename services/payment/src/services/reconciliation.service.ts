import type {
  ReconciliationRecordRow,
  ReconciliationRepository,
  ReconciliationStatus,
} from '../repositories/reconciliation.repository.js';

export interface ImportProviderPaymentRecord {
  provider: string;
  providerReference: string;
  amountTzs: number;
  providerStatus: string;
  occurredAt?: Date | null;
  rawPayload?: Record<string, unknown>;
}

export type ImportProviderRecord = ImportProviderPaymentRecord;

export interface ImportReconciliationResult {
  imported: ReconciliationRecordRow[];
  summary: Record<ReconciliationStatus, number>;
}

export class ReconciliationService {
  constructor(private readonly repo: ReconciliationRepository) {}

  async importPaymentRecords(
    records: ImportProviderPaymentRecord[],
    importedBy: string,
  ): Promise<ImportReconciliationResult> {
    return this.importRecords('payment', records, importedBy);
  }

  async importRefundRecords(
    records: ImportProviderRecord[],
    importedBy: string,
  ): Promise<ImportReconciliationResult> {
    return this.importRecords('refund', records, importedBy);
  }

  async importPayoutRecords(
    records: ImportProviderRecord[],
    importedBy: string,
  ): Promise<ImportReconciliationResult> {
    return this.importRecords('payout', records, importedBy);
  }

  private async importRecords(
    recordType: 'payment' | 'refund' | 'payout',
    records: ImportProviderRecord[],
    importedBy: string,
  ): Promise<ImportReconciliationResult> {
    const imported: ReconciliationRecordRow[] = [];
    const summary: Record<ReconciliationStatus, number> = {
      matched: 0,
      unmatched: 0,
      amount_mismatch: 0,
      status_mismatch: 0,
    };

    for (const record of records) {
      const classified = await this.classifyRecord(recordType, record);
      const row = await this.repo.createRecord({
        provider: record.provider,
        recordType,
        providerReference: record.providerReference,
        amountTzs: record.amountTzs,
        providerStatus: record.providerStatus,
        occurredAt: record.occurredAt,
        rawPayload: record.rawPayload,
        importedBy,
        ...classified,
      });
      summary[row.match_status] += 1;
      imported.push(row);
    }

    return { imported, summary };
  }

  async list(params: { status?: ReconciliationStatus; limit: number; offset: number }): Promise<ReconciliationRecordRow[]> {
    return this.repo.list(params);
  }

  private async classifyRecord(recordType: 'payment' | 'refund' | 'payout', record: ImportProviderRecord): Promise<{
    matchStatus: ReconciliationStatus;
    matchedPaymentId?: string | null;
    mismatchReason?: string | null;
  }> {
    if (!Number.isSafeInteger(record.amountTzs) || record.amountTzs <= 0) {
      throw Object.assign(new Error('Provider record amount must be a positive integer'), { code: 'INVALID_MONEY_AMOUNT' });
    }
    if (!record.providerReference.trim()) {
      throw Object.assign(new Error('Provider reference is required'), { code: 'VALIDATION_ERROR' });
    }
    if (recordType === 'refund') return this.classifyRefundRecord(record);
    if (recordType === 'payout') return this.classifyPayoutRecord(record);

    const payment = await this.repo.findPaymentByProviderReference(record.providerReference);
    if (!payment) {
      return { matchStatus: 'unmatched', mismatchReason: 'No local payment found for provider reference' };
    }
    if (payment.amount_tzs !== record.amountTzs) {
      return {
        matchStatus: 'amount_mismatch',
        matchedPaymentId: payment.id,
        mismatchReason: `Provider amount ${record.amountTzs} does not match local amount ${payment.amount_tzs}`,
      };
    }

    const normalizedProviderStatus = record.providerStatus.toLowerCase();
    if (normalizedProviderStatus !== 'completed' && normalizedProviderStatus !== 'success' && normalizedProviderStatus !== 'successful') {
      return {
        matchStatus: 'status_mismatch',
        matchedPaymentId: payment.id,
        mismatchReason: `Provider status ${record.providerStatus} is not successful`,
      };
    }
    if (payment.status !== 'completed') {
      return {
        matchStatus: 'status_mismatch',
        matchedPaymentId: payment.id,
        mismatchReason: `Local payment status ${payment.status} is not completed`,
      };
    }

    return { matchStatus: 'matched', matchedPaymentId: payment.id };
  }

  private async classifyRefundRecord(record: ImportProviderRecord): Promise<{
    matchStatus: ReconciliationStatus;
    matchedPaymentId?: string | null;
    mismatchReason?: string | null;
  }> {
    const refund = await this.repo.findRefundByProviderReference(record.providerReference);
    if (!refund) {
      return { matchStatus: 'unmatched', mismatchReason: 'No local refund found for provider reference' };
    }
    if (refund.amount_tzs !== record.amountTzs) {
      return {
        matchStatus: 'amount_mismatch',
        matchedPaymentId: refund.payment_id,
        mismatchReason: `Provider amount ${record.amountTzs} does not match local refund amount ${refund.amount_tzs}`,
      };
    }
    if (!this.isSuccessfulProviderStatus(record.providerStatus) || refund.status !== 'completed') {
      return {
        matchStatus: 'status_mismatch',
        matchedPaymentId: refund.payment_id,
        mismatchReason: `Provider status ${record.providerStatus} or local refund status ${refund.status} is not completed`,
      };
    }
    return { matchStatus: 'matched', matchedPaymentId: refund.payment_id };
  }

  private async classifyPayoutRecord(record: ImportProviderRecord): Promise<{
    matchStatus: ReconciliationStatus;
    matchedPaymentId?: string | null;
    mismatchReason?: string | null;
  }> {
    const payout = await this.repo.findPayoutByProviderReference(record.providerReference);
    if (!payout) {
      return { matchStatus: 'unmatched', mismatchReason: 'No local payout found for provider reference' };
    }
    if (Number(payout.amount_tzs) !== record.amountTzs) {
      return {
        matchStatus: 'amount_mismatch',
        mismatchReason: `Provider amount ${record.amountTzs} does not match local payout amount ${payout.amount_tzs}`,
      };
    }
    if (!this.isSuccessfulProviderStatus(record.providerStatus) || payout.status !== 'completed') {
      return {
        matchStatus: 'status_mismatch',
        mismatchReason: `Provider status ${record.providerStatus} or local payout status ${payout.status} is not completed`,
      };
    }
    return { matchStatus: 'matched' };
  }

  private isSuccessfulProviderStatus(status: string): boolean {
    const normalizedProviderStatus = status.toLowerCase();
    return normalizedProviderStatus === 'completed' ||
      normalizedProviderStatus === 'success' ||
      normalizedProviderStatus === 'successful';
  }
}
