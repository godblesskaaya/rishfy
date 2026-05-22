import { beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('../../src/clients/route.grpc.client.js', () => ({
  reserveSeats: vi.fn(),
  releaseSeats: vi.fn().mockResolvedValue(undefined),
}));

vi.mock('../../src/clients/payment.grpc.client.js', () => ({
  refundPayment: vi.fn(),
}));

vi.mock('../../src/clients/location.grpc.client.js', () => ({
  startTrackedTrip: vi.fn(),
  completeTrackedTrip: vi.fn().mockResolvedValue(undefined),
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
  publishBookingCompleted: vi.fn(),
  publishBookingDeclined: vi.fn(),
  publishBookingEmergency: vi.fn(),
  publishBookingExpired: vi.fn(),
  publishTripStarted: vi.fn(),
  publishTripCompleted: vi.fn(),
  publishBookingRated: vi.fn(),
  publishBookingJourneyStarted: vi.fn(),
  publishDriverArrivedPickup: vi.fn(),
  publishPassengerBoarded: vi.fn(),
  publishPassengerDroppedOff: vi.fn(),
  publishPassengerWalkingToDestination: vi.fn(),
  publishBookingJourneyCompleted: vi.fn(),
  publishBookingNoShow: vi.fn(),
}));

const { BookingService } = await import('../../src/services/booking.service.js');
const { refundPayment } = await import('../../src/clients/payment.grpc.client.js');
const { releaseSeats } = await import('../../src/clients/route.grpc.client.js');
const { startTrackedTrip, completeTrackedTrip } = await import('../../src/clients/location.grpc.client.js');
const {
  publishBookingEmergency,
  publishBookingJourneyCompleted,
  publishBookingNoShow,
  publishDriverArrivedPickup,
  publishPassengerBoarded,
  publishPassengerDroppedOff,
  publishTripCompleted,
  publishTripStarted,
} = await import('../../src/events/booking.events.js');

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
  pickup_walking_distance: null,
  dropoff_walking_distance: null,
  pickup_walking_time: null,
  estimated_pickup_time: null,
  suggested_pickup_name: null,
  total_price: '10000',
  platform_fee: '1500',
  driver_earnings: '8500',
  status: 'confirmed' as const,
  journey_state: 'confirmed' as const,
  declined_reason: null,
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
  arrived_pickup_at: null,
  boarded_at: null,
  dropped_off_at: null,
  journey_completed_at: null,
  no_show_at: null,
  passenger_rating: null,
  driver_rating: null,
  passenger_review: null,
  driver_review: null,
  trip_id: null,
  created_at: new Date(),
  updated_at: new Date(),
};

function makeRepo() {
  return {
    findById: vi.fn(),
    cancelByPassenger: vi.fn(),
    appendEvent: vi.fn().mockResolvedValue(undefined),
    markPaymentRefunded: vi.fn(),
    markDriverArrived: vi.fn(),
    boardPassenger: vi.fn(),
    dropoffPassenger: vi.fn(),
    completeJourney: vi.fn(),
    completeLegacyTrip: vi.fn(),
    markNoShow: vi.fn(),
    submitRating: vi.fn(),
  } as const;
}

beforeEach(() => {
  vi.clearAllMocks();
  vi.mocked(startTrackedTrip).mockResolvedValue('trip-1');
});

