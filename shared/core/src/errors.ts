export type ErrorDetails = Record<string, unknown>;

export class AppError extends Error {
  public readonly code: string;
  public readonly statusCode: number;
  public readonly details?: ErrorDetails;
  public readonly cause?: unknown;

  constructor(
    code: string,
    message: string,
    statusCode = 500,
    details?: ErrorDetails,
    options?: { cause?: unknown }
  ) {
    super(message);
    this.name = new.target.name;
    this.code = code;
    this.statusCode = statusCode;
    this.details = details;
    this.cause = options?.cause;
    Error.captureStackTrace?.(this, new.target);
  }

  toJSON(): Record<string, unknown> {
    return {
      name: this.name,
      code: this.code,
      message: this.message,
      statusCode: this.statusCode,
      details: this.details,
    };
  }
}

export class ValidationError extends AppError {
  constructor(message: string, details?: ErrorDetails) {
    super('VALIDATION_ERROR', message, 400, details);
  }
}

export class UnauthorizedError extends AppError {
  constructor(message = 'Unauthorized', details?: ErrorDetails) {
    super('UNAUTHORIZED', message, 401, details);
  }
}

export class ForbiddenError extends AppError {
  constructor(message = 'Forbidden', details?: ErrorDetails) {
    super('FORBIDDEN', message, 403, details);
  }
}

export class NotFoundError extends AppError {
  constructor(resource: string, id?: string | number, details?: ErrorDetails) {
    const message = id === undefined ? `${resource} not found` : `${resource} ${id} not found`;
    super('RESOURCE_NOT_FOUND', message, 404, details);
  }
}

export class ConflictError extends AppError {
  constructor(message: string, details?: ErrorDetails) {
    super('RESOURCE_CONFLICT', message, 409, details);
  }
}

export class RateLimitError extends AppError {
  constructor(message = 'Too many requests', details?: ErrorDetails) {
    super('RATE_LIMITED', message, 429, details);
  }
}

export class ExternalServiceError extends AppError {
  constructor(message: string, details?: ErrorDetails, options?: { cause?: unknown }) {
    super('EXTERNAL_SERVICE_ERROR', message, 502, details, options);
  }
}
