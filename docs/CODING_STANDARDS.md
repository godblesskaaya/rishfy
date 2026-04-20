# Rishfy Coding Standards

> **Style guide, conventions, and best practices for all Rishfy code**
> Languages: TypeScript (backend), Dart (mobile)

---

## Table of Contents

1. [General Principles](#1-general-principles)
2. [TypeScript Standards](#2-typescript-standards)
3. [Dart/Flutter Standards](#3-dartflutter-standards)
4. [API Design](#4-api-design)
5. [Error Handling](#5-error-handling)
6. [Testing](#6-testing)
7. [Git Workflow](#7-git-workflow)
8. [Code Review](#8-code-review)
9. [Security Checklist](#9-security-checklist)

---

## 1. General Principles

### 1.1 Core Values

| Value | What It Means |
|-------|---------------|
| **Clarity over cleverness** | Code is read 10x more than it's written |
| **Explicit over implicit** | Obvious beats magical |
| **Fail loudly and early** | Crashes in dev > silent bugs in prod |
| **YAGNI** | "You Aren't Gonna Need It" — don't add speculative features |
| **DRY, but not too dry** | Duplicate once, abstract on the third occurrence |
| **Consistency > Perfection** | Follow the pattern already in use |

### 1.2 Universal Rules

- **No commented-out code** in committed PRs
- **No console.log in production code** (use logger)
- **No `any` type without justification**
- **No TODO comments without an associated ticket**
- **No hard-coded magic numbers/strings** — use constants
- **No dead code** — delete it, git history preserves it
- **No secrets in code** — use environment variables

---

## 2. TypeScript Standards

### 2.1 File Organization

**One concept per file**. Filename matches primary export.

```typescript
// ✅ Good
// auth.service.ts
export class AuthService { /* ... */ }

// ❌ Bad
// utils.ts (generic dumping ground)
export class AuthService { /* ... */ }
export class UserService { /* ... */ }
```

### 2.2 Naming Conventions

| Type | Convention | Example |
|------|-----------|---------|
| Files | `kebab-case.ts` | `auth.service.ts`, `user-profile.repository.ts` |
| Classes | `PascalCase` | `AuthService`, `UserRepository` |
| Interfaces | `PascalCase` (no `I` prefix) | `AuthUser`, `BookingRequest` |
| Types | `PascalCase` | `UserType`, `PaymentStatus` |
| Functions | `camelCase` | `validateToken`, `calculateFare` |
| Variables | `camelCase` | `currentUser`, `bookingId` |
| Constants | `UPPER_SNAKE_CASE` | `MAX_RETRY_COUNT`, `JWT_EXPIRY_MS` |
| Enums | `PascalCase`, values `UPPER_SNAKE_CASE` | `UserType.DRIVER` |
| Private | prefix `_` (only for class members) | `_cache`, `_connection` |

### 2.3 Type Definitions

**Always use explicit types for function signatures**.

```typescript
// ✅ Good
function calculateFare(distance: number, basePrice: number): number {
  return distance * basePrice;
}

async function getUserById(id: number): Promise<User | null> {
  return await userRepo.findById(id);
}

// ❌ Bad
function calculateFare(distance, basePrice) {
  return distance * basePrice;
}
```

**Use interfaces for data shapes**, types for unions/utilities:

```typescript
// ✅ Good
interface User {
  id: number;
  name: string;
  email: string;
}

type UserType = 'driver' | 'rider' | 'admin';
type Partial<T> = { [P in keyof T]?: T[P] };

// ❌ Avoid interfaces for simple unions
interface UserType {
  value: 'driver' | 'rider' | 'admin';
}
```

### 2.4 Avoiding `any`

```typescript
// ❌ Bad
function processData(data: any) { /* ... */ }

// ✅ Good — use unknown if truly unknown
function processData(data: unknown) {
  if (typeof data === 'object' && data !== null && 'id' in data) {
    // Now we can safely access data.id
  }
}

// ✅ Good — use generics for flexibility
function getFirst<T>(items: T[]): T | undefined {
  return items[0];
}
```

### 2.5 Async/Await

**Always use async/await over raw Promises**:

```typescript
// ✅ Good
async function createBooking(data: BookingData): Promise<Booking> {
  const route = await routeService.getRoute(data.routeId);
  const booking = await bookingRepo.create({ ...data, route });
  await eventBus.publish('booking.created', booking);
  return booking;
}

// ❌ Bad
function createBooking(data: BookingData): Promise<Booking> {
  return routeService.getRoute(data.routeId)
    .then(route => bookingRepo.create({ ...data, route }))
    .then(booking => eventBus.publish('booking.created', booking).then(() => booking));
}
```

**Always handle errors**:

```typescript
// ✅ Good
try {
  await paymentService.process(payment);
} catch (error) {
  logger.error('Payment failed', { error, paymentId: payment.id });
  throw new PaymentError('Payment processing failed', { cause: error });
}

// ❌ Bad — silently swallowing
try {
  await paymentService.process(payment);
} catch {
  // nothing
}
```

### 2.6 Dependency Injection

Services should accept dependencies via constructor, not import them:

```typescript
// ✅ Good
export class AuthService {
  constructor(
    private readonly userRepo: UserRepository,
    private readonly tokenService: TokenService,
    private readonly eventBus: EventBus
  ) {}

  async login(phone: string, password: string): Promise<AuthResult> {
    const user = await this.userRepo.findByPhone(phone);
    // ...
  }
}

// ❌ Bad
import { userRepo } from './user.repository';
import { tokenService } from './token.service';

export class AuthService {
  async login(phone: string, password: string) {
    const user = await userRepo.findByPhone(phone);
    // ...
  }
}
```

Why? Testability. You can inject mocks in tests without module mocking hacks.

### 2.7 Layered Architecture

Strict dependency direction:

```
Controller → Service → Repository → Database
    ↓          ↓
  Validator  Domain
```

- **Controllers**: HTTP concerns only. Parse request, call service, format response.
- **Services**: Business logic. Orchestrate repositories and external calls.
- **Repositories**: Data access only. No business logic.
- **Validators**: Input validation using zod or similar.

```typescript
// ✅ Good separation
// controller
async function register(req: Request, res: Response) {
  const data = registerSchema.parse(req.body);  // validator
  const result = await authService.register(data);  // service
  res.status(201).json({ success: true, data: result });
}

// service
class AuthService {
  async register(data: RegisterData): Promise<AuthResult> {
    const existing = await this.userRepo.findByPhone(data.phone);  // repo
    if (existing) throw new ConflictError('Phone already registered');
    const hash = await this.hasher.hash(data.password);  // dependency
    return await this.userRepo.create({ ...data, passwordHash: hash });
  }
}
```

### 2.8 Logging

```typescript
import { logger } from '@rishfy/shared/utils/logger';

// ✅ Good — structured, with context
logger.info('User registered', {
  userId: user.id,
  phone: user.phone,
  user_type: user.userType
});

logger.error('Payment failed', {
  error: error.message,
  stack: error.stack,
  paymentId: payment.id,
  bookingId: payment.bookingId
});

// ❌ Bad — unstructured strings
console.log(`User ${user.id} registered with phone ${user.phone}`);
console.error(`Payment ${payment.id} failed: ${error.message}`);
```

**Log levels**:
- `error`: Something went wrong and needs attention
- `warn`: Unusual but recoverable (retry, fallback used)
- `info`: Important business events (user registered, booking confirmed)
- `debug`: Verbose info, dev only

**Never log**:
- Passwords (even hashed)
- Full JWTs
- National IDs
- Credit card numbers
- Phone numbers in full (mask middle digits)

### 2.9 Comments

Write self-documenting code. Comments explain **why**, not **what**:

```typescript
// ❌ Bad — explains what (obvious from code)
// Increment counter by 1
counter++;

// ✅ Good — explains why (context)
// Increment here to prevent race condition with async callback below
counter++;

// ✅ Good — explains business rule
// LATRA requires timestamps without the 'T' separator in JSON exports
return timestamp.toISOString().replace('T', ' ');
```

Use JSDoc for public APIs:

```typescript
/**
 * Creates a new booking and reserves seats on the route.
 *
 * @param data - Booking details including route ID and seat count
 * @returns The created booking with generated confirmation code
 * @throws {SeatsUnavailableError} If not enough seats available
 * @throws {RouteDepartedError} If the route has already departed
 */
async function createBooking(data: CreateBookingData): Promise<Booking> {
  // ...
}
```

---

## 3. Dart/Flutter Standards

### 3.1 File Organization

Follow the official [Dart style guide](https://dart.dev/effective-dart):

```
lib/
├── main.dart
├── core/
│   ├── config/
│   ├── errors/
│   ├── network/
│   └── utils/
├── features/
│   ├── auth/
│   │   ├── data/
│   │   │   ├── datasources/
│   │   │   ├── models/
│   │   │   └── repositories/
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   └── usecases/
│   │   └── presentation/
│   │       ├── bloc/
│   │       ├── screens/
│   │       └── widgets/
│   └── booking/
│       └── (same structure)
└── shared/
    └── widgets/
```

### 3.2 Naming Conventions

| Type | Convention | Example |
|------|-----------|---------|
| Files | `snake_case.dart` | `auth_screen.dart`, `user_model.dart` |
| Classes | `PascalCase` | `AuthScreen`, `UserModel` |
| Variables | `camelCase` | `userName`, `isLoading` |
| Constants | `camelCase` | `const maxRetries = 3;` |
| Private | prefix `_` | `_controller`, `_onLoginPressed` |

### 3.3 Widget Best Practices

**Prefer const constructors**:

```dart
// ✅ Good
const Text('Hello', style: TextStyle(fontSize: 16))

// ❌ Unnecessarily rebuilds
Text('Hello', style: TextStyle(fontSize: 16))
```

**Extract widgets for reuse**:

```dart
// ❌ Bad — 200-line build method
Widget build(BuildContext context) {
  return Scaffold(
    body: Column(children: [
      // 50 lines of header...
      // 50 lines of content...
      // 50 lines of footer...
    ]),
  );
}

// ✅ Good — composed widgets
Widget build(BuildContext context) {
  return Scaffold(
    body: Column(children: [
      const _Header(),
      const _Content(),
      const _Footer(),
    ]),
  );
}
```

### 3.4 State Management (flutter_bloc)

```dart
// Event
abstract class AuthEvent {}
class LoginRequested extends AuthEvent {
  final String phone;
  final String password;
  LoginRequested(this.phone, this.password);
}

// State
abstract class AuthState {}
class AuthInitial extends AuthState {}
class AuthLoading extends AuthState {}
class AuthSuccess extends AuthState {
  final User user;
  AuthSuccess(this.user);
}
class AuthFailure extends AuthState {
  final String message;
  AuthFailure(this.message);
}

// Bloc
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _repository;

  AuthBloc(this._repository) : super(AuthInitial()) {
    on<LoginRequested>(_onLoginRequested);
  }

  Future<void> _onLoginRequested(
    LoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final user = await _repository.login(event.phone, event.password);
      emit(AuthSuccess(user));
    } catch (e) {
      emit(AuthFailure(e.toString()));
    }
  }
}
```

---

## 4. API Design

### 4.1 RESTful Principles

```
GET    /users         # List users
POST   /users         # Create user
GET    /users/:id     # Get user
PUT    /users/:id     # Full update
PATCH  /users/:id     # Partial update
DELETE /users/:id     # Delete user
```

**Use nouns, not verbs**:
- ✅ `POST /bookings`
- ❌ `POST /createBooking`

**Use nested resources for containment**:
- ✅ `GET /routes/123/bookings`
- ❌ `GET /bookings?routeId=123` (acceptable but less clear)

**Use verbs only for non-CRUD actions**:
- ✅ `POST /bookings/123/cancel`
- ✅ `POST /bookings/123/start-trip`

### 4.2 Status Codes

Always use the correct HTTP status code. See [API_CONTRACTS.md](API_CONTRACTS.md) for the full table.

### 4.3 Request Validation

Use **zod** for all input validation:

```typescript
import { z } from 'zod';

const CreateBookingSchema = z.object({
  route_id: z.number().int().positive(),
  seats_booked: z.number().int().min(1).max(20),
  pickup: z.object({
    lat: z.number().min(-90).max(90),
    lng: z.number().min(-180).max(180),
    address: z.string().min(1).max(500),
  }),
  dropoff: z.object({
    lat: z.number().min(-90).max(90),
    lng: z.number().min(-180).max(180),
    address: z.string().min(1).max(500),
  }),
});

// In controller
const data = CreateBookingSchema.parse(req.body); // throws on invalid
```

---

## 5. Error Handling

### 5.1 Custom Error Classes

```typescript
// shared/utils/errors.ts
export class AppError extends Error {
  constructor(
    public code: string,
    message: string,
    public statusCode: number = 500,
    public details?: Record<string, unknown>
  ) {
    super(message);
    this.name = this.constructor.name;
    Error.captureStackTrace(this, this.constructor);
  }
}

export class ValidationError extends AppError {
  constructor(message: string, details?: Record<string, unknown>) {
    super('VALIDATION_ERROR', message, 400, details);
  }
}

export class NotFoundError extends AppError {
  constructor(resource: string, id: string | number) {
    super('RESOURCE_NOT_FOUND', `${resource} ${id} not found`, 404);
  }
}

export class ConflictError extends AppError {
  constructor(message: string) {
    super('RESOURCE_CONFLICT', message, 409);
  }
}

// Usage in service
if (!user) {
  throw new NotFoundError('User', userId);
}
```

### 5.2 Error Middleware

```typescript
// middleware/error-handler.ts
export function errorHandler(
  error: Error,
  req: Request,
  res: Response,
  next: NextFunction
) {
  logger.error('Request failed', {
    error: error.message,
    stack: error.stack,
    path: req.path,
    method: req.method,
    userId: req.user?.id,
  });

  if (error instanceof AppError) {
    res.status(error.statusCode).json({
      success: false,
      error: {
        code: error.code,
        message: error.message,
        details: error.details,
        trace_id: req.traceId,
      },
    });
    return;
  }

  // Unknown error — don't leak internals
  res.status(500).json({
    success: false,
    error: {
      code: 'INTERNAL_ERROR',
      message: 'An unexpected error occurred',
      trace_id: req.traceId,
    },
  });
}
```

---

## 6. Testing

### 6.1 Testing Pyramid

```
        /\
       /E2E\         ← Few, slow, critical flows
      /------\
     / Integ. \      ← Service + DB integration
    /----------\
   /   Unit     \    ← Many, fast, isolated
  /--------------\
```

| Type | Count | Speed | What |
|------|-------|-------|------|
| Unit | Hundreds | ms | Pure functions, business logic |
| Integration | Dozens | seconds | Service + DB + Redis |
| E2E | A few | minutes | Critical user flows |

### 6.2 Unit Tests (Jest)

```typescript
// auth.service.test.ts
describe('AuthService', () => {
  let authService: AuthService;
  let mockUserRepo: jest.Mocked<UserRepository>;
  let mockTokenService: jest.Mocked<TokenService>;

  beforeEach(() => {
    mockUserRepo = {
      findByPhone: jest.fn(),
      create: jest.fn(),
    } as any;
    mockTokenService = {
      generate: jest.fn(),
    } as any;
    authService = new AuthService(mockUserRepo, mockTokenService);
  });

  describe('login', () => {
    it('returns tokens on valid credentials', async () => {
      mockUserRepo.findByPhone.mockResolvedValue({
        id: 1,
        passwordHash: 'hashed',
      } as User);
      mockTokenService.generate.mockResolvedValue({
        accessToken: 'at',
        refreshToken: 'rt',
      });

      const result = await authService.login('+255712345678', 'password');

      expect(result.accessToken).toBe('at');
      expect(mockUserRepo.findByPhone).toHaveBeenCalledWith('+255712345678');
    });

    it('throws on invalid credentials', async () => {
      mockUserRepo.findByPhone.mockResolvedValue(null);

      await expect(authService.login('+255712345678', 'wrong'))
        .rejects.toThrow('Invalid credentials');
    });
  });
});
```

### 6.3 Integration Tests

```typescript
// auth.integration.test.ts
describe('Auth API', () => {
  let app: FastifyInstance;
  let db: DatabasePool;

  beforeAll(async () => {
    app = await buildApp({ env: 'test' });
    db = await createTestDb();
  });

  afterEach(async () => {
    await db.query('TRUNCATE auth_users CASCADE');
  });

  afterAll(async () => {
    await app.close();
    await db.end();
  });

  describe('POST /auth/register', () => {
    it('registers a new user and sends OTP', async () => {
      const response = await app.inject({
        method: 'POST',
        url: '/api/v1/auth/register',
        payload: {
          phone: '+255712345678',
          password: 'TestPass123!',
          user_type: 'rider',
        },
      });

      expect(response.statusCode).toBe(201);
      const { data } = JSON.parse(response.body);
      expect(data.verification_required).toBe(true);

      // Verify in DB
      const user = await db.query(
        'SELECT * FROM auth_users WHERE phone = $1',
        ['+255712345678']
      );
      expect(user.rowCount).toBe(1);
      expect(user.rows[0].verified).toBe(false);
    });

    it('rejects duplicate phone', async () => {
      await db.query(
        'INSERT INTO auth_users (phone, password_hash, user_type) VALUES ($1, $2, $3)',
        ['+255712345678', 'hash', 'rider']
      );

      const response = await app.inject({
        method: 'POST',
        url: '/api/v1/auth/register',
        payload: {
          phone: '+255712345678',
          password: 'TestPass123!',
          user_type: 'rider',
        },
      });

      expect(response.statusCode).toBe(409);
    });
  });
});
```

### 6.4 Coverage Requirements

| Code Type | Minimum Coverage |
|-----------|-----------------|
| Business logic (services) | 90% |
| Controllers | 80% |
| Repositories | 80% |
| Utilities | 95% |
| **Overall** | **80%** |

CI fails if coverage drops below threshold.

---

## 7. Git Workflow

See [REPO_STRUCTURE.md](REPO_STRUCTURE.md) for branching strategy.

### 7.1 Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Subject line**:
- Max 72 characters
- Imperative mood: "add" not "added"
- No period at the end
- Describes what the commit does

**Examples**:

```bash
# Good
feat(auth): add OTP rate limiting
fix(payment): handle M-Pesa timeout gracefully
docs(api): update booking endpoint examples
test(route): add edge cases for seat reservation

# Bad
Added stuff
Fix bug
WIP
```

### 7.2 Atomic Commits

One logical change per commit. Split unrelated changes:

```bash
# ❌ Bad
git commit -m "feat(auth): add OTP and fix typos and update deps"

# ✅ Good
git commit -m "feat(auth): add OTP rate limiting"
git commit -m "docs: fix typos in README"
git commit -m "chore(deps): update zod to 3.22.4"
```

### 7.3 Pre-Commit Hooks

Husky runs these on every commit:

- `lint-staged`: ESLint + Prettier on staged files
- `commitlint`: Validates commit message format

Don't `--no-verify` unless truly necessary (and explain why in the PR).

---

## 8. Code Review

### 8.1 Author Responsibilities

Before requesting review:
- [ ] All tests pass locally
- [ ] Linter passes
- [ ] Self-review the diff
- [ ] PR description fills the template
- [ ] Screenshots for UI changes
- [ ] No commented-out code
- [ ] No debug logs
- [ ] Migration tested both ways (up + down)

### 8.2 Reviewer Responsibilities

Review for:

**Correctness**: Does the code do what it claims?
**Design**: Is this the right approach? Any simpler?
**Tests**: Do tests cover the new behavior? Edge cases?
**Performance**: Any obvious perf issues? N+1 queries?
**Security**: Input validated? SQL injection possible? Secrets leaked?
**Style**: Follows standards? Names are clear?
**Documentation**: Updated if APIs changed?

### 8.3 Review Etiquette

**Author**:
- Don't take feedback personally
- Respond to every comment (even just "done")
- Ask questions if unclear
- Push back (politely) if you disagree — explain reasoning

**Reviewer**:
- Be kind and specific
- Suggest, don't dictate: "Have you considered X?"
- Distinguish must-fix from nitpicks (prefix with "nit:")
- Approve with "LGTM" or explicit request for changes
- Don't rubber-stamp — if you don't understand it, ask

### 8.4 Merge Strategy

- **Squash merge** for feature branches (clean history on develop)
- **Merge commit** for release/hotfix branches (preserve history)
- **No fast-forward** (preserves branch context)

---

## 9. Security Checklist

Before merging any PR, verify:

### Input Validation
- [ ] All user input validated with zod
- [ ] SQL queries use parameterization (no string interpolation)
- [ ] File uploads check size and MIME type
- [ ] URL parameters sanitized

### Authentication & Authorization
- [ ] Protected endpoints check `req.user`
- [ ] Role checks use middleware, not scattered `if` statements
- [ ] Tokens never logged
- [ ] Passwords hashed with bcrypt (12+ rounds)

### Data Protection
- [ ] PII fields (phone, email, NID) never in URLs
- [ ] Sensitive data not in logs
- [ ] API responses don't leak internals (stack traces, DB errors)
- [ ] Rate limiting on auth endpoints

### External Integrations
- [ ] HTTPS enforced for external calls
- [ ] Webhook signatures verified
- [ ] Idempotency keys used for payments
- [ ] Secrets loaded from environment, never hardcoded

### Dependencies
- [ ] `npm audit` shows no high/critical issues
- [ ] New dependencies reviewed for credibility
- [ ] Lock file (`package-lock.json`) committed

---

## Quick Reference

### File Checklist for New Feature

- [ ] Controller with request/response handling
- [ ] Service with business logic
- [ ] Repository for data access
- [ ] DTOs for request/response
- [ ] Validator schema (zod)
- [ ] Unit tests
- [ ] Integration test
- [ ] OpenAPI spec update
- [ ] Documentation update

### Common Linting Errors

```typescript
// Error: Missing return type
function foo() {}                    // ❌
function foo(): void {}              // ✅

// Error: Unexpected any
function foo(data: any) {}           // ❌
function foo(data: unknown) {}       // ✅

// Error: Prefer const
let x = 5;                           // ❌ (never reassigned)
const x = 5;                         // ✅

// Error: No unused vars
const unused = 'foo';                // ❌
```

---

**Document Owner**: Platform Team
**Last Updated**: 2026-03-15
**Version**: 1.0
