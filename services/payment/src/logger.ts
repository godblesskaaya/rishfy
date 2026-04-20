import pino from 'pino';

import { config, isDevelopment } from './config.js';

// Redact PII automatically.
const REDACT_PATHS = [
  '*.password',
  '*.phone_number',
  '*.email',
  '*.token',
  '*.authorization',
  'req.headers.authorization',
  'req.headers.cookie',
];

export const logger = pino({
  level: config.LOG_LEVEL,
  base: {
    service: config.SERVICE_NAME,
    env: config.NODE_ENV,
  },
  redact: {
    paths: REDACT_PATHS,
    censor: '[REDACTED]',
  },
  timestamp: pino.stdTimeFunctions.isoTime,
  ...(isDevelopment && {
    transport: {
      target: 'pino-pretty',
      options: {
        colorize: true,
        translateTime: 'HH:MM:ss.l',
        ignore: 'pid,hostname,service,env',
      },
    },
  }),
});

export type Logger = typeof logger;
