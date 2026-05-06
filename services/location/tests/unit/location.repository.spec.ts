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
    const [sql] = (pool.query as ReturnType<typeof vi.fn>).mock.calls[0] as [string];
    expect(sql).toContain('INSERT INTO driver_locations');
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
    const row = { driverId: 'd1', lat: -6.7924, lng: 39.2083, time: new Date() };
    const pool = makePool([row]);
    const repo = new LocationRepository(pool);
    const result = await repo.getLastKnownLocation('d1');
    expect(result).toMatchObject({ lat: -6.7924, lng: 39.2083 });
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
});

describe('LocationRepository.startTrip', () => {
  it('returns null when booking not found or wrong state', async () => {
    const pool = makePool([]);
    const repo = new LocationRepository(pool);
    const result = await repo.startTrip('nonexistent');
    expect(result).toBeNull();
  });
});

describe('LocationRepository.completeTrip', () => {
  it('passes path_encoded and distance_meters to the query', async () => {
    const pool = makePool([]);
    const repo = new LocationRepository(pool);
    await repo.completeTrip('booking-1', 'encodedPolyline==', 12500);
    const [, params] = (pool.query as ReturnType<typeof vi.fn>).mock.calls[0] as [string, unknown[]];
    expect(params).toContain('encodedPolyline==');
    expect(params).toContain(12500);
  });
});
