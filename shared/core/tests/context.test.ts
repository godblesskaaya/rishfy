import { describe, expect, it } from 'vitest';

import { getRequestContext, withRequestContext } from '../src/context.js';

describe('request context', () => {
  it('exposes request context values inside the async scope', async () => {
    await withRequestContext({ requestId: 'req-123', userId: 'user-1' }, async () => {
      await Promise.resolve();
      expect(getRequestContext()).toMatchObject({ requestId: 'req-123', userId: 'user-1' });
    });
  });
});
