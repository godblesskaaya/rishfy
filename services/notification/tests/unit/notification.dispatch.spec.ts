import { beforeEach, describe, expect, it, vi } from 'vitest';

const getTemplateMock = vi.fn();
const createMock = vi.fn();
const markDeliveredMock = vi.fn();
const markFailedMock = vi.fn();
const markSkippedMock = vi.fn();
const isCategoryEnabledMock = vi.fn();
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
    isCategoryEnabled = isCategoryEnabledMock;
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
  isCategoryEnabledMock.mockResolvedValue(true);
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

  it('skips delivery when the user disables the notification category', async () => {
    isCategoryEnabledMock.mockResolvedValue(false);

    await new NotificationService().dispatch({
      userId: 'user-1',
      templateKey: 'payment_completed',
      channels: ['push'],
      vars: {},
      fallbackBody: 'Paid',
      sourceEventType: 'payment.completed',
    });

    expect(isCategoryEnabledMock).toHaveBeenCalledWith('user-1', 'payments');
    expect(createMock).not.toHaveBeenCalled();
    expect(pushSendMock).not.toHaveBeenCalled();
  });

  it('delivers emergency notifications even when the related category is disabled', async () => {
    isCategoryEnabledMock.mockResolvedValue(false);
    pushSendMock.mockResolvedValue({ status: 'sent', providerMessageId: 'push-1' });

    await new NotificationService().dispatch({
      userId: 'user-1',
      templateKey: 'booking.emergency',
      channels: ['push'],
      vars: {},
      fallbackTitle: 'Emergency alert',
      fallbackBody: 'A passenger triggered an emergency alert.',
      sourceEventType: 'booking.emergency',
    });

    expect(isCategoryEnabledMock).not.toHaveBeenCalled();
    expect(createMock).toHaveBeenCalledWith(expect.objectContaining({
      userId: 'user-1',
      templateKey: 'booking.emergency',
      channel: 'push',
      sourceEventType: 'booking.emergency',
    }));
    expect(pushSendMock).toHaveBeenCalled();
    expect(markDeliveredMock).toHaveBeenCalledWith('notif-1', 'push-1');
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