describe('BookingService.cancelByPassengerWithRefund', () => {
  it('orchestrates refund for paid bookings before boarding', async () => {
    const repo = makeRepo();
    const cancellable = { ...baseBooking, journey_state: 'driver_arrived' as const };
    const cancelled = { ...cancellable, status: 'passenger_cancelled' as const, journey_state: 'cancelled' as const };
    repo.findById.mockResolvedValue(cancellable);
    repo.cancelByPassenger.mockResolvedValue(cancelled);
    repo.markPaymentRefunded.mockResolvedValue({ ...cancelled, payment_status: 'refunded' as const });
    vi.mocked(refundPayment).mockResolvedValue({
      refundReference: 'RF-123',
      refundedAmountTzs: 10000,
      paymentStatus: 'REFUNDED',
    });

    const svc = new BookingService(repo as never);
    const result = await svc.cancelByPassengerWithRefund('booking-1', 'passenger-1', 'PASSENGER_CANCELLED');

    expect(vi.mocked(releaseSeats)).toHaveBeenCalledWith('route-1', 'booking-1', 'PASSENGER_CANCELLED');
    expect(vi.mocked(refundPayment)).toHaveBeenCalledWith('payment-1', 'passenger-1', 'PASSENGER_CANCELLED');
    expect(repo.markPaymentRefunded).toHaveBeenCalledWith('booking-1', 'PAYMENT_SERVICE_POLICY');
    expect(result.booking.journey_state).toBe('cancelled');
    expect(result.refund.applied).toBe(true);
  });

  it('rejects passenger cancellation once the booking is in transit', async () => {
    const repo = makeRepo();
    repo.findById.mockResolvedValue({ ...baseBooking, journey_state: 'in_transit' as const, trip_id: 'trip-1' });

    const svc = new BookingService(repo as never);

    await expect(
      svc.cancelByPassengerWithRefund('booking-1', 'passenger-1', 'PASSENGER_CANCELLED'),
    ).rejects.toMatchObject({ code: 'INVALID_STATE' });

    expect(repo.cancelByPassenger).not.toHaveBeenCalled();
    expect(vi.mocked(releaseSeats)).not.toHaveBeenCalled();
    expect(vi.mocked(refundPayment)).not.toHaveBeenCalled();
  });
});

describe('BookingService journey actions', () => {
  it('marks pickup arrival for the assigned driver', async () => {
    const repo = makeRepo();
    const arrived = { ...baseBooking, journey_state: 'driver_arrived' as const, arrived_pickup_at: new Date() };
    repo.findById.mockResolvedValue(baseBooking);
    repo.markDriverArrived.mockResolvedValue(arrived);

    const svc = new BookingService(repo as never);
    const result = await svc.arrivePickup('booking-1', 'driver-1');

    expect(result.journey_state).toBe('driver_arrived');
    expect(repo.markDriverArrived).toHaveBeenCalledWith('booking-1');
    expect(vi.mocked(publishDriverArrivedPickup)).toHaveBeenCalledTimes(1);
  });

  it('boards the passenger only after pickup arrival', async () => {
    const repo = makeRepo();
    const readyToBoard = { ...baseBooking, journey_state: 'driver_arrived' as const };
    const boarded = {
      ...readyToBoard,
      journey_state: 'in_transit' as const,
      trip_id: 'trip-1',
      boarded_at: new Date(),
      trip_started_at: new Date(),
    };
    repo.findById.mockResolvedValue(readyToBoard);
    repo.boardPassenger.mockResolvedValue(boarded);

    const svc = new BookingService(repo as never);
    const result = await svc.boardPassenger('booking-1', 'driver-1');

    expect(result.journey_state).toBe('in_transit');
    expect(vi.mocked(startTrackedTrip)).toHaveBeenCalledTimes(1);
    expect(repo.boardPassenger).toHaveBeenCalledWith('booking-1', 'trip-1');
    expect(vi.mocked(publishPassengerBoarded)).toHaveBeenCalledTimes(1);
    expect(vi.mocked(publishTripStarted)).toHaveBeenCalledTimes(1);
  });

  it('fails boarding before pickup arrival and avoids creating a tracked trip', async () => {
    const repo = makeRepo();
    repo.findById.mockResolvedValue(baseBooking);

    const svc = new BookingService(repo as never);

    await expect(svc.boardPassenger('booking-1', 'driver-1')).rejects.toMatchObject({ code: 'INVALID_STATE' });

    expect(vi.mocked(startTrackedTrip)).not.toHaveBeenCalled();
    expect(repo.boardPassenger).not.toHaveBeenCalled();
  });

  it('records dropoff and moves the booking into the walking leg', async () => {
    const repo = makeRepo();
    const activeBooking = { ...baseBooking, journey_state: 'in_transit' as const, trip_id: 'trip-1' };
    const droppedOff = {
      ...activeBooking,
      journey_state: 'walking_to_destination' as const,
      dropped_off_at: new Date(),
      trip_completed_at: new Date(),
    };
    repo.findById.mockResolvedValue(activeBooking);
    repo.dropoffPassenger.mockResolvedValue(droppedOff);

    const svc = new BookingService(repo as never);
    const result = await svc.dropoffPassenger('booking-1', 'driver-1');

    expect(result.journey_state).toBe('walking_to_destination');
    expect(repo.dropoffPassenger).toHaveBeenCalledWith('booking-1');
    expect(vi.mocked(completeTrackedTrip)).toHaveBeenCalledTimes(1);
    expect(vi.mocked(publishPassengerDroppedOff)).toHaveBeenCalledTimes(1);
  });

  it('marks a no-show only after pickup arrival', async () => {
    const repo = makeRepo();
    const readyForNoShow = { ...baseBooking, journey_state: 'driver_arrived' as const };
    const noShow = {
      ...readyForNoShow,
      status: 'no_show' as const,
      journey_state: 'no_show' as const,
      no_show_at: new Date(),
    };
    repo.findById.mockResolvedValue(readyForNoShow);
    repo.markNoShow.mockResolvedValue(noShow);

    const svc = new BookingService(repo as never);
    const result = await svc.markNoShow('booking-1', 'driver-1', 'PASSENGER_ABSENT');

    expect(result.status).toBe('no_show');
    expect(repo.markNoShow).toHaveBeenCalledWith('booking-1', 'PASSENGER_ABSENT');
    expect(vi.mocked(publishBookingNoShow)).toHaveBeenCalledTimes(1);
  });

  it('rejects no-show before pickup arrival', async () => {
    const repo = makeRepo();
    repo.findById.mockResolvedValue(baseBooking);

    const svc = new BookingService(repo as never);

    await expect(svc.markNoShow('booking-1', 'driver-1', 'PASSENGER_ABSENT')).rejects.toMatchObject({ code: 'INVALID_STATE' });
    expect(repo.markNoShow).not.toHaveBeenCalled();
  });

  it('completes the journey for a booking participant', async () => {
    const repo = makeRepo();
    const walking = { ...baseBooking, journey_state: 'walking_to_destination' as const, trip_id: 'trip-1' };
    const completed = {
      ...walking,
      status: 'completed' as const,
      journey_state: 'completed' as const,
      completed_at: new Date(),
      journey_completed_at: new Date(),
    };
    repo.findById.mockResolvedValue(walking);
    repo.completeJourney.mockResolvedValue(completed);

    const svc = new BookingService(repo as never);
    const result = await svc.completeJourney('booking-1', 'passenger-1');

    expect(result.status).toBe('completed');
    expect(repo.completeJourney).toHaveBeenCalledWith('booking-1');
    expect(vi.mocked(publishBookingJourneyCompleted)).toHaveBeenCalledTimes(1);
  });
});

