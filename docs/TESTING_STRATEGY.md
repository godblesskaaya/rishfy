# Testing Strategy

> **Principle:** Every line of production code is tested. Tests run in CI on every PR. Red builds block merges, period.

---

## 1. Test Pyramid

```
                    ▲
                   ╱ ╲
                  ╱ E ╲          ← ~10 tests, full stack, slow
                 ╱ 2 E ╲
                ╱───────╲
               ╱   I    ╲        ← ~100 tests per service, cross-module
              ╱ n t  e g ╲
             ╱ r a t  i o ╲
            ╱─────────────╲
           ╱      Unit      ╲    ← ~1000 tests per service, fast, isolated
          ╱─────────────────╲
```

**Ratios we aim for:**

- **Unit tests:** 70% of test volume, 100% of pure logic
- **Integration tests:** 20% of volume, cover inter-module flows
- **End-to-end tests:** 10% of volume, cover critical user journeys only

---

## 2. Tooling

| Layer | Tool | Rationale |
|---|---|---|
| Test runner | **Vitest** | Fast, TypeScript-native, Jest-compatible API |
| Assertion | Vitest built-in | No extra library needed |
| Mocking | Vitest's `vi.mock` | Built-in, ergonomic |
| API testing | **Supertest** | Industry standard for Express/Fastify |
| DB test containers | **@testcontainers/postgresql** | Real PostgreSQL, no mocking |
| Kafka testing | **testcontainers** (redpanda image) | Real Kafka, fast |
| E2E framework | **Playwright** (for future web admin) + custom harness (API) | Flexible |
| Load testing | **k6** | Scriptable in JS, good reports |
| Mobile testing | **Flutter test** + **integration_test** | Framework standard |

---

## 3. What to Test at Each Level

### 3.1 Unit Tests

**Scope:** A single class, function, or module. No network, no DB, no file I/O.

**Target: 90%+ line coverage** of:

- Business logic classes (`services/*/src/services/`)
- Pure helpers (fare calculation, distance math, validation)
- Domain models (invariants, state transitions)

**Don't unit-test:**

- Controllers (test via integration)
- Repositories (test via integration with real DB)
- Auto-generated code (proto classes)

**Example structure:**

```
services/booking/
├── src/
│   └── services/
│       └── booking.service.ts
└── tests/
    └── unit/
        └── booking.service.spec.ts
```

**Example test:**

```typescript
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { BookingService } from '../../src/services/booking.service';

describe('BookingService.calculateRefund', () => {
  let service: BookingService;

  beforeEach(() => {
    service = new BookingService({} as any, {} as any, {} as any);
  });

  it('returns full refund when cancellation is >2h before departure', () => {
    const result = service.calculateRefund({
      amount: 5000,
      departureTime: new Date('2026-02-18T10:00:00Z'),
      cancellationTime: new Date('2026-02-18T07:00:00Z'),
    });
    expect(result.refundAmount).toBe(5000);
    expect(result.policy).toBe('FREE');
  });

  it('applies 50% penalty when cancellation is <2h before departure', () => {
    const result = service.calculateRefund({
      amount: 5000,
      departureTime: new Date('2026-02-18T10:00:00Z'),
      cancellationTime: new Date('2026-02-18T09:00:00Z'),
    });
    expect(result.refundAmount).toBe(2500);
    expect(result.policy).toBe('PENALTY_50');
  });
});
```

### 3.2 Integration Tests

**Scope:** Multiple modules within one service, using real DB and real Kafka (via testcontainers). Mock external services (user-service gRPC, payment providers).

**What they prove:** A module interacts correctly with its dependencies.

**Per-service targets:**

- Repository → DB (all queries work against real schema)
- Controller → Service → Repository (full request handling)
- Event consumers (Kafka message → state change)
- gRPC server (incoming call → response)

**Example:**

```typescript
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { PostgreSqlContainer } from '@testcontainers/postgresql';
import { buildApp } from '../../src/app';
import request from 'supertest';

describe('POST /api/v1/bookings', () => {
  let container;
  let app;

  beforeAll(async () => {
    container = await new PostgreSqlContainer('postgis/postgis:16-3.4')
      .withDatabase('booking_db_test')
      .start();
    app = await buildApp({
      databaseUrl: container.getConnectionUri(),
      // ... mock other deps
    });
    await app.migrate();
  }, 60000);

  afterAll(async () => {
    await container.stop();
  });

  it('creates a booking when seats available and payment succeeds', async () => {
    // given: seeded route with available seats
    // when: POST /api/v1/bookings
    const res = await request(app.server)
      .post('/api/v1/bookings')
      .set('Authorization', 'Bearer <test-token>')
      .send({
        route_id: 'test-route-1',
        seat_count: 1,
        // ...
      });

    expect(res.status).toBe(201);
    expect(res.body.booking.status).toBe('PENDING');
    expect(res.body.booking.confirmation_code).toMatch(/^[A-Z0-9]{8}$/);
  });
});
```

### 3.3 End-to-End Tests

**Scope:** Full stack — real services, real DB, real infrastructure. Slow, but they prove the system works.

**Critical paths to cover (MUST have E2E tests):**

1. **Registration flow:** Phone → OTP → profile creation
2. **Route posting flow:** Driver creates route → route appears in search
3. **Booking flow:** Passenger searches → books → pays → confirmation
4. **Trip flow:** Driver starts trip → location updates stream → trip completes → rating submitted
5. **Cancellation flow:** Free cancellation within window → full refund issued
6. **LATRA report flow:** Completed trips appear in LATRA endpoint correctly formatted

