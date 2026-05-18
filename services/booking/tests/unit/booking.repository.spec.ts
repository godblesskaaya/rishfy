import { describe, expect, it, vi } from 'vitest';

import { BookingRepository } from '../../src/repositories/booking.repository.js';

describe('BookingRepository.startTrip', () => {
  it('moves a confirmed booking into the in-progress state', async () => {
    const pool = {
      query: vi.fn().mockResolvedValue({
        rows: [{ id: 'booking-1', status: 'in_progress' }],
      }),
    };
    const repo = new BookingRepository(pool as never);

    const result = await repo.startTrip('booking-1');

    expect(result).toEqual({ id: 'booking-1', status: 'in_progress' });
    expect(pool.query).toHaveBeenCalledWith(
      expect.stringContaining("SET status='in_progress'"),
      ['booking-1'],
    );
    expect(pool.query).toHaveBeenCalledWith(
      expect.stringContaining("WHERE id=$1 AND status='confirmed'"),
      ['booking-1'],
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
