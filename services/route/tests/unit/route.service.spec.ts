import { describe, it, expect, vi, beforeEach } from 'vitest';

vi.mock('../../src/config.js', () => ({
  config: {
    NODE_ENV: 'test', SERVICE_NAME: 'route-service', HTTP_PORT: 8083, GRPC_PORT: 50053,
    LOG_LEVEL: 'silent', DATABASE_URL: 'postgresql://test:test@localhost/test',
    REDIS_URL: 'redis://localhost:6379', KAFKA_BROKERS: 'localhost:9092',
    GOOGLE_MAPS_API_KEY: 'test-key', USER_SERVICE_GRPC_URL: 'localhost:50052',
    BOOKING_SERVICE_GRPC_URL: 'localhost:50054',
    LOCATION_SERVICE_GRPC_URL: 'localhost:50056',
    SEARCH_RADIUS_METERS: 5000, COARSE_MATCH_RADIUS_METERS: 3000,
    ROUTE_CACHE_TTL_SECONDS: 300,
  },
  isProduction: false, isDevelopment: false, isTest: true,
}));
vi.mock('../../src/db.js', () => ({ pgPool: {}, db: {} }));

const mockGetDirections = vi.fn().mockResolvedValue({
  polyline: '_p~iF~ps|U_ulLnnqC_mqNvxq`@',
  distance_meters: 10000,
  duration_seconds: 900,
});
const mockGetWalkingDistance = vi.fn();
const mockReverseGeocode = vi.fn();
const mockListRouteBookings = vi.fn();
const mockStartTrackedRouteRun = vi.fn().mockResolvedValue('trip-1');
const mockCompleteTrackedRouteRun = vi.fn().mockResolvedValue('trip-1');

vi.mock('../../src/clients/googlemaps.client.js', () => ({
  getDirections: mockGetDirections,
  getWalkingDistance: mockGetWalkingDistance,
  reverseGeocode: mockReverseGeocode,
}));
vi.mock('../../src/clients/booking.grpc.client.js', () => ({
  listRouteBookings: mockListRouteBookings,
}));
vi.mock('../../src/clients/location.grpc.client.js', () => ({
  startTrackedRouteRun: mockStartTrackedRouteRun,
  completeTrackedRouteRun: mockCompleteTrackedRouteRun,
}));
vi.mock('../../src/clients/user.grpc.client.js', () => ({
  checkDriverEligibility: vi.fn().mockResolvedValue({ eligible: true, blockers: [] }),
  getUserProfile: vi.fn().mockResolvedValue({ firstName: 'Test', lastName: 'Driver', ratingAverage: 4.5 }),
}));

const { RouteService } = await import('../../src/services/route.service.js');
const { RouteRepository } = await import('../../src/repositories/route.repository.js');
const { AppError } = await import('../../src/utils/errors.js');

const mockRoute = {
  id: 'route-1', driver_id: 'driver-1', vehicle_id: 'vehicle-1',
  origin_name: 'Ubungo', destination_name: 'Kariakoo',
  origin_lat: -6.7924, origin_lng: 39.2083,
  destination_lat: -6.8161, destination_lng: 39.2894,
  polyline: '_p~iF~ps|U_ulLnnqC', route_geometry_geojson: null,
  distance_meters: 10000, duration_seconds: 1800,
  flexibility_minutes: 15,
  available_seats: 3, booked_seats: 0, price_per_seat: '5000',
  departure_time: new Date('2026-05-01T07:00:00Z'), status: 'active' as const,
  recurrence: 'none' as const, recurrence_days: null, recurrence_end_date: null,
  parent_route_id: null, driver_name: 'Test Driver', driver_rating: '4.5',
  vehicle_make: null, vehicle_model: null, vehicle_color: null, vehicle_plate: null,
  created_at: new Date(), updated_at: new Date(),
};

function makePool() { return { query: vi.fn(), connect: vi.fn() } as unknown as import('pg').Pool; }
function makeRedis() {
  return {
    get: vi.fn().mockResolvedValue(null),
    setex: vi.fn(),
    del: vi.fn(),
  } as unknown as import('ioredis').Redis;
}

// ─── getRoute ─────────────────────────────────────────────────────────────────

describe('RouteService.getRoute', () => {
  it('throws ROUTE_NOT_FOUND when route missing', async () => {
    const pool = makePool();
    const redis = makeRedis();
    vi.mocked(pool.query).mockResolvedValueOnce({ rows: [], rowCount: 0 } as never);
    const svc = new RouteService(pool, redis);
    await expect(svc.getRoute('nonexistent')).rejects.toThrow(AppError);
  });

  it('returns cached route without DB call', async () => {
    const pool = makePool();
    const redis = makeRedis();
    vi.mocked(redis.get).mockResolvedValueOnce(JSON.stringify(mockRoute));
    const svc = new RouteService(pool, redis);
    const result = await svc.getRoute('route-1');
    expect(result).toBeTruthy();
    expect(vi.mocked(pool.query)).not.toHaveBeenCalled();
  });
});

