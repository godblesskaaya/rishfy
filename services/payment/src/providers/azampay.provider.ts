import { createHmac } from 'crypto';
import { config } from '../config.js';
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
  apiKey: string;
  callbackSecret: string;
}

interface AzampayTokenResponse {
  data?: {
    accessToken?: string;
    expire?: string;
  };
  accessToken?: string;
  expire?: string;
}

interface AzampayMNOCheckoutResponse {
  transactionId?: string;
  reference?: string;
  message: string;
  success?: boolean;
}

interface AzampayCallback {
  transactionId?: string;
  msisdn?: string;
  amount?: string;
  message?: string;
  utilityref?: string;
  operator?: string;
  reference?: string;
  success?: string | boolean;
  transactionstatus?: string;
  transactionStatus?: string;
}

const MNO_MAP: Record<string, string> = {
  mpesa_tz: 'Mpesa',
  tigopesa: 'Tigo',
  airtel_money: 'Airtel',
  halopesa: 'Halopesa',
};

async function readJsonResponse<T>(res: Response, context: string): Promise<T> {
  const body = await res.text();
  if (!body.trim()) {
    throw new Error(`${context} returned an empty response body`);
  }

  try {
    return JSON.parse(body) as T;
  } catch {
    throw new Error(`${context} returned non-JSON response: ${body.slice(0, 240)}`);
  }
}

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
    const data = await readJsonResponse<AzampayTokenResponse>(res, 'Azampay auth');
    const accessToken = data.data?.accessToken ?? data.accessToken;
    const expire = data.data?.expire ?? data.expire;
    if (!accessToken || !expire) {
      throw new Error(`Azampay auth response missing token fields: ${JSON.stringify(data)}`);
    }
    this.token = accessToken;
    this.tokenExpiry = new Date(expire);
    return this.token;
  }

  async initiatePayment(params: InitiatePaymentParams): Promise<InitiatePaymentResult> {
    const token = await this.getToken();
    const operator = MNO_MAP[params.method] ?? 'Mpesa';
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    };

    if (this.cfg.apiKey) {
      headers['X-API-Key'] = this.cfg.apiKey;
    }

    const res = await fetch(`${this.cfg.baseUrl}/azampay/mno/checkout`, {
      method: 'POST',
      headers,
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

    const data = await readJsonResponse<AzampayMNOCheckoutResponse>(res, 'Azampay checkout');

    return {
      providerReference: data.transactionId ?? data.reference ?? null,
      instructions: `Enter your ${operator} PIN to approve payment of TZS ${params.amountTzs.toLocaleString()}.`,
      expiresInSeconds: 120,
    };
  }

  verifyCallback(payload: CallbackPayload): boolean {
    if (!payload.signature) {
      return config.NODE_ENV !== 'production';
    }
    const expected = createHmac('sha256', this.cfg.callbackSecret)
      .update(payload.rawBody)
      .digest('hex');
    return payload.signature === expected;
  }

  parseCallback(payload: CallbackPayload): CallbackResult {
    const data = JSON.parse(payload.rawBody) as AzampayCallback;
    const rawStatus = String(data.transactionStatus ?? data.transactionstatus ?? data.success ?? '').toLowerCase();
    const success = rawStatus === 'true' || rawStatus === '1' || rawStatus === 'success' || rawStatus === 'successful';
    const internalReference = data.utilityref ?? data.reference;
    if (!internalReference) {
      throw new Error('Azampay callback missing internal reference');
    }
    return {
      internalReference,
      providerReference: data.transactionId ?? data.reference ?? '',
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
