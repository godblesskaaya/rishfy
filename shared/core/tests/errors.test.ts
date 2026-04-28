import { describe, expect, it } from 'vitest';

import { ConflictError, NotFoundError, ValidationError } from '../src/errors.js';

describe('shared errors', () => {
  it('builds validation errors with the expected metadata', () => {
    const error = new ValidationError('Invalid input', { field: 'phone' });

    expect(error.code).toBe('VALIDATION_ERROR');
    expect(error.statusCode).toBe(400);
    expect(error.details).toEqual({ field: 'phone' });
  });

  it('builds resource-specific not found errors', () => {
    const error = new NotFoundError('User', 42);

    expect(error.message).toBe('User 42 not found');
    expect(error.statusCode).toBe(404);
  });

  it('serializes conflict errors without leaking implementation fields', () => {
    const error = new ConflictError('Phone already registered');

    expect(error.toJSON()).toMatchObject({
      name: 'ConflictError',
      code: 'RESOURCE_CONFLICT',
      message: 'Phone already registered',
      statusCode: 409,
    });
  });
});