// ─── cancelRoute ──────────────────────────────────────────────────────────────

describe('RouteService.cancelRoute', () => {
  it('throws ROUTE_NOT_FOUND when cancel returns null', async () => {
    const pool = makePool();
    const redis = makeRedis();
    vi.mocked(pool.query).mockResolvedValueOnce({ rows: [], rowCount: 0 } as never);
    const svc = new RouteService(pool, redis);
    await expect(svc.cancelRoute('driver-1', 'bad-route')).rejects.toThrow(AppError);
  });
});

describe('RouteService.getDriverRouteOperations', () => {
  it('returns the owned route plus prioritized booking operations', async () => {
    const pool = makePool();
    const redis = makeRedis();
    vi.mocked(pool.query)
      .mockResolvedValueOnce({ rows: [mockRoute], rowCount: 1 } as never)
      .mockResolvedValueOnce({ rows: [], rowCount: 0 } as never);
    mockListRouteBookings.mockResolvedValueOnce([
      {
        booking_id: 'booking-2',
        route_id: mockRoute.id,
        passenger_user_id: 'passenger-2',
        driver_user_id: 'driver-1',
        seat_count: 1,
        pickup_address: 'Pickup B',
        dropoff_address: 'Dropoff B',
        status: 'BOOKING_STATUS_CONFIRMED',
        trip_status: 'TRIP_STATUS_SCHEDULED',
        journey_state: 'JOURNEY_STATE_CONFIRMED',
        payment_id: 'payment-2',
        trip_id: '',
      },
      {
        booking_id: 'booking-1',
        route_id: mockRoute.id,
        passenger_user_id: 'passenger-1',
        driver_user_id: 'driver-1',
        seat_count: 1,
        pickup_address: 'Pickup A',
        dropoff_address: 'Dropoff A',
        status: 'BOOKING_STATUS_CONFIRMED',
        trip_status: 'TRIP_STATUS_SCHEDULED',
        journey_state: 'JOURNEY_STATE_DRIVER_ARRIVED',
        payment_id: 'payment-1',
        trip_id: '',
      },
    ]);

    const svc = new RouteService(pool, redis);
    const result = await svc.getDriverRouteOperations('driver-1', mockRoute.id);

    expect(result.route.id).toBe(mockRoute.id);
    expect(result.bookings.map((booking) => booking.booking_id)).toEqual([
      'booking-1',
      'booking-2',
    ]);
    expect(result.active_run).toBeNull();
    expect(result.run_stops).toEqual([]);
  });

  it('reconciles persisted run stops with booking lifecycle updates', async () => {
    const pool = makePool();
    const redis = makeRedis();
    const svc = new RouteService(pool, redis);
    const run = {
      id: 'run-1',
      route_id: mockRoute.id,
      driver_id: 'driver-1',
      status: 'active' as const,
      started_at: new Date(),
      completed_at: null,
      cancelled_at: null,
      current_stop_index: 0,
      created_at: new Date(),
      updated_at: new Date(),
    };
    const persistedStops = [
      {
        id: 'stop-1',
        route_run_id: 'run-1',
        booking_id: 'booking-1',
        stop_kind: 'pickup' as const,
        sequence: 0,
        status: 'active' as const,
        stop_name: 'Pickup 1',
        created_at: new Date(),
        updated_at: new Date(),
      },
      {
        id: 'stop-2',
        route_run_id: 'run-1',
        booking_id: 'booking-1',
        stop_kind: 'dropoff' as const,
        sequence: 1,
        status: 'pending' as const,
        stop_name: 'Dropoff 1',
        created_at: new Date(),
        updated_at: new Date(),
      },
    ];
    vi.spyOn(RouteRepository.prototype, 'findById').mockResolvedValue(mockRoute);
    vi.spyOn(RouteRepository.prototype, 'findOpenRunByRoute').mockResolvedValue(run);
    vi.spyOn(RouteRepository.prototype, 'listRouteRunStops')
      .mockResolvedValueOnce(persistedStops)
      .mockResolvedValueOnce([
        { ...persistedStops[0], status: 'completed' as const },
        { ...persistedStops[1], status: 'active' as const },
      ]);
    const updateStopSpy = vi.spyOn(RouteRepository.prototype, 'updateRouteRunStopStatus').mockResolvedValue(null);
    const updateIndexSpy = vi.spyOn(RouteRepository.prototype, 'updateRouteRunCurrentStopIndex')
      .mockResolvedValue({ ...run, current_stop_index: 1 });
    mockListRouteBookings.mockResolvedValueOnce([
      {
        booking_id: 'booking-1',
        route_id: mockRoute.id,
        passenger_user_id: 'passenger-1',
        driver_user_id: 'driver-1',
        seat_count: 1,
        pickup_address: 'Pickup 1',
        dropoff_address: 'Dropoff 1',
        status: 'BOOKING_STATUS_CONFIRMED',
        trip_status: 'TRIP_STATUS_IN_PROGRESS',
        journey_state: 'JOURNEY_STATE_IN_TRANSIT',
        payment_id: 'payment-1',
        trip_id: 'trip-1',
      },
    ]);

    const result = await svc.getDriverRouteOperations('driver-1', mockRoute.id);

    expect(updateStopSpy).toHaveBeenCalledTimes(2);
    expect(updateIndexSpy).toHaveBeenCalledWith('run-1', 1);
    expect(result.run_stops).toMatchObject([
      { sequence: 0, status: 'completed' },
      { sequence: 1, status: 'active' },
    ]);
  });
});

