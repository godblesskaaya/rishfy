import { describe, expect, it, vi } from 'vitest';

import { BookingRepository } from '../../src/repositories/booking.repository.js';

describe('BookingRepository journey transitions', () => {
  it('marks pickup arrival for a confirmed booking', async () => {
    const pool = {
      query: vi.fn().mockResolvedValue({
        rows: [{ id: 'booking-1', journey_state: 'driver_arrived' }],
      }),
    };
    const repo = new BookingRepository(pool as never);

    const result = await repo.markDriverArrived('booking-1');

    expect(result).toEqual({ id: 'booking-1', journey_state: 'driver_arrived' });
    expect(pool.query).toHaveBeenCalledWith(
      expect.stringContaining("journey_state='driver_arrived'"),
      ['booking-1'],
    );
  });

  it('boards the passenger and stores trip linkage', async () => {
    const pool = {
      query: vi.fn().mockResolvedValue({
        rows: [{ id: 'booking-1', journey_state: 'in_transit', trip_id: 'trip-1' }],
      }),
    };
    const repo = new BookingRepository(pool as never);

    const result = await repo.boardPassenger('booking-1', 'trip-1');

    expect(result).toEqual({ id: 'booking-1', journey_state: 'in_transit', trip_id: 'trip-1' });
    expect(pool.query).toHaveBeenCalledWith(
      expect.stringContaining("trip_id=COALESCE(trip_id, $2)"),
      ['booking-1', 'trip-1'],
    );
  });

  it('moves an in-transit journey into the walking leg at dropoff', async () => {
    const pool = {
      query: vi.fn().mockResolvedValue({
        rows: [{ id: 'booking-1', journey_state: 'walking_to_destination' }],
      }),
    };
    const repo = new BookingRepository(pool as never);

    const result = await repo.dropoffPassenger('booking-1');

    expect(result).toEqual({ id: 'booking-1', journey_state: 'walking_to_destination' });
    expect(pool.query).toHaveBeenCalledWith(
      expect.stringContaining("journey_state='walking_to_destination'"),
      ['booking-1'],
    );
  });

  it('closes the booking on completeJourney', async () => {
    const pool = {
      query: vi.fn().mockResolvedValue({
        rows: [{ id: 'booking-1', status: 'completed', journey_state: 'completed' }],
      }),
    };
    const repo = new BookingRepository(pool as never);

    const result = await repo.completeJourney('booking-1');

    expect(result).toEqual({ id: 'booking-1', status: 'completed', journey_state: 'completed' });
    expect(pool.query).toHaveBeenCalledWith(
      expect.stringContaining("journey_state='completed'"),
      ['booking-1'],
    );
  });

  it('marks no-show without changing unrelated bookings', async () => {
    const pool = {
      query: vi.fn().mockResolvedValue({
        rows: [{ id: 'booking-1', status: 'no_show', journey_state: 'no_show' }],
      }),
    };
    const repo = new BookingRepository(pool as never);

    const result = await repo.markNoShow('booking-1', 'PASSENGER_ABSENT');

    expect(result).toEqual({ id: 'booking-1', status: 'no_show', journey_state: 'no_show' });
    expect(pool.query).toHaveBeenCalledWith(
      expect.stringContaining("status='no_show'"),
      ['booking-1', 'PASSENGER_ABSENT'],
    );
  });
});

describe('BookingRepository.completeTrip', () => {
  it('only completes an in-progress booking', async () => {
    const pool = {
      query: vi.fn().mockResolvedValue({
        rows: [{ id: 'booking-1', status: 'completed' }],
      }),
    };
    const repo = new BookingRepository(pool as never);

    const result = await repo.completeTrip('booking-1');

    expect(result).toEqual({ id: 'booking-1', status: 'completed' });
    expect(pool.query).toHaveBeenCalledWith(
      expect.stringContaining("WHERE id=$1 AND status='in_progress'"),
      ['booking-1'],
    );
  });
});
