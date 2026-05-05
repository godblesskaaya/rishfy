import fastify, { type FastifyInstance } from 'fastify';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const {
  serviceMock,
  scheduleExpiryMock,
  removeJobMock,
} = vi.hoisted(() => ({
  serviceMock: {
    createBooking: vi.fn(),
    triggerEmergency: vi.fn(),
    cancelByPassengerWithRefund: vi.fn(),
  },
  scheduleExpiryMock: vi.fn(),
  removeJobMock: vi.fn(),
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
    BOOKING_EXPIRY_MINUTES: 2,
  },
}));

vi.mock('../../src/logger.js', () => ({
  logger: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
}));

vi.mock('../../src/db.js', () => ({
  pgPool: {},
}));

vi.mock('../../src/repositories/booking.repository.js', () => ({
  BookingRepository: vi.fn().mockImplementation(() => ({})),
}));

vi.mock('../../src/services/booking.service.js', () => ({
  BookingService: vi.fn().mockImplementation(() => serviceMock),
}));

vi.mock('../../src/jobs/booking-expiry.worker.js', () => ({
  scheduleExpiry: scheduleExpiryMock,
  getExpiryQueue: vi.fn().mockImplementation(() => ({
    remove: removeJobMock,
  })),
}));

vi.mock('ioredis', () => ({
  default: vi.fn().mockImplementation(() => ({})),
}));

const { bookingRoutes } = await import('../../src/controllers/booking.routes.js');

describe('booking routes integration', () => {
  let app: FastifyInstance;

  beforeEach(async () => {
    vi.clearAllMocks();
    app = fastify();
    await app.register(bookingRoutes);
  });

  afterEach(async () => {
    await app.close();
  });

  it('creates a booking and schedules expiry', async () => {
    const booking = {
      id: 'booking-1',
      route_id: 'route-1',
      passenger_id: 'passenger-1',
      driver_id: 'driver-1',
      seats_booked: 1,
      price_per_seat_tzs: 5000,
      total_price_tzs: 5000,
      status: 'pending',
      payment_status: 'pending',
      confirmation_code: 'ABCD1234',
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    };
    serviceMock.createBooking.mockResolvedValue(booking);
    scheduleExpiryMock.mockResolvedValue(undefined);

    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/bookings',
      headers: { 'x-user-id': 'passenger-1' },
      payload: {
        routeId: 'route-1',
        driverId: 'driver-1',
        seatsBooked: 1,
        pricePerSeat: 5000,
        idempotencyKey: 'idem-1',
      },
    });

    expect(res.statusCode).toBe(201);
    expect(serviceMock.createBooking).toHaveBeenCalledTimes(1);
    expect(scheduleExpiryMock).toHaveBeenCalledWith('booking-1', expect.anything());
  });

  it('reports emergency and maps service response', async () => {
    serviceMock.triggerEmergency.mockResolvedValue({
      id: 'booking-2',
      route_id: 'route-2',
    });

    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/bookings/booking-2/emergency',
      headers: { 'x-user-id': 'passenger-2' },
      payload: { reason: 'SOS' },
    });

    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({
      reported: true,
      bookingId: 'booking-2',
      routeId: 'route-2',
      reason: 'SOS',
    });
    expect(serviceMock.triggerEmergency).toHaveBeenCalledWith('booking-2', 'passenger-2', 'SOS');
  });
});
