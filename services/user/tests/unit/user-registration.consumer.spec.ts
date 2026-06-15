import { describe, expect, it, vi } from 'vitest';
import { applyUserRegisteredEvent } from '../../src/consumers/user-registration.consumer.js';

describe('applyUserRegisteredEvent', () => {
  it('upserts user profile from user.registered payload', async () => {
    const repo = {
      upsertFromRegistration: vi.fn().mockResolvedValue({}),
    } as unknown as import('../../src/repositories/user.repository.js').UserRepository;

    await applyUserRegisteredEvent(repo, {
      user_id: 'user-1',
      phone_number: '+255700000001',
      full_name: 'Rishfy Rider',
      email: 'rider@rishfy.test',
      role: 'passenger',
    });

    expect(repo.upsertFromRegistration).toHaveBeenCalledWith(expect.objectContaining({
      id: expect.any(String),
      auth_id: 'user-1',
      phone_number: '+255700000001',
      full_name: 'Rishfy Rider',
      email: 'rider@rishfy.test',
      role: 'passenger',
      status: 'active',
    }));
  });

  it('supports legacy phone/user_type payload keys', async () => {
    const repo = {
      upsertFromRegistration: vi.fn().mockResolvedValue({}),
    } as unknown as import('../../src/repositories/user.repository.js').UserRepository;

    await applyUserRegisteredEvent(repo, {
      user_id: 'user-2',
      phone: '+255700000002',
      full_name: 'Driver Candidate',
      user_type: 'driver',
    });

    expect(repo.upsertFromRegistration).toHaveBeenCalledWith(expect.objectContaining({
      id: expect.any(String),
      auth_id: 'user-2',
      phone_number: '+255700000002',
      full_name: 'Driver Candidate',
      email: null,
      role: 'driver',
      status: 'active',
    }));
  });

  it('defaults full_name when missing', async () => {
    const repo = {
      upsertFromRegistration: vi.fn().mockResolvedValue({}),
    } as unknown as import('../../src/repositories/user.repository.js').UserRepository;

    await applyUserRegisteredEvent(repo, {
      user_id: 'user-3',
      phone_number: '+255700000003',
    });

    expect(repo.upsertFromRegistration).toHaveBeenCalledWith(expect.objectContaining({
      id: expect.any(String),
      auth_id: 'user-3',
      phone_number: '+255700000003',
      full_name: 'Rishfy User',
      email: null,
      role: 'passenger',
      status: 'active',
    }));
  });

  it('throws when phone identity field is missing', async () => {
    const repo = {
      upsertFromRegistration: vi.fn().mockResolvedValue({}),
    } as unknown as import('../../src/repositories/user.repository.js').UserRepository;

    await expect(applyUserRegisteredEvent(repo, { user_id: 'user-4' })).rejects.toThrow(
      'user.registered event missing phone_number',
    );
    expect(repo.upsertFromRegistration).not.toHaveBeenCalled();
  });
});