**Location:** `tests/e2e/` at repo root.

**Harness:** Custom TypeScript harness that spins up `docker-compose.test.yml` (lighter than dev), seeds data, and runs scenarios via HTTP.

```typescript
describe('E2E: Full booking lifecycle', () => {
  it('a passenger can book a ride and complete the trip', async () => {
    const passenger = await registerUser({ role: 'passenger' });
    const driver = await registerUser({ role: 'driver' });
    const vehicle = await registerVehicle(driver);
    const route = await postRoute(driver, vehicle);

    const booking = await createBooking(passenger, route);
    await mockPaymentSuccess(booking.payment_id);
    await startTrip(driver, booking);
    await completeTrip(driver, booking);
    await submitRating(passenger, booking, 5);

    const finalBooking = await getBooking(passenger, booking.booking_id);
    expect(finalBooking.status).toBe('COMPLETED');
    expect(finalBooking.passenger_rating).toBe(5);
  });
});
```

---

## 4. Test Data Strategy

### 4.1 Fixtures

Each service has a `tests/fixtures/` directory with:

- `users.ts` — Test user factory (passengers, drivers, admins)
- `routes.ts` — Test route factory
- `bookings.ts` — Test booking factory
- Small SQL seed files for integration tests

Use **factory functions**, not static JSON fixtures — they're easier to override:

```typescript
// tests/fixtures/users.ts
export function aDriver(overrides: Partial<User> = {}): User {
  return {
    user_id: uuid(),
    phone_number: '+255712345678',
    first_name: 'Test',
    last_name: 'Driver',
    role: 'driver',
    rating_average: 4.8,
    rating_count: 25,
    ...overrides,
  };
}
```

### 4.2 Database Isolation

**Every integration test runs in a transaction that's rolled back at the end.** No cross-test pollution.

```typescript
beforeEach(async () => {
  await db.raw('BEGIN');
});
afterEach(async () => {
  await db.raw('ROLLBACK');
});
```

For E2E, we use schema-per-test-run: each CI job gets its own schema, dropped on completion.

---

## 5. CI Pipeline

Test stages, in order:

1. **Lint** — ESLint + Prettier check (< 30s)
2. **Typecheck** — `tsc --noEmit` (< 1 min)
3. **Unit tests** — All services in parallel (< 2 min)
4. **Integration tests** — Services in parallel with testcontainers (< 5 min)
5. **E2E tests** — Critical paths only (< 10 min)
6. **Security scan** — `npm audit` + `gitleaks` (< 1 min)

**Any failure blocks merge.** No exceptions, no "I'll fix it next PR."

---

## 6. Coverage Thresholds

Enforced by CI:

| Layer | Minimum Coverage | How measured |
|---|---|---|
| Business logic (`src/services/`) | 90% lines | Vitest coverage |
| Repositories (`src/repositories/`) | 80% lines (integration) | Vitest coverage |
| Controllers (`src/controllers/`) | 80% lines (integration) | Vitest coverage |
| Overall service | 85% lines | Vitest coverage |

**Coverage is a floor, not a goal.** 100% coverage with bad tests is worse than 80% with good ones. Focus on the right assertions.

---

## 7. Performance Testing

k6 scripts in `tests/load/`:

- `route-search.js` — simulate 500 concurrent passengers searching routes
- `booking-creation.js` — 100 bookings/second sustained
- `location-ingestion.js` — 1000 drivers posting locations every 30s

**Targets (from ARCHITECTURE.md):**

- API p95 < 200ms
- Route search < 1s
- Booking creation < 2s

Run before every major release, and monthly in dev.

---

## 8. Mobile App Testing

Responsibility of the mobile lead. High-level:

- **Unit tests:** All view models, utilities
- **Widget tests:** All screens and reusable widgets
- **Integration tests:** Critical user journeys on a real device emulator
- **Manual tests:** Device matrix (Android 9+, iOS 14+) before each release

---

## 9. Testing Mobile Money (Without a Real Phone)

The dev environment includes a **mock payment provider** that simulates the three real providers:

- Toggle `PAYMENT_MOCK_MODE=true` in `.env`
- Mock provider accepts any phone number
- Configure success/failure rates and latencies via admin endpoint
- Useful for testing failure paths (timeout, insufficient funds, invalid PIN)

For sandbox testing against real providers, use the sandbox credentials from each provider's developer portal. Flow documented in `services/payment/README.md`.

---

## 10. Manual Testing Checklist (Pre-Release)

Automated tests catch regressions but not UX issues. Before every release, manually verify:

- [ ] Registration with a Tanzanian phone number
- [ ] OTP arrives within 30 seconds (SMS sandbox)
- [ ] Route posting + search returns relevant results
- [ ] Booking flow end-to-end with a real sandbox M-Pesa account
- [ ] Push notification arrives when booking confirmed
- [ ] Trip tracking updates in real-time on passenger app
- [ ] Rating submission works for both sides
- [ ] Cancellation policy enforced correctly (both sides of 2h window)
- [ ] LATRA report endpoint returns correctly formatted data

---

## 11. Definition of Done

A feature is "done" when:

- [ ] All unit tests pass
- [ ] Integration tests cover the new paths
- [ ] E2E test exists if it's a critical path
- [ ] Coverage thresholds maintained
- [ ] Manual smoke test done in dev environment
- [ ] Documentation updated (API_CONTRACTS.md, DATABASE_SCHEMA.md, etc.)
- [ ] PR approved by at least one other team member

---

*Last updated: Sprint 0. Adjust strategy at each retro based on what's actually catching bugs vs. what's busywork.*