describe('RouteService.startRouteRun', () => {
  it('creates an active run, seeds normalized stops, and returns workspace data', async () => {
    const pool = makePool();
    const redis = makeRedis();
    const svc = new RouteService(pool, redis);
    const run = {
      id: 'run-1',
      route_id: mockRoute.id,
      driver_id: 'driver-1',
      status: 'active' as const,
      started_at: new Date(),
      completed_at: null,
      cancelled_at: null,
      current_stop_index: 0,
      created_at: new Date(),
      updated_at: new Date(),
    };
    const listStopsSpy = vi.spyOn(RouteRepository.prototype, 'listRouteRunStops')
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([
        {
          id: 'stop-1',
          route_run_id: 'run-1',
          booking_id: 'booking-1',
          stop_kind: 'pickup',
          sequence: 0,
          status: 'active',
          stop_name: 'Pickup 1',
          created_at: new Date(),
          updated_at: new Date(),
        },
        {
          id: 'stop-2',
          route_run_id: 'run-1',
          booking_id: 'booking-1',
          stop_kind: 'dropoff',
          sequence: 1,
          status: 'pending',
          stop_name: 'Dropoff 1',
          created_at: new Date(),
          updated_at: new Date(),
        },
      ]);
    const replaceStopsSpy = vi.spyOn(RouteRepository.prototype, 'replaceRouteRunStops').mockResolvedValue();
    const updateIndexSpy = vi.spyOn(RouteRepository.prototype, 'updateRouteRunCurrentStopIndex').mockResolvedValue(run);
    const findByIdSpy = vi.spyOn(RouteRepository.prototype, 'findById').mockResolvedValue(mockRoute);
    const findOpenRunSpy = vi.spyOn(RouteRepository.prototype, 'findOpenRunByRoute')
      .mockResolvedValueOnce(null)
      .mockResolvedValueOnce(run);
    const createRouteRunSpy = vi.spyOn(RouteRepository.prototype, 'createRouteRun').mockResolvedValue(run);
    const routeBookings = [
      {
        booking_id: 'booking-1',
        route_id: mockRoute.id,
        passenger_user_id: 'passenger-1',
        driver_user_id: 'driver-1',
        seat_count: 1,
        pickup_address: 'Pickup 1',
        dropoff_address: 'Dropoff 1',
        status: 'BOOKING_STATUS_CONFIRMED',
        trip_status: 'TRIP_STATUS_SCHEDULED',
        journey_state: 'JOURNEY_STATE_CONFIRMED',
        payment_id: 'payment-1',
        trip_id: '',
      },
    ];
    mockListRouteBookings.mockResolvedValueOnce(routeBookings).mockResolvedValueOnce(routeBookings);

    const result = await svc.startRouteRun('driver-1', mockRoute.id);

    expect(findByIdSpy).toHaveBeenCalledWith(mockRoute.id);
    expect(createRouteRunSpy).toHaveBeenCalledWith(mockRoute.id, 'driver-1');
    expect(replaceStopsSpy).toHaveBeenCalledWith('run-1', [
      expect.objectContaining({ sequence: 0, status: 'active', stop_kind: 'pickup' }),
      expect.objectContaining({ sequence: 1, status: 'pending', stop_kind: 'dropoff' }),
    ]);
    expect(updateIndexSpy).toHaveBeenCalledWith('run-1', 0);
    expect(mockStartTrackedRouteRun).toHaveBeenCalledTimes(1);
    expect(result.active_run?.status).toBe('active');
    expect(result.run_stops[0]?.status).toBe('active');
    expect(listStopsSpy).toHaveBeenCalledWith('run-1');
  });

  it('reuses an existing open run without resetting persisted stops', async () => {
    const pool = makePool();
    const redis = makeRedis();
    const svc = new RouteService(pool, redis);
    const run = {
      id: 'run-1',
      route_id: mockRoute.id,
      driver_id: 'driver-1',
      status: 'active' as const,
      started_at: new Date(),
      completed_at: null,
      cancelled_at: null,
      current_stop_index: 1,
      created_at: new Date(),
      updated_at: new Date(),
    };
    const persistedStops = [
      {
        id: 'stop-1',
        route_run_id: 'run-1',
        booking_id: 'booking-1',
        stop_kind: 'pickup' as const,
        sequence: 0,
        status: 'completed' as const,
        stop_name: 'Pickup 1',
        created_at: new Date(),
        updated_at: new Date(),
      },
      {
        id: 'stop-2',
        route_run_id: 'run-1',
        booking_id: 'booking-1',
        stop_kind: 'dropoff' as const,
        sequence: 1,
        status: 'active' as const,
        stop_name: 'Dropoff 1',
        created_at: new Date(),
        updated_at: new Date(),
      },
    ];
    vi.spyOn(RouteRepository.prototype, 'findById').mockResolvedValue(mockRoute);
    vi.spyOn(RouteRepository.prototype, 'findOpenRunByRoute').mockResolvedValue(run);
    const listStopsSpy = vi.spyOn(RouteRepository.prototype, 'listRouteRunStops').mockResolvedValue(persistedStops);
    const replaceStopsSpy = vi.spyOn(RouteRepository.prototype, 'replaceRouteRunStops').mockResolvedValue();
    const createRouteRunSpy = vi.spyOn(RouteRepository.prototype, 'createRouteRun').mockResolvedValue(run);
    mockListRouteBookings.mockReset();
    mockListRouteBookings
      .mockResolvedValueOnce([
        {
          booking_id: 'booking-1',
          route_id: mockRoute.id,
          passenger_user_id: 'passenger-1',
          driver_user_id: 'driver-1',
          seat_count: 1,
          pickup_address: 'Pickup 1',
          dropoff_address: 'Dropoff 1',
          status: 'BOOKING_STATUS_CONFIRMED',
          trip_status: 'TRIP_STATUS_IN_PROGRESS',
          journey_state: 'JOURNEY_STATE_IN_TRANSIT',
          payment_id: 'payment-1',
          trip_id: 'trip-1',
        },
      ])
      .mockResolvedValueOnce([
        {
          booking_id: 'booking-1',
          route_id: mockRoute.id,
          passenger_user_id: 'passenger-1',
          driver_user_id: 'driver-1',
          seat_count: 1,
          pickup_address: 'Pickup 1',
          dropoff_address: 'Dropoff 1',
          status: 'BOOKING_STATUS_CONFIRMED',
          trip_status: 'TRIP_STATUS_IN_PROGRESS',
          journey_state: 'JOURNEY_STATE_IN_TRANSIT',
          payment_id: 'payment-1',
          trip_id: 'trip-1',
        },
      ]);
    mockStartTrackedRouteRun.mockClear();

    const result = await svc.startRouteRun('driver-1', mockRoute.id);

    expect(createRouteRunSpy).not.toHaveBeenCalled();
    expect(replaceStopsSpy).not.toHaveBeenCalled();
    expect(mockStartTrackedRouteRun).not.toHaveBeenCalled();
    expect(listStopsSpy).toHaveBeenCalledWith('run-1');
    expect(result.run_stops[1]?.status).toBe('active');
  });
});

