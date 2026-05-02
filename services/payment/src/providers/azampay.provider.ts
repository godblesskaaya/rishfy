import { createHmac } from 'crypto';
import type {
  PaymentProvider,
  InitiatePaymentParams,
  InitiatePaymentResult,
  CallbackPayload,
  CallbackResult,
  RefundParams,
  RefundResult,
} from './payment.provider.js';

interface AzampayConfig {
  baseUrl: string;
  authUrl: string;
  appName: string;
  clientId: string;
  clientSecret: string;
  callbackSecret: string;
}

interface AzampayTokenResponse {
  accessToken: string;
  expire: string;
}

interface AzampayMNOPushResponse {
  transactionId: string;
  message: string;
  success: boolean;
}

interface AzampayCallback {
  transactionId: string;
  msisdn: string;
  amount: string;
  message: string;
  utilityref: string;
  operator: string;
  reference: string;
  success: string;
}

const MNO_MAP: Record<string, string> = {
  mpesa_tz: 'Mpesa',
  tigopesa: 'Tigo',
  airtel_money: 'Airtel',
  halopesa: 'Halopesa',
};

export class AzampayProvider implements PaymentProvider {
  readonly name = 'azampay';
  private token: string | null = null;
  private tokenExpiry: Date | null = null;

  constructor(private readonly cfg: AzampayConfig) {}

  private async getToken(): Promise<string> {
    if (this.token && this.tokenExpiry && this.tokenExpiry > new Date()) {
      return this.token;
    }
    const res = await fetch(`${this.cfg.authUrl}/AppRegistration/GenerateToken`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        appName: this.cfg.appName,
        clientId: this.cfg.clientId,
        clientSecret: this.cfg.clientSecret,
      }),
    });
    if (!res.ok) throw new Error(`Azampay auth failed: ${res.status}`);
    const data = (await res.json()) as AzampayTokenResponse;
    this.token = data.accessToken;
    this.tokenExpiry = new Date(data.expire);
    return this.token;
  }

  async initiatePayment(params: InitiatePaymentParams): Promise<InitiatePaymentResult> {
    const token = await this.getToken();
    const operator = MNO_MAP[params.method] ?? 'Mpesa';

    const res = await fetch(`${this.cfg.baseUrl}/azampay/mno/push`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({
        accountNumber: params.payerPhone.replace(/^\+/, ''),
        amount: String(params.amountTzs),
        currency: 'TZS',
        externalId: params.internalReference,
        provider: operator,
        additionalProperties: {
          bookingId: params.bookingId,
          idempotencyKey: params.idempotencyKey,
        },
      }),
    });

    if (!res.ok) {
      const text = await res.text();
      throw new Error(`Azampay push failed (${res.status}): ${text}`);
    }

    const data = (await res.json()) as AzampayMNOPushResponse;

    return {
      providerReference: data.transactionId ?? null,
      instructions: `Enter your ${operator} PIN to approve payment of TZS ${params.amountTzs.toLocaleString()}.`,
      expiresInSeconds: 120,
    };
  }

  verifyCallback(payload: CallbackPayload): boolean {
    const expected = createHmac('sha256', this.cfg.callbackSecret)
      .update(payload.rawBody)
      .digest('hex');
    return payload.signature === expected;
  }

  parseCallback(payload: CallbackPayload): CallbackResult {
    const data = JSON.parse(payload.rawBody) as AzampayCallback;
    const success = data.success === 'true' || data.success === '1';
    return {
      internalReference: data.utilityref ?? data.reference,
      providerReference: data.transactionId,
      status: success ? 'completed' : 'failed',
      failureCode: success ? undefined : 'PROVIDER_DECLINED',
      failureMessage: success ? undefined : data.message,
    };
  }

  async refund(_params: RefundParams): Promise<RefundResult> {
    // Azampay disbursement API — manual in MVP; automated in S5
    throw new Error('Azampay automated refunds not yet implemented — handle manually via dashboard');
  }
}
