import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { BookingRepository } from '../../src/repositories/booking.repository.js';

const {
  getDriverComplianceProfileMock,
  getVehicleComplianceRecordMock,
  getRouteComplianceSnapshotMock,
  getTrackedTripSnapshotMock,
} = vi.hoisted(() => ({
  getDriverComplianceProfileMock: vi.fn(),
  getVehicleComplianceRecordMock: vi.fn(),
  getRouteComplianceSnapshotMock: vi.fn(),
  getTrackedTripSnapshotMock: vi.fn(),
}));

vi.mock('../../src/clients/user.grpc.client.js', () => ({
  getDriverComplianceProfile: getDriverComplianceProfileMock,
  getVehicleComplianceRecord: getVehicleComplianceRecordMock,
}));

vi.mock('../../src/clients/route.grpc.client.js', () => ({
  getRouteComplianceSnapshot: getRouteComplianceSnapshotMock,
}));

vi.mock('../../src/clients/location.grpc.client.js', () => ({
  getTrackedTripSnapshot: getTrackedTripSnapshotMock,
}));

const { LatraComplianceService } = await import('../../src/services/latra.service.js');

function makeRepo(overrides: Partial<BookingRepository> = {}): BookingRepository {
  return {
    listCompletedTripsForLatraReport: vi.fn().mockResolvedValue([
      {
        booking_id: 'booking-1',
        trip_id: 'trip-1',
        route_id: 'route-1',
        passenger_id: 'passenger-1',
        driver_id: 'driver-1',
        pickup_lat: -6.8,
        pickup_lng: 39.2,
        dropoff_lat: -6.7,
        dropoff_lng: 39.3,
        pickup_point_lat: null,
        pickup_point_lng: null,
        dropoff_point_lat: null,
        dropoff_point_lng: null,
        trip_started_at: new Date('2026-06-01T08:00:00.000Z'),
        trip_completed_at: new Date('2026-06-01T08:30:00.000Z'),
        completed_at: new Date('2026-06-01T08:31:00.000Z'),
        journey_completed_at: null,
        total_price: '5000',
        driver_earnings: '4250',
        passenger_rating: 5,
        driver_rating: null,
        created_at: new Date('2026-06-01T07:55:00.000Z'),
      },
    ]),
    getLatraComplianceStats: vi.fn(),
    ...overrides,
  } as unknown as BookingRepository;
}

describe('LatraComplianceService', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    getDriverComplianceProfileMock.mockResolvedValue({
      licenseNumber: 'DL-123',
      vehicles: [
        { vehicleId: 'fallback-vehicle', registrationNumber: 'T111ABC', latraVerified: true },
      ],
    });
    getRouteComplianceSnapshotMock.mockResolvedValue({
      routeId: 'route-1',
      driverUserId: 'driver-1',
      vehicleId: 'route-vehicle',
      distanceMeters: 12345,
    });
    getVehicleComplianceRecordMock.mockResolvedValue({
      vehicleId: 'route-vehicle',
      registrationNumber: 'T999XYZ',
      latraVerified: true,
    });
    getTrackedTripSnapshotMock.mockResolvedValue({
      distanceMeters: 9876,
      durationSeconds: 1800,
      locationPointsRecorded: 12,
    });
  });

  it('uses the route vehicle and tracked trip distance for LATRA reports', async () => {
    const service = new LatraComplianceService(makeRepo());

    const result = await service.listTrips({
      startDate: '2026-06-01',
      endDate: '2026-06-30',
    });

    expect(result.summary).toEqual({ total: 1, complete: 1, incomplete: 0 });
    expect(result.trips[0]).toMatchObject({
      trip_id: 'trip-1',
      trip_distance: 9876,
      driver_license_number: 'DL-123',
      vehicle_registration: 'T999XYZ',
      validation_status: 'complete',
      missing_fields: [],
    });
    expect(result.trips[0]!.warnings).not.toContain('vehicle_registration_fell_back_to_driver_profile');
    expect(getVehicleComplianceRecordMock).toHaveBeenCalledWith('route-vehicle');
    expect(getTrackedTripSnapshotMock).toHaveBeenCalledWith('trip-1');
  });

  it('falls back to driver vehicle with visible warnings when route snapshot is unavailable', async () => {
    getRouteComplianceSnapshotMock.mockResolvedValue(null);
    getVehicleComplianceRecordMock.mockResolvedValue(null);
    getTrackedTripSnapshotMock.mockResolvedValue(null);
    const service = new LatraComplianceService(makeRepo());

    const result = await service.listTrips({
      startDate: '2026-06-01',
      endDate: '2026-06-30',
    });

    expect(result.trips[0]).toMatchObject({
      vehicle_registration: 'T111ABC',
      validation_status: 'complete',
    });
    expect(result.trips[0]!.warnings).toEqual(
      expect.arrayContaining([
        'route_snapshot_unavailable',
        'vehicle_registration_fell_back_to_driver_profile',
        'trip_distance_calculated_from_pickup_dropoff_coordinates',
      ]),
    );
  });
});
