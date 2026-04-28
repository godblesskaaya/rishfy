import { pino, stdTimeFunctions, type DestinationStream, type Logger, type LoggerOptions } from 'pino';

import { getRequestContext, type RequestContext } from './context.js';

const REDACT_PATHS = [
  '*.password',
  '*.passwordHash',
  '*.phone',
  '*.phone_number',
  '*.email',
  '*.token',
  '*.authorization',
  '*.nationalId',
  '*.refreshToken',
  'req.headers.authorization',
  'req.headers.cookie',
];

export interface CreateLoggerOptions {
  serviceName: string;
  environment: string;
  level?: LoggerOptions['level'];
  pretty?: boolean;
  base?: Record<string, unknown>;
  stream?: DestinationStream;
}

export function createLogger(options: CreateLoggerOptions): Logger {
  const loggerOptions: LoggerOptions = {
    level: options.level ?? 'info',
    base: {
      service: options.serviceName,
      env: options.environment,
      ...options.base,
    },
    redact: {
      paths: REDACT_PATHS,
      censor: '[REDACTED]',
    },
    timestamp: stdTimeFunctions.isoTime,
    mixin() {
      return requestContextMixin(getRequestContext());
    },
  };

  if (options.pretty) {
    loggerOptions.transport = {
      target: 'pino-pretty',
      options: {
        colorize: true,
        translateTime: 'HH:MM:ss.l',
        ignore: 'pid,hostname,service,env',
      },
    };
  }

  return options.stream ? pino(loggerOptions, options.stream) : pino(loggerOptions);
}

export function createChildLogger(logger: Logger, bindings: Record<string, unknown>): Logger {
  return logger.child(bindings);
}

function requestContextMixin(context: RequestContext): Record<string, unknown> {
  return {
    ...(context.requestId ? { requestId: context.requestId } : {}),
    ...(context.correlationId ? { correlationId: context.correlationId } : {}),
    ...(context.userId ? { userId: context.userId } : {}),
  };
}
