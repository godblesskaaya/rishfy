import { describe, expect, it, vi } from 'vitest';
import { UserRepository } from '../../src/repositories/user.repository.js';

function makePool() {
  return { query: vi.fn() } as unknown as import('pg').Pool;
}

function makeTransactionalPool() {
  const client = {
    query: vi.fn(),
    release: vi.fn(),
  };
  const pool = {
    connect: vi.fn().mockResolvedValue(client),
    query: vi.fn(),
  } as unknown as import('pg').Pool;
  return { pool, client };
}

const row = {
  id: 'user-1',
  phone_number: '+255700000001',
  full_name: 'User One',
  email: 'user1@rishfy.test',
  role: 'passenger',
  status: 'active',
  profile_picture_url: null,
  average_rating: '5.00',
  total_ratings: 1,
  created_at: new Date(),
  updated_at: new Date(),
};

describe('UserRepository.upsertFromRegistration', () => {
  it('runs idempotent upsert with role/status guardrails', async () => {
    const pool = makePool();
    const row = {
      id: 'user-1',
      phone_number: '+255700000001',
      full_name: 'User One',
      email: 'user1@rishfy.test',
      role: 'passenger',
      status: 'active',
      profile_picture_url: null,
      average_rating: '0.00',
      total_ratings: 0,
      created_at: new Date(),
      updated_at: new Date(),
    };
    vi.mocked(pool.query).mockResolvedValueOnce({ rows: [row], rowCount: 1 } as never);

    const repo = new UserRepository(pool);
    const result = await repo.upsertFromRegistration({
      id: 'user-1',
      auth_id: 'auth-1',
      phone_number: '+255700000001',
      full_name: 'User One',
      email: 'user1@rishfy.test',
      role: 'passenger',
      status: 'active',
    });

    expect(result).toEqual(row);
    const [sql, values] = vi.mocked(pool.query).mock.calls[0]!;
    expect(String(sql)).toContain('ON CONFLICT (id) DO UPDATE');
    expect(String(sql)).toContain("WHEN users.role = 'driver' AND EXCLUDED.role = 'passenger'");
    expect(String(sql)).toContain("WHEN users.status = 'suspended' AND EXCLUDED.status = 'active'");
    expect(values).toEqual([
      'user-1',
      'auth-1',
      '+255700000001',
      'User One',
      'user1@rishfy.test',
      'passenger',
      'active',
    ]);
  });
});

describe('UserRepository.recordRating', () => {
  it('records a new rating and updates aggregate once', async () => {
    const { pool, client } = makeTransactionalPool();
    vi.mocked(client.query)
      .mockResolvedValueOnce({ rows: [], rowCount: null } as never)
      .mockResolvedValueOnce({ rows: [{ id: 'rating-1' }], rowCount: 1 } as never)
      .mockResolvedValueOnce({ rows: [row], rowCount: 1 } as never)
      .mockResolvedValueOnce({ rows: [], rowCount: null } as never);

    const result = await new UserRepository(pool).recordRating({
      rateeId: 'user-1',
      raterId: 'user-2',
      bookingId: 'booking-1',
      score: 5,
    });

    expect(result).toEqual({ applied: true, user: row });
    expect(vi.mocked(client.query).mock.calls[1]?.[0]).toContain('ON CONFLICT (booking_id, ratee_id) DO NOTHING');
    expect(vi.mocked(client.query).mock.calls[2]?.[0]).toContain('total_ratings + 1');
    expect(client.release).toHaveBeenCalledTimes(1);
  });

  it('does not update aggregate for duplicate booking/ratee ratings', async () => {
    const { pool, client } = makeTransactionalPool();
    vi.mocked(client.query)
      .mockResolvedValueOnce({ rows: [], rowCount: null } as never)
      .mockResolvedValueOnce({ rows: [], rowCount: 0 } as never)
      .mockResolvedValueOnce({ rows: [row], rowCount: 1 } as never)
      .mockResolvedValueOnce({ rows: [], rowCount: null } as never);

    const result = await new UserRepository(pool).recordRating({
      rateeId: 'user-1',
      raterId: 'user-2',
      bookingId: 'booking-1',
      score: 5,
    });

    expect(result).toEqual({ applied: false, user: row });
    expect(vi.mocked(client.query).mock.calls[2]?.[0]).toContain('SELECT * FROM users');
    expect(
      vi.mocked(client.query).mock.calls.some((call) => String(call[0]).includes('total_ratings + 1')),
    ).toBe(false);
    expect(client.release).toHaveBeenCalledTimes(1);
  });
});

describe('UserRepository social trust operations', () => {
  it('moderates ratings with reviewer audit fields', async () => {
    const pool = makePool();
    const rating = {
      id: 'rating-1',
      ratee_id: 'user-1',
      rater_id: 'user-2',
      booking_id: 'booking-1',
      score: 2,
      comment: 'Unsafe',
      moderation_status: 'hidden',
      moderated_by: 'admin-1',
      moderated_at: new Date(),
      hidden_reason: 'Safety complaint',
      created_at: new Date(),
    };
    vi.mocked(pool.query).mockResolvedValueOnce({ rows: [rating], rowCount: 1 } as never);

    const result = await new UserRepository(pool).moderateRating({
      ratingId: 'rating-1',
      status: 'hidden',
      moderatedBy: 'admin-1',
      hiddenReason: 'Safety complaint',
    });

    expect(result).toEqual(rating);
    const [sql, values] = vi.mocked(pool.query).mock.calls[0]!;
    expect(String(sql)).toContain('moderation_status=$2');
    expect(String(sql)).toContain('moderated_by=$3');
    expect(values).toEqual(['rating-1', 'hidden', 'admin-1', 'Safety complaint']);
  });

  it('creates active user blocks idempotently', async () => {
    const pool = makePool();
    const block = {
      id: 'block-1',
      blocker_id: 'user-1',
      blocked_id: 'user-2',
      reason: 'harassment',
      created_at: new Date(),
      deleted_at: null,
    };
    vi.mocked(pool.query).mockResolvedValueOnce({ rows: [block], rowCount: 1 } as never);

    const result = await new UserRepository(pool).blockUser({
      blockerId: 'user-1',
      blockedId: 'user-2',
      reason: 'harassment',
    });

    expect(result).toEqual(block);
    const [sql, values] = vi.mocked(pool.query).mock.calls[0]!;
    expect(String(sql)).toContain('ON CONFLICT (blocker_id, blocked_id) WHERE deleted_at IS NULL');
    expect(values).toEqual(['user-1', 'user-2', 'harassment']);
  });

  it('creates active favorite drivers idempotently', async () => {
    const pool = makePool();
    const favorite = {
      id: 'favorite-1',
      passenger_user_id: 'passenger-1',
      driver_user_id: 'driver-1',
      created_at: new Date(),
      deleted_at: null,
    };
    vi.mocked(pool.query).mockResolvedValueOnce({ rows: [favorite], rowCount: 1 } as never);

    const result = await new UserRepository(pool).addFavoriteDriver('passenger-1', 'driver-1');

    expect(result).toEqual(favorite);
    const [sql, values] = vi.mocked(pool.query).mock.calls[0]!;
    expect(String(sql)).toContain('ON CONFLICT (passenger_user_id, driver_user_id) WHERE deleted_at IS NULL');
    expect(values).toEqual(['passenger-1', 'driver-1']);
  });
});