describe('RouteService route-run progression', () => {
  it('advances the next actionable stop to active', async () => {
    const pool = makePool();
    const redis = makeRedis();
    const svc = new RouteService(pool, redis);
    const workspace = {
      route: mockRoute,
      active_run: {
        id: 'run-1',
        route_id: mockRoute.id,
        driver_id: 'driver-1',
        status: 'active' as const,
        started_at: new Date(),
        completed_at: null,
        cancelled_at: null,
        current_stop_index: 1,
        created_at: new Date(),
        updated_at: new Date(),
      },
      run_stops: [
        {
          id: 'stop-2',
          route_run_id: 'run-1',
          booking_id: 'booking-1',
          stop_kind: 'dropoff' as const,
          sequence: 1,
          status: 'active' as const,
          stop_name: 'Dropoff 1',
          created_at: new Date(),
          updated_at: new Date(),
        },
      ],
      bookings: [],
    };
    vi.spyOn(svc, 'getDriverRouteOperations').mockResolvedValue(workspace);
    const run = {
      id: 'run-1',
      route_id: mockRoute.id,
      driver_id: 'driver-1',
      status: 'active' as const,
      started_at: new Date(),
      completed_at: null,
      cancelled_at: null,
      current_stop_index: 1,
      created_at: new Date(),
      updated_at: new Date(),
    };
    const pendingStops = [
      {
        id: 'stop-1',
        route_run_id: 'run-1',
        booking_id: 'booking-1',
        stop_kind: 'pickup' as const,
        sequence: 0,
        status: 'completed' as const,
        stop_name: 'Pickup 1',
        created_at: new Date(),
        updated_at: new Date(),
      },
      {
        id: 'stop-2',
        route_run_id: 'run-1',
        booking_id: 'booking-1',
        stop_kind: 'dropoff' as const,
        sequence: 1,
        status: 'active' as const,
        stop_name: 'Dropoff 1',
        created_at: new Date(),
        updated_at: new Date(),
      },
    ];
    vi.spyOn(RouteRepository.prototype, 'findById').mockResolvedValue(mockRoute);
    vi.spyOn(RouteRepository.prototype, 'findOpenRunByRoute').mockResolvedValue(run);
    vi.spyOn(RouteRepository.prototype, 'listRouteRunStops').mockResolvedValue(pendingStops);
    const clearActiveSpy = vi.spyOn(RouteRepository.prototype, 'clearActiveRouteRunStops').mockResolvedValue();
    const setStatusSpy = vi.spyOn(RouteRepository.prototype, 'setRouteRunStopStatus')
      .mockResolvedValue({ ...pendingStops[1], status: 'active' });
    const updateIndexSpy = vi.spyOn(RouteRepository.prototype, 'updateRouteRunCurrentStopIndex').mockResolvedValue(run);
    mockListRouteBookings
      .mockResolvedValueOnce([
        {
          booking_id: 'booking-1',
          route_id: mockRoute.id,
          passenger_user_id: 'passenger-1',
          driver_user_id: 'driver-1',
          seat_count: 1,
          pickup_address: 'Pickup 1',
          dropoff_address: 'Dropoff 1',
          status: 'BOOKING_STATUS_CONFIRMED',
          trip_status: 'TRIP_STATUS_IN_PROGRESS',
          journey_state: 'JOURNEY_STATE_IN_TRANSIT',
          payment_id: 'payment-1',
          trip_id: 'trip-1',
        },
      ])
      .mockResolvedValueOnce([
        {
          booking_id: 'booking-1',
          route_id: mockRoute.id,
          passenger_user_id: 'passenger-1',
          driver_user_id: 'driver-1',
          seat_count: 1,
          pickup_address: 'Pickup 1',
          dropoff_address: 'Dropoff 1',
          status: 'BOOKING_STATUS_CONFIRMED',
          trip_status: 'TRIP_STATUS_IN_PROGRESS',
          journey_state: 'JOURNEY_STATE_IN_TRANSIT',
          payment_id: 'payment-1',
          trip_id: 'trip-1',
        },
      ]);

    const result = await svc.advanceRouteRun('driver-1', mockRoute.id);

    expect(clearActiveSpy).not.toHaveBeenCalled();
    expect(setStatusSpy).not.toHaveBeenCalled();
    expect(updateIndexSpy).not.toHaveBeenCalled();
    expect(result.run_stops[0]?.status).toBe('active');
  });

  it('completes the current stop and auto-completes the run when no further stops remain', async () => {
    const pool = makePool();
    const redis = makeRedis();
    const svc = new RouteService(pool, redis);
    vi.spyOn(svc, 'getDriverRouteOperations').mockResolvedValue({
      route: mockRoute,
      active_run: null,
      run_stops: [],
      bookings: [],
    });
    const run = {
      id: 'run-1',
      route_id: mockRoute.id,
      driver_id: 'driver-1',
      status: 'active' as const,
      started_at: new Date(),
      completed_at: null,
      cancelled_at: null,
      current_stop_index: 1,
      created_at: new Date(),
      updated_at: new Date(),
    };
    const completedRun = {
      ...run,
      status: 'completed' as const,
      completed_at: new Date(),
    };
    const activeStops = [
      {
        id: 'stop-1',
        route_run_id: 'run-1',
        booking_id: 'booking-1',
        stop_kind: 'pickup' as const,
        sequence: 0,
        status: 'completed' as const,
        stop_name: 'Pickup 1',
        created_at: new Date(),
        updated_at: new Date(),
      },
      {
        id: 'stop-2',
        route_run_id: 'run-1',
        booking_id: 'booking-1',
        stop_kind: 'dropoff' as const,
        sequence: 1,
        status: 'active' as const,
        stop_name: 'Dropoff 1',
        created_at: new Date(),
        updated_at: new Date(),
      },
    ];
    vi.spyOn(RouteRepository.prototype, 'findById').mockResolvedValue(mockRoute);
    vi.spyOn(RouteRepository.prototype, 'findOpenRunByRoute')
      .mockResolvedValue(run);
    vi.spyOn(RouteRepository.prototype, 'listRouteRunStops').mockResolvedValue(activeStops);
    const setStatusSpy = vi.spyOn(RouteRepository.prototype, 'setRouteRunStopStatus')
      .mockResolvedValue({ ...activeStops[1], status: 'completed' });
    const updateIndexSpy = vi.spyOn(RouteRepository.prototype, 'updateRouteRunCurrentStopIndex').mockResolvedValue(run);
    const completeRunSpy = vi.spyOn(RouteRepository.prototype, 'completeRouteRun').mockResolvedValue(completedRun);
    const completeRouteSpy = vi.spyOn(RouteRepository.prototype, 'completeRoute').mockResolvedValue({
      ...mockRoute,
      status: 'completed',
    });
    mockCompleteTrackedRouteRun.mockClear();
    mockListRouteBookings.mockResolvedValueOnce([
      {
        booking_id: 'booking-1',
        route_id: mockRoute.id,
        passenger_user_id: 'passenger-1',
        driver_user_id: 'driver-1',
        seat_count: 1,
        pickup_address: 'Pickup 1',
        dropoff_address: 'Dropoff 1',
        status: 'BOOKING_STATUS_COMPLETED',
        trip_status: 'TRIP_STATUS_COMPLETED',
        journey_state: 'JOURNEY_STATE_COMPLETED',
        payment_id: 'payment-1',
        trip_id: 'trip-1',
      },
    ]);
    const result = await svc.completeCurrentRouteRunStop('driver-1', mockRoute.id);

    expect(setStatusSpy).toHaveBeenCalledWith('run-1', 1, 'completed');
    expect(updateIndexSpy).toHaveBeenCalledWith('run-1', 2);
    expect(mockCompleteTrackedRouteRun).toHaveBeenCalledWith({
      routeRunId: 'run-1',
      endLat: mockRoute.destination_lat,
      endLng: mockRoute.destination_lng,
    });
    expect(completeRunSpy).toHaveBeenCalledWith(mockRoute.id, 'driver-1');
    expect(completeRouteSpy).toHaveBeenCalledWith(mockRoute.id, 'driver-1');
    expect(result.active_run).toBeNull();
  });

  it('rejects manual route-run completion while stops are still open', async () => {
    const pool = makePool();
    const redis = makeRedis();
    const svc = new RouteService(pool, redis);
    const run = {
      id: 'run-1',
      route_id: mockRoute.id,
      driver_id: 'driver-1',
      status: 'active' as const,
      started_at: new Date(),
      completed_at: null,
      cancelled_at: null,
      current_stop_index: 1,
      created_at: new Date(),
      updated_at: new Date(),
    };
    const openStops = [
      {
        id: 'stop-1',
        route_run_id: 'run-1',
        booking_id: 'booking-1',
        stop_kind: 'pickup' as const,
        sequence: 0,
        status: 'completed' as const,
        stop_name: 'Pickup 1',
        created_at: new Date(),
        updated_at: new Date(),
      },
      {
        id: 'stop-2',
        route_run_id: 'run-1',
        booking_id: 'booking-1',
        stop_kind: 'dropoff' as const,
        sequence: 1,
        status: 'active' as const,
        stop_name: 'Dropoff 1',
        created_at: new Date(),
        updated_at: new Date(),
      },
    ];
    vi.spyOn(RouteRepository.prototype, 'findById').mockResolvedValue(mockRoute);
    vi.spyOn(RouteRepository.prototype, 'findOpenRunByRoute').mockResolvedValue(run);
    vi.spyOn(RouteRepository.prototype, 'listRouteRunStops').mockResolvedValue(openStops);
    mockListRouteBookings.mockResolvedValueOnce([]);

    await expect(svc.completeRouteRun('driver-1', mockRoute.id)).rejects.toThrow(AppError);
  });
});

