import type { PaymentProvider } from './payment.provider.js';
import { AzampayProvider } from './azampay.provider.js';
import { MockProvider } from './mock.provider.js';

export function createPaymentProvider(providerName: string): PaymentProvider {
  switch (providerName) {
    case 'azampay':
      return new AzampayProvider({
        baseUrl: process.env['AZAMPAY_BASE_URL'] ?? 'https://sandbox.azampay.co.tz',
        authUrl: process.env['AZAMPAY_AUTH_URL'] ?? 'https://authenticator.sandbox.azampay.co.tz',
        appName: process.env['AZAMPAY_APP_NAME'] ?? '',
        clientId: process.env['AZAMPAY_CLIENT_ID'] ?? '',
        clientSecret: process.env['AZAMPAY_CLIENT_SECRET'] ?? '',
        callbackSecret: process.env['AZAMPAY_CALLBACK_SECRET'] ?? '',
      });
    case 'mock':
      return new MockProvider();
    default:
      throw new Error(`Unknown payment provider: ${providerName}`);
  }
}
