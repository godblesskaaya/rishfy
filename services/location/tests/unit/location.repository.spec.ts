import { describe, it, expect, vi, beforeEach } from 'vitest';
import type { Pool, QueryResult } from 'pg';
import { LocationRepository } from '../../src/repositories/location.repository.js';

function makePool(rows: unknown[] = []): Pool {
  return {
    query: vi.fn().mockResolvedValue({ rows, rowCount: rows.length } as unknown as QueryResult),
  } as unknown as Pool;
}

describe('LocationRepository.insertDriverLocation', () => {
  it('executes an INSERT without throwing', async () => {
    const pool = makePool();
    const repo = new LocationRepository(pool);
    await expect(
      repo.insertDriverLocation({
        time: new Date(),
        driverId: 'd1',
        lat: -6.7924,
        lng: 39.2083,
      }),
    ).resolves.toBeUndefined();
    expect(pool.query).toHaveBeenCalledOnce();
    const [sql, params] = (pool.query as ReturnType<typeof vi.fn>).mock.calls[0] as [string, unknown[]];
    expect(sql).toContain('INSERT INTO driver_locations');
    expect(sql).toContain('route_run_id');
    expect(params[3]).toBeNull();
  });

  it('persists route_run_id when provided', async () => {
    const pool = makePool();
    const repo = new LocationRepository(pool);
    await repo.insertDriverLocation({
      time: new Date(),
      driverId: 'd1',
      tripId: 'trip-1',
      routeRunId: 'run-1',
      lat: -6.7924,
      lng: 39.2083,
    });
    const [, params] = (pool.query as ReturnType<typeof vi.fn>).mock.calls[0] as [string, unknown[]];
    expect(params[2]).toBe('trip-1');
    expect(params[3]).toBe('run-1');
  });
});

describe('LocationRepository.getLastKnownLocation', () => {
  it('returns null when no rows', async () => {
    const pool = makePool([]);
    const repo = new LocationRepository(pool);
    const result = await repo.getLastKnownLocation('unknown');
    expect(result).toBeNull();
  });

  it('returns the first row when present', async () => {
    const row = { driverId: 'd1', routeRunId: 'run-1', lat: -6.7924, lng: 39.2083, time: new Date() };
    const pool = makePool([row]);
    const repo = new LocationRepository(pool);
    const result = await repo.getLastKnownLocation('d1');
    expect(result).toMatchObject({ lat: -6.7924, lng: 39.2083, routeRunId: 'run-1' });
  });
});

describe('LocationRepository.createTrip', () => {
  it('returns the inserted trip row', async () => {
    const trip = {
      id: 'trip-1',
      booking_id: 'booking-1',
      driver_id: 'driver-1',
      passenger_id: 'passenger-1',
      status: 'pending',
      origin_lat: -6.7924, origin_lng: 39.2083,
      destination_lat: -3.3869, destination_lng: 36.6830,
      path_encoded: null, total_distance_meters: null,
      total_duration_seconds: null, started_at: null,
      completed_at: null, cancelled_at: null,
      created_at: new Date(), updated_at: new Date(),
    };
    const pool = makePool([trip]);
    const repo = new LocationRepository(pool);
    const result = await repo.createTrip({
      bookingId: 'booking-1',
      driverId: 'driver-1',
      passengerId: 'passenger-1',
      originLat: -6.7924, originLng: 39.2083,
      destinationLat: -3.3869, destinationLng: 36.6830,
    });
    expect(result.booking_id).toBe('booking-1');
    expect(result.status).toBe('pending');
  });

  it('supports route-run-only trips without a booking', async () => {
    const trip = {
      id: 'trip-2',
      booking_id: null,
      route_id: 'route-1',
      route_run_id: 'run-1',
      driver_id: 'driver-1',
      passenger_id: null,
      status: 'pending',
      origin_lat: -6.7924, origin_lng: 39.2083,
      destination_lat: -3.3869, destination_lng: 36.6830,
      path_encoded: null, total_distance_meters: null,
      total_duration_seconds: null, started_at: null,
      completed_at: null, cancelled_at: null,
      created_at: new Date(), updated_at: new Date(),
    };
    const pool = makePool([trip]);
    const repo = new LocationRepository(pool);
    const result = await repo.createTrip({
      routeId: 'route-1',
      routeRunId: 'run-1',
      driverId: 'driver-1',
      originLat: -6.7924, originLng: 39.2083,
      destinationLat: -3.3869, destinationLng: 36.6830,
    });
    expect(result.booking_id).toBeNull();
    expect(result.route_run_id).toBe('run-1');
  });
});

describe('LocationRepository.getTripByRouteRunId', () => {
  it('queries by route_run_id', async () => {
    const trip = { id: 'trip-1', route_run_id: 'run-1' };
    const pool = makePool([trip]);
    const repo = new LocationRepository(pool);
    const result = await repo.getTripByRouteRunId('run-1');
    expect(result).toMatchObject({ id: 'trip-1', route_run_id: 'run-1' });
    const [sql, params] = (pool.query as ReturnType<typeof vi.fn>).mock.calls[0] as [string, unknown[]];
    expect(sql).toContain('route_run_id');
    expect(params).toEqual(['run-1']);
  });
});

describe('LocationRepository.startTripById', () => {
  it('returns null when trip not found or wrong state', async () => {
    const pool = makePool([]);
    const repo = new LocationRepository(pool);
    const result = await repo.startTripById('nonexistent');
    expect(result).toBeNull();
  });
});

describe('LocationRepository.completeTripById', () => {
  it('passes path_encoded and distance_meters to the query', async () => {
    const pool = makePool([]);
    const repo = new LocationRepository(pool);
    await repo.completeTripById('trip-1', 'encodedPolyline==', 12500);
    const [, params] = (pool.query as ReturnType<typeof vi.fn>).mock.calls[0] as [string, unknown[]];
    expect(params).toContain('encodedPolyline==');
    expect(params).toContain(12500);
  });
});