describe('BookingService legacy trip actions', () => {
  it('keeps startTrip as a legacy alias for boarding', async () => {
    const repo = makeRepo();
    const readyToBoard = { ...baseBooking, journey_state: 'driver_arrived' as const };
    const boarded = { ...readyToBoard, journey_state: 'in_transit' as const, trip_id: 'trip-1', boarded_at: new Date() };
    repo.findById.mockResolvedValue(readyToBoard);
    repo.boardPassenger.mockResolvedValue(boarded);

    const svc = new BookingService(repo as never);
    const result = await svc.startTrip('booking-1', 'driver-1');

    expect(result.journey_state).toBe('in_transit');
    expect(repo.boardPassenger).toHaveBeenCalledWith('booking-1', 'trip-1');
  });

  it('keeps completeTrip as a legacy compatibility close-out path', async () => {
    const repo = makeRepo();
    const activeBooking = { ...baseBooking, journey_state: 'in_transit' as const, trip_id: 'trip-1' };
    const completed = {
      ...activeBooking,
      status: 'completed' as const,
      journey_state: 'completed' as const,
      completed_at: new Date(),
      journey_completed_at: new Date(),
      trip_completed_at: new Date(),
      dropped_off_at: new Date(),
    };
    repo.findById.mockResolvedValue(activeBooking);
    repo.completeLegacyTrip.mockResolvedValue(completed);

    const svc = new BookingService(repo as never);
    const result = await svc.completeTrip('booking-1', 'driver-1');

    expect(result.status).toBe('completed');
    expect(repo.completeLegacyTrip).toHaveBeenCalledWith('booking-1');
    expect(vi.mocked(completeTrackedTrip)).toHaveBeenCalledTimes(1);
    expect(vi.mocked(publishTripCompleted)).toHaveBeenCalledTimes(1);
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
});
