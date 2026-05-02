import { z } from 'zod';
import 'dotenv/config';

const configSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'staging', 'production']).default('development'),
  SERVICE_NAME: z.string().default('payment-service'),
  HTTP_PORT: z.coerce.number().int().default(8085),
  GRPC_PORT: z.coerce.number().int().default(50055),
  LOG_LEVEL: z.enum(['trace', 'debug', 'info', 'warn', 'error', 'fatal']).default('info'),

  DATABASE_URL: z.string().url(),
  REDIS_URL: z.string().url(),
  KAFKA_BROKERS: z.string(),

  OTEL_EXPORTER_OTLP_ENDPOINT: z.string().url().optional(),

  PAYMENT_PROVIDER: z.enum(['azampay', 'mock']).default('mock'),
  AZAMPAY_BASE_URL: z.string().default('https://sandbox.azampay.co.tz'),
  AZAMPAY_AUTH_URL: z.string().default('https://authenticator.sandbox.azampay.co.tz'),
  AZAMPAY_APP_NAME: z.string().default(''),
  AZAMPAY_CLIENT_ID: z.string().default(''),
  AZAMPAY_CLIENT_SECRET: z.string().default(''),
  AZAMPAY_CALLBACK_SECRET: z.string().default(''),
});

export type Config = z.infer<typeof configSchema>;

export const config: Config = configSchema.parse(process.env);

export const isProduction = config.NODE_ENV === 'production';
export const isDevelopment = config.NODE_ENV === 'development';
export const isTest = config.NODE_ENV === 'test';
