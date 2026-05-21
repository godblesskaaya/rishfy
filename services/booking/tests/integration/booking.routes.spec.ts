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
    declineBooking: vi.fn(),
    startTrip: vi.fn(),
    completeTrip: vi.fn(),
    arrivePickup: vi.fn(),
    boardPassenger: vi.fn(),
    dropoffPassenger: vi.fn(),
    markNoShow: vi.fn(),
    completeJourney: vi.fn(),
    submitRating: vi.fn(),
    listMyBookings: vi.fn(),
    getBooking: vi.fn(),
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

  // ── Decline booking ────────────────────────────────────────────────────────

  it('POST /bookings/:id/decline returns 200 when driver declines within window', async () => {
    const declinedBooking = {
      id: 'booking-1', route_id: 'route-1', passenger_id: 'passenger-1',
      driver_id: 'driver-1', seats_booked: 1, total_price: '5000',
      status: 'declined', payment_status: 'pending', declined_reason: 'Full',
      confirmation_code: null, created_at: new Date(), updated_at: new Date(),
      platform_fee: '250', driver_earnings: '4750', expires_at: null,
      payment_id: null, pickup_name: null, dropoff_name: null,
      pickup_lat: null, pickup_lng: null, dropoff_lat: null, dropoff_lng: null,
      pickup_walking_distance: null, dropoff_walking_distance: null,
      pickup_walking_time: null, estimated_pickup_time: null,
      suggested_pickup_name: null, pickup_point: null, dropoff_point: null,
    };
    serviceMock.declineBooking.mockResolvedValue(declinedBooking);

    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/bookings/booking-1/decline',
      headers: { 'x-user-id': 'driver-1' },
      payload: { reason: 'Full' },
    });

    expect(res.statusCode).toBe(200);
    expect(serviceMock.declineBooking).toHaveBeenCalledWith('booking-1', 'driver-1', 'Full');
  });

  it('POST /bookings/:id/decline returns 409 CANNOT_DECLINE when window expired', async () => {
    const err = Object.assign(new Error('Cannot decline'), { code: 'CANNOT_DECLINE' });
    serviceMock.declineBooking.mockRejectedValue(err);

    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/bookings/booking-1/decline',
      headers: { 'x-user-id': 'driver-1' },
      payload: {},
    });

    expect(res.statusCode).toBe(409);
    expect(res.json()).toMatchObject({ error: 'CANNOT_DECLINE' });
  });

  it('POST /bookings/:id/decline returns 403 when driver is not the booking driver', async () => {
    const err = Object.assign(new Error('Forbidden'), { code: 'FORBIDDEN' });
    serviceMock.declineBooking.mockRejectedValue(err);

    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/bookings/booking-1/decline',
      headers: { 'x-user-id': 'other-driver' },
      payload: {},
    });

    expect(res.statusCode).toBe(403);
  });

  it('POST /bookings/:id/decline returns 401 without x-user-id', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/bookings/booking-1/decline',
      payload: {},
    });
    expect(res.statusCode).toBe(401);
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

  it('POST /bookings/:id/arrive-pickup returns 200 for the assigned driver', async () => {
    serviceMock.arrivePickup.mockResolvedValue({ id: 'booking-1', journey_state: 'driver_arrived' });

    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/bookings/booking-1/arrive-pickup',
      headers: { 'x-user-id': 'driver-1' },
    });

    expect(res.statusCode).toBe(200);
    expect(serviceMock.arrivePickup).toHaveBeenCalledWith('booking-1', 'driver-1');
  });

  it('POST /bookings/:id/board-passenger returns 200 and forwards to service', async () => {
    serviceMock.boardPassenger.mockResolvedValue({ id: 'booking-1', journey_state: 'in_transit', trip_id: 'trip-1' });

    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/bookings/booking-1/board-passenger',
      headers: { 'x-user-id': 'driver-1' },
    });

    expect(res.statusCode).toBe(200);
    expect(serviceMock.boardPassenger).toHaveBeenCalledWith('booking-1', 'driver-1');
  });

  it('POST /bookings/:id/dropoff-passenger returns 200 and forwards to service', async () => {
    serviceMock.dropoffPassenger.mockResolvedValue({ id: 'booking-1', journey_state: 'walking_to_destination' });

    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/bookings/booking-1/dropoff-passenger',
      headers: { 'x-user-id': 'driver-1' },
    });

    expect(res.statusCode).toBe(200);
    expect(serviceMock.dropoffPassenger).toHaveBeenCalledWith('booking-1', 'driver-1');
  });

  it('POST /bookings/:id/mark-no-show returns 200 with a reason payload', async () => {
    serviceMock.markNoShow.mockResolvedValue({ id: 'booking-1', status: 'no_show', journey_state: 'no_show' });

    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/bookings/booking-1/mark-no-show',
      headers: { 'x-user-id': 'driver-1' },
      payload: { reason: 'PASSENGER_ABSENT' },
    });

    expect(res.statusCode).toBe(200);
    expect(serviceMock.markNoShow).toHaveBeenCalledWith('booking-1', 'driver-1', 'PASSENGER_ABSENT');
  });

  it('POST /bookings/:id/complete-journey returns 200 for a participant', async () => {
    serviceMock.completeJourney.mockResolvedValue({ id: 'booking-1', status: 'completed', journey_state: 'completed' });

    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/bookings/booking-1/complete-journey',
      headers: { 'x-user-id': 'passenger-1' },
    });

    expect(res.statusCode).toBe(200);
    expect(serviceMock.completeJourney).toHaveBeenCalledWith('booking-1', 'passenger-1');
  });
});
