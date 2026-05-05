import { z } from 'zod';
import 'dotenv/config';

const configSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'staging', 'production']).default('development'),
  SERVICE_NAME: z.string().default('notification-service'),
  HTTP_PORT: z.coerce.number().int().default(8087),
  GRPC_PORT: z.coerce.number().int().default(50057),
  LOG_LEVEL: z.enum(['trace', 'debug', 'info', 'warn', 'error', 'fatal']).default('info'),

  DATABASE_URL: z.string().url(),
  REDIS_URL: z.string().url(),
  KAFKA_BROKERS: z.string(),
  NOTIF_QUEUE_ATTEMPTS: z.coerce.number().int().positive().default(4),
  NOTIF_QUEUE_BACKOFF_MS: z.coerce.number().int().positive().default(15000),

  OTEL_EXPORTER_OTLP_ENDPOINT: z.string().url().optional(),
});

export type Config = z.infer<typeof configSchema>;

export const config: Config = configSchema.parse(process.env);

export const isProduction = config.NODE_ENV === 'production';
export const isDevelopment = config.NODE_ENV === 'development';
export const isTest = config.NODE_ENV === 'test';
