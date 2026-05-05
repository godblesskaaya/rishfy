import { beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('../../src/clients/route.grpc.client.js', () => ({
  reserveSeats: vi.fn(),
  releaseSeats: vi.fn().mockResolvedValue(undefined),
}));

vi.mock('../../src/clients/payment.grpc.client.js', () => ({
  refundPayment: vi.fn(),
}));

vi.mock('../../src/config.js', () => ({
  config: {
    NODE_ENV: 'test',
    SERVICE_NAME: 'booking-service',
    HTTP_PORT: 8084,
    GRPC_PORT: 50054,
    LOG_LEVEL: 'silent',
    DATABASE_URL: 'postgresql://test:test@localhost/test',
    REDIS_URL: 'redis://localhost:6379',
    KAFKA_BROKERS: 'localhost:9092',
    ROUTE_SERVICE_GRPC_URL: 'localhost:50053',
    PAYMENT_SERVICE_GRPC_URL: 'localhost:50055',
    BOOKING_EXPIRY_SECONDS: 120,
    PLATFORM_FEE_PERCENT: 15,
  },
  isProduction: false, isDevelopment: false, isTest: true,
}));

vi.mock('../../src/events/booking.events.js', () => ({
  publishBookingCreated: vi.fn(),
  publishBookingConfirmed: vi.fn(),
  publishBookingCancelled: vi.fn(),
  publishBookingEmergency: vi.fn(),
  publishBookingCompleted: vi.fn(),
  publishBookingExpired: vi.fn(),
  publishTripStarted: vi.fn(),
  publishTripCompleted: vi.fn(),
  publishBookingRated: vi.fn(),
}));

const { BookingService } = await import('../../src/services/booking.service.js');
const { refundPayment } = await import('../../src/clients/payment.grpc.client.js');
const { releaseSeats } = await import('../../src/clients/route.grpc.client.js');
const { publishBookingEmergency } = await import('../../src/events/booking.events.js');

const baseBooking = {
  id: 'booking-1',
  route_id: 'route-1',
  passenger_id: 'passenger-1',
  driver_id: 'driver-1',
  seats_booked: 1,
  seat_count: 1,
  pickup_name: null,
  dropoff_name: null,
  pickup_lat: null,
  pickup_lng: null,
  dropoff_lat: null,
  dropoff_lng: null,
  total_price: '10000',
  platform_fee: '1500',
  driver_earnings: '8500',
  status: 'confirmed' as const,
  payment_status: 'paid' as const,
  payment_reference: null,
  payment_id: 'payment-1',
  confirmation_code: 'ABC12345',
  idempotency_key: 'idem-1',
  expires_at: new Date(),
  confirmed_at: new Date(),
  cancelled_at: null,
  cancellation_reason: null,
  cancellation_policy: null,
  completed_at: null,
  trip_started_at: null,
  trip_completed_at: null,
  passenger_rating: null,
  driver_rating: null,
  passenger_review: null,
  driver_review: null,
  created_at: new Date(),
  updated_at: new Date(),
};

function makeRepo() {
  return {
    findById: vi.fn(),
    cancelByPassenger: vi.fn(),
    appendEvent: vi.fn().mockResolvedValue(undefined),
    markPaymentRefunded: vi.fn(),
  } as const;
}

beforeEach(() => {
  vi.clearAllMocks();
});

describe('BookingService.cancelByPassengerWithRefund', () => {
  it('orchestrates refund for paid bookings', async () => {
    const repo = makeRepo();
    const cancelled = { ...baseBooking, status: 'passenger_cancelled' as const };
    repo.findById.mockResolvedValue(baseBooking);
    repo.cancelByPassenger.mockResolvedValue(cancelled);
    repo.markPaymentRefunded.mockResolvedValue({ ...cancelled, payment_status: 'refunded' as const });
    vi.mocked(refundPayment).mockResolvedValue({
      refundReference: 'RF-123',
      refundedAmountTzs: 10000,
      paymentStatus: 'REFUNDED',
    });

    const svc = new BookingService(repo as never);
    const result = await svc.cancelByPassengerWithRefund('booking-1', 'passenger-1', 'PASSENGER_CANCELLED');

    expect(vi.mocked(releaseSeats)).toHaveBeenCalledWith('booking-1', 'PASSENGER_CANCELLED');
    expect(vi.mocked(refundPayment)).toHaveBeenCalledWith('payment-1', 'passenger-1', 'PASSENGER_CANCELLED');
    expect(repo.markPaymentRefunded).toHaveBeenCalledWith('booking-1', 'PAYMENT_SERVICE_POLICY');
    expect(result.refund.applied).toBe(true);
    expect(result.refund.refundedAmountTzs).toBe(10000);
    expect(result.refund.refundReference).toBe('RF-123');
  });

  it('keeps cancellation successful when refund is unavailable', async () => {
    const repo = makeRepo();
    const cancelled = { ...baseBooking, status: 'passenger_cancelled' as const };
    repo.findById.mockResolvedValue(baseBooking);
    repo.cancelByPassenger.mockResolvedValue(cancelled);
    vi.mocked(refundPayment).mockResolvedValue(null);

    const svc = new BookingService(repo as never);
    const result = await svc.cancelByPassengerWithRefund('booking-1', 'passenger-1', 'PASSENGER_CANCELLED');

    expect(result.booking.id).toBe('booking-1');
    expect(result.refund.attempted).toBe(true);
    expect(result.refund.applied).toBe(false);
    expect(repo.markPaymentRefunded).not.toHaveBeenCalled();
  });
});

describe('BookingService.triggerEmergency', () => {
  it('emits emergency event for booking participants', async () => {
    const repo = makeRepo();
    repo.findById.mockResolvedValue(baseBooking);

    const svc = new BookingService(repo as never);
    await svc.triggerEmergency('booking-1', 'passenger-1', 'UNSAFE_DRIVER');

    expect(repo.appendEvent).toHaveBeenCalledWith(
      'booking-1',
      'booking.emergency',
      expect.objectContaining({ reportedBy: 'passenger-1', reporterRole: 'passenger', reason: 'UNSAFE_DRIVER' }),
    );
    expect(vi.mocked(publishBookingEmergency)).toHaveBeenCalledTimes(1);
  });

  it('rejects non-participants', async () => {
    const repo = makeRepo();
    repo.findById.mockResolvedValue(baseBooking);

    const svc = new BookingService(repo as never);
    await expect(svc.triggerEmergency('booking-1', 'intruder-1', 'SOS')).rejects.toMatchObject({ code: 'FORBIDDEN' });
  });
});
