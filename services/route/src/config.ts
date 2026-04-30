import { z } from 'zod';
import 'dotenv/config';

const configSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'staging', 'production']).default('development'),
  SERVICE_NAME: z.string().default('route-service'),
  HTTP_PORT: z.coerce.number().int().default(8083),
  GRPC_PORT: z.coerce.number().int().default(50053),
  LOG_LEVEL: z.enum(['trace', 'debug', 'info', 'warn', 'error', 'fatal']).default('info'),

  DATABASE_URL: z.string().url(),
  REDIS_URL: z.string().url(),
  KAFKA_BROKERS: z.string(),

  OTEL_EXPORTER_OTLP_ENDPOINT: z.string().url().optional(),

  GOOGLE_MAPS_API_KEY: z.string().min(1),
  USER_SERVICE_GRPC_URL: z.string().default('user-service:50052'),
  SEARCH_RADIUS_METERS: z.coerce.number().int().default(5000),
  ROUTE_CACHE_TTL_SECONDS: z.coerce.number().int().default(300),
});

export type Config = z.infer<typeof configSchema>;

export const config: Config = configSchema.parse(process.env);

export const isProduction = config.NODE_ENV === 'production';
export const isDevelopment = config.NODE_ENV === 'development';
export const isTest = config.NODE_ENV === 'test';