// ─── previewRoute ─────────────────────────────────────────────────────────────

describe('RouteService.previewRoute', () => {
  it('returns polyline and GeoJSON linestring without DB write', async () => {
    const pool = makePool();
    const redis = makeRedis();
    const svc = new RouteService(pool, redis);

    const result = await svc.previewRoute({
      origin_lat: -6.7924, origin_lng: 39.2083,
      destination_lat: -6.8161, destination_lng: 39.2894,
    });

    expect(result.polyline).toBeTruthy();
    expect(result.geojson_linestring.type).toBe('LineString');
    expect(Array.isArray(result.geojson_linestring.coordinates)).toBe(true);
    expect(result.distance_meters).toBe(10000);
    expect(result.duration_seconds).toBe(900);
    expect(vi.mocked(pool.query)).not.toHaveBeenCalled();
  });

  it('passes waypoints to getDirections', async () => {
    const pool = makePool();
    const redis = makeRedis();
    const svc = new RouteService(pool, redis);
    const waypoints = [{ lat: -6.8, lng: 39.25 }];

    await svc.previewRoute({
      origin_lat: -6.7924, origin_lng: 39.2083,
      destination_lat: -6.8161, destination_lng: 39.2894,
      waypoints,
    });

    expect(mockGetDirections).toHaveBeenCalledWith(
      { lat: -6.7924, lng: 39.2083 },
      { lat: -6.8161, lng: 39.2894 },
      waypoints,
    );
  });

  it('throws DIRECTIONS_UNAVAILABLE when routing API fails', async () => {
    mockGetDirections.mockResolvedValueOnce(null);
    const pool = makePool();
    const redis = makeRedis();
    const svc = new RouteService(pool, redis);

    await expect(svc.previewRoute({
      origin_lat: -6.7924, origin_lng: 39.2083,
      destination_lat: -6.8161, destination_lng: 39.2894,
    })).rejects.toThrow(AppError);
  });
});

