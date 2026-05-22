import { describe, expect, it } from 'vitest';
import {
  calculatePathDistanceMeters,
  deriveTripLiveState,
  encodePolyline,
  estimateEtaSeconds,
} from '../../src/services/live-trip.service.js';
import type { DriverLocationPoint, TripRow } from '../../src/repositories/location.repository.js';

function makeTrip(overrides: Partial<TripRow> = {}): TripRow {
  return {
    id: 'trip-1',
    booking_id: 'booking-1',
    driver_id: 'driver-1',
    passenger_id: 'passenger-1',
    status: 'in_progress',
    origin_lat: -6.7924,
    origin_lng: 39.2083,
    destination_lat: -6.8005,
    destination_lng: 39.2550,
    path_encoded: null,
    total_distance_meters: null,
    total_duration_seconds: null,
    started_at: new Date('2026-01-01T08:00:00.000Z'),
    completed_at: null,
    cancelled_at: null,
    created_at: new Date('2026-01-01T07:55:00.000Z'),
    updated_at: new Date('2026-01-01T08:00:00.000Z'),
    ...overrides,
  };
}

describe('estimateEtaSeconds', () => {
  it('uses reported speed when available', () => {
    const eta = estimateEtaSeconds(300, 36);
    expect(eta.source).toBe('reported_speed');
    expect(eta.seconds).toBe(30);
  });

  it('falls back to default speed when vehicle speed is missing', () => {
    const eta = estimateEtaSeconds(300, null);
    expect(eta.source).toBe('fallback_speed');
    expect(eta.seconds).toBeGreaterThan(30);
  });
});

describe('deriveTripLiveState', () => {
  it('targets pickup before arrival', () => {
    const state = deriveTripLiveState(
      makeTrip(),
      { lat: -6.7900, lng: 39.2083, speedKmh: 18 },
      100,
    );
    expect(state.activeStopType).toBe('pickup');
    expect(state.proximityState).toMatch(/pickup/);
    expect(state.etaSeconds).toBeGreaterThan(0);
    expect(state.activeStopRouteFraction).toBe(0);
    expect(state.routeGeometrySource).toBe('trip_endpoints_linear_fallback');
  });

  it('switches to dropoff after pickup arrival', () => {
    const state = deriveTripLiveState(
      makeTrip(),
      { lat: -6.7924, lng: 39.2083, speedKmh: 18 },
      100,
    );
    expect(state.activeStopType).toBe('dropoff');
    expect(state.proximityState).toMatch(/dropoff/);
    expect(state.currentRouteFraction).toBeGreaterThanOrEqual(0);
    expect(state.activeStopRouteFraction).toBe(1);
    expect(state.remainingRouteFraction).toBeGreaterThanOrEqual(0);
  });

  it('marks completed trips as completed', () => {
    const state = deriveTripLiveState(
      makeTrip({ status: 'completed' }),
      { lat: -6.8005, lng: 39.2550, speedKmh: 0 },
      100,
    );
    expect(state.proximityState).toBe('trip_completed');
    expect(state.etaSeconds).toBe(0);
  });
});

describe('calculatePathDistanceMeters', () => {
  it('sums segment distance for a trace', () => {
    const points: DriverLocationPoint[] = [
      { time: new Date(), driverId: 'driver-1', tripId: 'trip-1', lat: -6.7924, lng: 39.2083 },
      { time: new Date(), driverId: 'driver-1', tripId: 'trip-1', lat: -6.7933, lng: 39.2083 },
    ];
    const distance = calculatePathDistanceMeters(points);
    expect(distance).toBeGreaterThan(85);
    expect(distance).toBeLessThan(115);
  });
});

describe('encodePolyline', () => {
  it('returns a deterministic polyline string', () => {
    const polyline = encodePolyline([
      { lat: 38.5, lng: -120.2 },
      { lat: 40.7, lng: -120.95 },
      { lat: 43.252, lng: -126.453 },
    ]);
    expect(polyline).toBe('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
  });
});
