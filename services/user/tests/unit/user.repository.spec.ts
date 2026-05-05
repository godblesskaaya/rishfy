import { describe, expect, it, vi } from 'vitest';
import { UserRepository } from '../../src/repositories/user.repository.js';

function makePool() {
  return { query: vi.fn() } as unknown as import('pg').Pool;
}

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
      '+255700000001',
      'User One',
      'user1@rishfy.test',
      'passenger',
      'active',
    ]);
  });
});