// ─── searchRoutes — Stage 3 temporal filter ───────────────────────────────────

describe('RouteService.searchRoutes — Stage 3 temporal filter', () => {
  const desiredTime = new Date('2026-05-01T07:00:00Z');

  // candidate whose estimated pickup time is 30 minutes before desired (within 30+15 = 45 min window)
  const withinWindow = {
    ...mockRoute,
    pickup_fraction: 0.1,   // 10% along route, 1800s * 0.1 = 180s from departure
    dropoff_fraction: 0.8,
    closest_pickup_geojson: '{"type":"Point","coordinates":[39.22,-6.795]}',
    closest_dropoff_geojson: '{"type":"Point","coordinates":[39.28,-6.81]}',
    // departure_time = 07:00, pickup_fraction=0.1, duration=1800 → pickup at 07:03
  };

  // candidate whose estimated pickup time is 2 hours off (outside window)
  const outsideWindow = {
    ...mockRoute,
    id: 'route-2',
    departure_time: new Date('2026-05-01T05:00:00Z'), // 2 hours early
    pickup_fraction: 0.1,
    dropoff_fraction: 0.8,
    closest_pickup_geojson: '{"type":"Point","coordinates":[39.22,-6.795]}',
    closest_dropoff_geojson: '{"type":"Point","coordinates":[39.28,-6.81]}',
  };

  beforeEach(() => {
    mockGetWalkingDistance.mockResolvedValue({ distance_meters: 400, duration_seconds: 300 });
    mockReverseGeocode.mockResolvedValue('Ubungo Bus Stand');
  });

  it('filters out candidates outside combined flexibility window', async () => {
    const pool = makePool();
    const redis = makeRedis();
    vi.mocked(pool.query).mockResolvedValueOnce({ rows: [withinWindow, outsideWindow] } as never);

    const svc = new RouteService(pool, redis);
    const results = await svc.searchRoutes({
      pickup_lat: -6.795, pickup_lng: 39.22,
      dropoff_lat: -6.81, dropoff_lng: 39.28,
      desired_departure_time: desiredTime,
      time_flexibility_minutes: 30,
    });

    // Only withinWindow should survive
    expect(results.length).toBe(1);
    expect(results[0]?.route_id).toBe('route-1');
  });

  it('keeps candidates slightly outside the preferred time window with tradeoff metadata', async () => {
    const nearOutsideWindow = {
      ...mockRoute,
      id: 'route-near-time',
      departure_time: new Date('2026-05-01T06:10:00Z'),
      pickup_fraction: 0.1,
      dropoff_fraction: 0.8,
      closest_pickup_geojson: '{"type":"Point","coordinates":[39.22,-6.795]}',
      closest_dropoff_geojson: '{"type":"Point","coordinates":[39.28,-6.81]}',
    };

    const pool = makePool();
    const redis = makeRedis();
    vi.mocked(pool.query).mockResolvedValueOnce({ rows: [nearOutsideWindow] } as never);

    const svc = new RouteService(pool, redis);
    const results = await svc.searchRoutes({
      pickup_lat: -6.795, pickup_lng: 39.22,
      dropoff_lat: -6.81, dropoff_lng: 39.28,
      desired_departure_time: desiredTime,
      time_flexibility_minutes: 30,
    });

    expect(results).toHaveLength(1);
    expect(results[0]?.route_id).toBe('route-near-time');
    expect(results[0]?.time_exceeds_preference).toBe(true);
    expect(results[0]?.time_overage_minutes).toBe(17);
  });
});

