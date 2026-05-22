import { beforeEach, describe, expect, it, vi } from 'vitest';

const getTemplateMock = vi.fn();
const createMock = vi.fn();
const markDeliveredMock = vi.fn();
const markFailedMock = vi.fn();
const markSkippedMock = vi.fn();
const pushSendMock = vi.fn();
const smsSendMock = vi.fn();
const inAppSendMock = vi.fn();

vi.mock('../../src/db.js', () => ({ pgPool: {} }));
vi.mock('../../src/config.js', () => ({
  config: {
    NODE_ENV: 'test',
    SERVICE_NAME: 'notification-service',
    HTTP_PORT: 8087,
    GRPC_PORT: 50057,
    LOG_LEVEL: 'silent',
    DATABASE_URL: 'postgresql://test:test@localhost/test',
    REDIS_URL: 'redis://localhost:6379',
    KAFKA_BROKERS: 'localhost:9092',
    NOTIF_QUEUE_ATTEMPTS: 4,
    NOTIF_QUEUE_BACKOFF_MS: 15000,
  },
  isProduction: false,
  isDevelopment: false,
  isTest: true,
}));
vi.mock('../../src/logger.js', () => ({
  logger: {
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
    debug: vi.fn(),
  },
}));
vi.mock('../../src/repositories/notification.repository.js', () => ({
  NotificationRepository: class {
    getTemplate = getTemplateMock;
    create = createMock;
    markDelivered = markDeliveredMock;
    markFailed = markFailedMock;
    markSkipped = markSkippedMock;
  },
}));
vi.mock('../../src/channels/push.adapter.js', () => ({
  PushAdapter: class {
    send = pushSendMock;
  },
}));
vi.mock('../../src/channels/sms.adapter.js', () => ({
  SmsAdapter: class {
    send = smsSendMock;
  },
}));
vi.mock('../../src/channels/in-app.adapter.js', () => ({
  InAppAdapter: class {
    send = inAppSendMock;
  },
}));

const { NotificationService } = await import('../../src/services/notification.service.js');

beforeEach(() => {
  vi.clearAllMocks();
  getTemplateMock.mockResolvedValue({
    subject: null,
    body_template: 'Trip update',
  });
  createMock.mockResolvedValue({ id: 'notif-1' });
  markDeliveredMock.mockResolvedValue(undefined);
  markFailedMock.mockResolvedValue(undefined);
  markSkippedMock.mockResolvedValue(undefined);
  smsSendMock.mockResolvedValue({ status: 'sent', providerMessageId: 'sms-1' });
  inAppSendMock.mockResolvedValue({ status: 'sent' });
});

describe('NotificationService.dispatch', () => {
  it('marks skipped deliveries without recording them as delivered', async () => {
    pushSendMock.mockResolvedValue({
      status: 'skipped',
      code: 'PUSH_PROVIDER_NOT_CONFIGURED',
      error: 'Push adapter is not configured',
    });

    const svc = new NotificationService();
    await svc.dispatch({
      userId: 'user-1',
      templateKey: 'trip.started',
      channels: ['push'],
      vars: {},
    });

    expect(markSkippedMock).toHaveBeenCalledWith('notif-1', 'Push adapter is not configured');
    expect(markDeliveredMock).not.toHaveBeenCalled();
    expect(markFailedMock).not.toHaveBeenCalled();
  });

  it('marks failed deliveries when the channel adapter reports a send failure', async () => {
    pushSendMock.mockResolvedValue({
      status: 'failed',
      code: 'FCM_SEND_FAILED',
      error: 'provider down',
    });

    const svc = new NotificationService();
    await svc.dispatch({
      userId: 'user-1',
      templateKey: 'trip.started',
      channels: ['push'],
      vars: {},
    });

    expect(markFailedMock).toHaveBeenCalledWith('notif-1', 'provider down');
    expect(markDeliveredMock).not.toHaveBeenCalled();
  });
});
