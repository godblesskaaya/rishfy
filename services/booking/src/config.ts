import { z } from 'zod';
import 'dotenv/config';

const configSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'staging', 'production']).default('development'),
  SERVICE_NAME: z.string().default('booking-service'),
  HTTP_PORT: z.coerce.number().int().default(8084),
  GRPC_PORT: z.coerce.number().int().default(50054),
  LOG_LEVEL: z.enum(['trace', 'debug', 'info', 'warn', 'error', 'fatal']).default('info'),

  DATABASE_URL: z.string().url(),
  REDIS_URL: z.string().url(),
  KAFKA_BROKERS: z.string(),

  OTEL_EXPORTER_OTLP_ENDPOINT: z.string().url().optional(),

  ROUTE_SERVICE_GRPC_URL: z.string().default('route-service:50053'),
  PAYMENT_SERVICE_GRPC_URL: z.string().default('payment-service:50055'),
  BOOKING_EXPIRY_SECONDS: z.coerce.number().int().default(120),
  PLATFORM_FEE_PERCENT: z.coerce.number().default(15),
});

export type Config = z.infer<typeof configSchema>;

export const config: Config = configSchema.parse(process.env);

export const isProduction = config.NODE_ENV === 'production';
export const isDevelopment = config.NODE_ENV === 'development';
export const isTest = config.NODE_ENV === 'test';