// ─── searchRoutes — Stage 4 walking distance cache ───────────────────────────

describe('RouteService.searchRoutes — Stage 4 walking distance cache', () => {
  const candidate = {
    ...mockRoute,
    pickup_fraction: 0.1,
    dropoff_fraction: 0.8,
    closest_pickup_geojson: '{"type":"Point","coordinates":[39.22,-6.795]}',
    closest_dropoff_geojson: '{"type":"Point","coordinates":[39.28,-6.81]}',
  };

  it('uses Redis cache on second search — does not call walking API again', async () => {
    const futureTime = new Date(Date.now() + 3600_000);
    const futureCandidate = {
      ...candidate,
      departure_time: futureTime,
      closest_pickup_geojson: '{"type":"Point","coordinates":[39.215,-6.793]}',
      closest_dropoff_geojson: '{"type":"Point","coordinates":[39.285,-6.808]}',
    };

    const pool = makePool();
    const cachedWalk = JSON.stringify({ distance_meters: 350, duration_seconds: 260 });

    // Key-based mock: walk: keys return cached values; everything else returns null
    const redis = {
      get: vi.fn().mockImplementation((key: string) =>
        Promise.resolve(key.startsWith('walk:') ? cachedWalk : null),
      ),
      setex: vi.fn(),
      del: vi.fn(),
    } as unknown as import('ioredis').Redis;

    vi.mocked(pool.query).mockResolvedValueOnce({ rows: [futureCandidate] } as never);
    mockReverseGeocode.mockResolvedValue('Ubungo');
    mockGetWalkingDistance.mockClear();

    const svc = new RouteService(pool, redis);
    await svc.searchRoutes({
      pickup_lat: -6.795, pickup_lng: 39.22,
      dropoff_lat: -6.81, dropoff_lng: 39.28,
      desired_departure_time: futureTime,
    });

    expect(mockGetWalkingDistance).not.toHaveBeenCalled();
  });

  it('keeps candidates slightly outside preferred walking distance with tradeoff metadata', async () => {
    const futureTime = new Date(Date.now() + 3600_000);
    const futureCandidate = {
      ...candidate,
      departure_time: futureTime,
      closest_pickup_geojson: '{"type":"Point","coordinates":[39.215,-6.793]}',
      closest_dropoff_geojson: '{"type":"Point","coordinates":[39.285,-6.808]}',
    };

    const pool = makePool();
    const redis = makeRedis();
    vi.mocked(pool.query).mockResolvedValueOnce({ rows: [futureCandidate] } as never);

    mockGetWalkingDistance.mockResolvedValue({ distance_meters: 1500, duration_seconds: 1200 });

    const svc = new RouteService(pool, redis);
    const results = await svc.searchRoutes({
      pickup_lat: -6.795, pickup_lng: 39.22,
      dropoff_lat: -6.81, dropoff_lng: 39.28,
      max_walking_distance_meters: 1000,
      desired_departure_time: futureTime,
    });

    expect(results).toHaveLength(1);
    expect(results[0]?.walking_exceeds_preference).toBe(true);
    expect(results[0]?.walking_overage_meters).toBe(1000);
    expect(results[0]?.match_quality).toBe('flexible');
  });

  it('discards candidates outside the expanded walking limit', async () => {
    const futureTime = new Date(Date.now() + 3600_000);
    const futureCandidate = {
      ...candidate,
      departure_time: futureTime,
      closest_pickup_geojson: '{"type":"Point","coordinates":[39.215,-6.793]}',
      closest_dropoff_geojson: '{"type":"Point","coordinates":[39.285,-6.808]}',
    };

    const pool = makePool();
    const redis = makeRedis();
    vi.mocked(pool.query).mockResolvedValueOnce({ rows: [futureCandidate] } as never);

    mockGetWalkingDistance.mockResolvedValue({ distance_meters: 1800, duration_seconds: 1200 });

    const svc = new RouteService(pool, redis);
    const results = await svc.searchRoutes({
      pickup_lat: -6.795, pickup_lng: 39.22,
      dropoff_lat: -6.81, dropoff_lng: 39.28,
      max_walking_distance_meters: 1000,
      desired_departure_time: futureTime,
    });

    expect(results).toHaveLength(0);
  });
});

