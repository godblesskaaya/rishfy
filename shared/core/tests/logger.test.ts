import { Writable } from 'node:stream';

import { describe, expect, it } from 'vitest';

import { createChildLogger, createLogger, withRequestContext } from '../src/index.js';

function createMemoryStream(): { stream: Writable; lines: string[] } {
  const lines: string[] = [];
  const stream = new Writable({
    write(chunk: Buffer | string, _encoding: BufferEncoding, callback: (error?: Error | null) => void) {
      lines.push(chunk.toString());
      callback();
    },
  });

  return { stream, lines };
}

describe('shared logger', () => {
  it('adds service metadata and request context to log records', () => {
    const { stream, lines } = createMemoryStream();
    const logger = createLogger({ serviceName: 'auth', environment: 'test', stream });

    withRequestContext({ requestId: 'req-1', correlationId: 'corr-1', userId: 'user-1' }, () => {
      logger.info({ action: 'login' }, 'handled request');
    });

    const entry = JSON.parse(lines[0] ?? '{}') as Record<string, unknown>;
    expect(entry).toMatchObject({
      service: 'auth',
      env: 'test',
      requestId: 'req-1',
      correlationId: 'corr-1',
      userId: 'user-1',
      action: 'login',
      msg: 'handled request',
    });
  });

  it('creates child loggers with additional bindings', () => {
    const { stream, lines } = createMemoryStream();
    const logger = createLogger({ serviceName: 'auth', environment: 'test', stream });
    const child = createChildLogger(logger, { component: 'otp' });

    child.info('sent code');

    const entry = JSON.parse(lines[0] ?? '{}') as Record<string, unknown>;
    expect(entry).toMatchObject({ component: 'otp', msg: 'sent code' });
  });
});
