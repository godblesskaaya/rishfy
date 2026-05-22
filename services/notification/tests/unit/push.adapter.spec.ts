import { beforeEach, describe, expect, it, vi } from 'vitest';

const {
  getActiveTokensForUserMock,
  deactivateByTokenMock,
  initializeAppMock,
  certMock,
  messagingMock,
  sendMock,
  appsMock,
} = vi.hoisted(() => ({
  getActiveTokensForUserMock: vi.fn(),
  deactivateByTokenMock: vi.fn().mockResolvedValue(undefined),
  initializeAppMock: vi.fn(),
  certMock: vi.fn(),
  messagingMock: vi.fn(),
  sendMock: vi.fn(),
  appsMock: [] as unknown[],
}));

vi.mock('../../src/db.js', () => ({
  pgPool: {},
}));

vi.mock('../../src/logger.js', () => ({
  logger: {
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
    debug: vi.fn(),
    child: vi.fn().mockReturnThis(),
  },
}));

vi.mock('../../src/repositories/device-token.repository.js', () => ({
  DeviceTokenRepository: vi.fn().mockImplementation(() => ({
    getActiveTokensForUser: getActiveTokensForUserMock,
    deactivateByToken: deactivateByTokenMock,
  })),
}));

vi.mock('firebase-admin', () => ({
  apps: appsMock,
  initializeApp: initializeAppMock,
  credential: {
    cert: certMock,
  },
  messaging: messagingMock,
}));

const { PushAdapter, __resetPushAdapterForTests } = await import('../../src/channels/push.adapter.js');

describe('PushAdapter', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    __resetPushAdapterForTests();
    delete process.env.FIREBASE_PROJECT_ID;
    delete process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
    delete process.env.FIREBASE_SERVICE_ACCOUNT_PATH;
    appsMock.length = 0;
    initializeAppMock.mockReturnValue({ name: 'firebase-app' });
    messagingMock.mockReturnValue({ send: sendMock });
  });

  it('skips delivery when Firebase is not configured', async () => {
    const adapter = new PushAdapter();

    const result = await adapter.send({
      userId: 'user-1',
      body: 'hello',
    });

    expect(result).toMatchObject({
      status: 'skipped',
      code: 'FIREBASE_NOT_CONFIGURED',
    });
    expect(getActiveTokensForUserMock).not.toHaveBeenCalled();
  });

  it('skips delivery when the user has no active tokens', async () => {
    process.env.FIREBASE_PROJECT_ID = 'demo-project';
    getActiveTokensForUserMock.mockResolvedValue([]);

    const adapter = new PushAdapter();
    const result = await adapter.send({
      userId: 'user-2',
      body: 'hello',
    });

    expect(initializeAppMock).toHaveBeenCalledOnce();
    expect(result).toMatchObject({
      status: 'skipped',
      code: 'NO_ACTIVE_TOKENS',
    });
  });

  it('deactivates stale tokens when FCM rejects them', async () => {
    process.env.FIREBASE_PROJECT_ID = 'demo-project';
    getActiveTokensForUserMock.mockResolvedValue([
      { fcm_token: 'dead-token-12345678' },
    ]);
    sendMock.mockRejectedValue({
      errorInfo: { code: 'messaging/registration-token-not-registered' },
      message: 'token is no longer registered',
    });

    const adapter = new PushAdapter();
    const result = await adapter.send({
      userId: 'user-3',
      body: 'hello',
    });

    expect(result).toMatchObject({
      status: 'failed',
      code: 'messaging/registration-token-not-registered',
    });
    expect(deactivateByTokenMock).toHaveBeenCalledWith('dead-token-12345678');
  });
});