// ─── searchRoutes — Stage 5 ranking ──────────────────────────────────────────

describe('RouteService.searchRoutes — Stage 5 ranking', () => {
  it('returns results sorted by passenger tradeoff score', async () => {
    const futureTime = new Date(Date.now() + 3600_000);
    const base = {
      ...mockRoute,
      departure_time: futureTime,
      pickup_fraction: 0.1,
      dropoff_fraction: 0.8,
      closest_pickup_geojson: '{"type":"Point","coordinates":[39.215,-6.793]}',
      closest_dropoff_geojson: '{"type":"Point","coordinates":[39.285,-6.808]}',
    };
    const closer  = { ...base, id: 'route-close' };
    const farther = { ...base, id: 'route-far'   };

    const pool = makePool();
    const redis = makeRedis();
    vi.mocked(pool.query).mockResolvedValueOnce({ rows: [farther, closer] } as never);

    let call = 0;
    mockGetWalkingDistance.mockImplementation(() => {
      call++;
      // First two calls are for farther's pickup+dropoff, next two for closer's
      if (call === 1) return Promise.resolve({ distance_meters: 900, duration_seconds: 700 });
      if (call === 2) return Promise.resolve({ distance_meters: 300, duration_seconds: 220 });
      if (call === 3) return Promise.resolve({ distance_meters: 200, duration_seconds: 150 });
      return Promise.resolve({ distance_meters: 100, duration_seconds: 80 });
    });
    mockReverseGeocode.mockResolvedValue('Some street');

    const svc = new RouteService(pool, redis);
    const results = await svc.searchRoutes({
      pickup_lat: -6.795, pickup_lng: 39.22,
      dropoff_lat: -6.81, dropoff_lng: 39.28,
      max_walking_distance_meters: 1000,
      desired_departure_time: futureTime,
    });

    expect(results[0]?.route_id).toBe('route-close');
    expect(results[1]?.route_id).toBe('route-far');
    expect(results[0]!.match_score).toBeGreaterThan(results[1]!.match_score);
    expect(results[0]!.walking_distance_to_pickup).toBeLessThan(results[1]!.walking_distance_to_pickup);
  });
});
