# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## Commit Workflow (Critical)

Every commit must be attributed to the team member who owns that code. **Never add `Co-Authored-By` trailers of any kind.** Push using that person's key from `.ssh-keys/`.

**Ownership by area:**
| Area | Owner | git identity |
|------|-------|-------------|
| Auth service, user service | CodeWithStella | `stellakahungo24@gmail.com` |
| Route service, location service, mobile app | godblesskaaya | `godblessgkaaya@gmail.com` |
| Booking service, payment service, admin | Ezzy141 | `mazwaezekiel@gmail.com` |
| Notification service, docs | fatma-nassib | `abdallah.nassib.fatma@gmail.com` |

```bash
# Stage only that person's files, then:
git config user.name "godblesskaaya"
git config user.email "godblessgkaaya@gmail.com"
GIT_SSH_COMMAND="ssh -i /home/stk/rishfy/.ssh-keys/godbless_id_rsa -o IdentitiesOnly=yes" git push origin main
```

SSH agent state does not persist across Bash calls — always use `GIT_SSH_COMMAND` inline or chain `eval $(ssh-agent -s) && ssh-add ... && git push` in a single call.

---

## Backend Commands

All services are npm workspaces under `services/*`. Run from repo root or from the service directory.

```bash
# Start full dev stack (Postgres, Redis, Kafka, all services via Docker Compose)
npm run dev:up                        # docker compose up -d
npm run dev:logs                      # tail all logs
npm run dev:down                      # tear down

# Per-service dev (hot reload with tsx)
cd services/auth && npm run dev

# Tests
npm test                              # all workspaces
npm run test:unit                     # unit only (all workspaces)
npm run test:integration              # integration only
cd services/route && npm test         # single service
cd services/route && npm run test:unit -- tests/unit/route.service.spec.ts  # single file

# Lint / typecheck
npm run lint
npm run lint:fix
npm run typecheck                     # tsc --noEmit across all workspaces

# Migrations (per service)
cd services/auth && npm run migrate:up
cd services/auth && npm run migrate:create -- --name add_locked_until

# Seed
npm run seed
```

Gateway is NGINX on port 8080. All `/api/v1/*` traffic routes there; each service also exposes its own HTTP port (auth: 3001, user: 3002, route: 3003, booking: 3004, payment: 3005, location: 3006, notification: 3007). gRPC ports are 5005x (internal only).

---

## Mobile Commands

```bash
cd mobile

# Run (dev defaults to Android emulator — 10.0.2.2 → host localhost)
flutter run --dart-define=ENV=dev

# iOS simulator needs API_BASE_URL=http://localhost in assets/env/dev.env
flutter run --dart-define=ENV=dev

# Build
flutter build apk --dart-define=ENV=prod
flutter build ios --dart-define=ENV=prod

# Analyze / test
flutter analyze
flutter test
flutter test test/features/auth/        # single directory
```

Env config is loaded from `assets/env/<env>.env` at startup (`Env.load()` in `main.dart`). If the file is missing in debug mode, hardcoded dev defaults are used (see `lib/core/config/env.dart`).

---

## Architecture

### Backend — SOA with 7 services

```
Flutter App → NGINX (:8080) → auth / user / route / booking / payment / location / notification
```

Services communicate:
- **gRPC** for synchronous cross-service calls (e.g. route-service calls user-service to verify driver eligibility)
- **Kafka** for async events (e.g. `booking.created` triggers payment-service and notification-service)
- **No shared databases** — each service owns its own Postgres database and schema

Every service follows: `controllers/` (HTTP + Zod validation) → `services/` (business logic) → `repositories/` (Kysely queries). Routes files register endpoints and inline Zod schema parsing; the `services/` layer never touches HTTP. gRPC server implementations live in `grpc/` or `src/grpc.ts`.

Shared TypeScript types live in `shared/` and are imported as `@rishfy/shared/...` or `@rishfy/protos/...`. New services (Sprint 3+) use `@rishfy/protos` with `loadSync`; Sprint 1–2 services use runtime proto loading.

### Mobile — Flutter with Riverpod + Dio + GoRouter

**Layer flow:**  
`Screen (ConsumerWidget)` → `Provider (StateNotifier / AsyncNotifier)` → `DataSource` → `Dio`

- All Dio calls go through `dioClientProvider` (`lib/core/network/dio_client.dart`), which chains `AuthInterceptor → RetryInterceptor → ErrorInterceptor`. The auth interceptor auto-refreshes tokens and retries; the error interceptor converts HTTP errors into typed `AppException` subclasses (`lib/core/errors/app_exception.dart`).
- Feature structure: each feature in `lib/features/<name>/` has `data/` (models, datasources), `domain/` (entities, repository interfaces), and `presentation/` (providers, screens).
- Models have a strict parsing convention: use `_readRequiredString(json, [keys])`, `_readString(json, [keys])`, `_toInt(value)`, `_toDouble(value)`, `_parseDateTime(value)` — all file-scoped helpers that coerce types and handle nulls without throwing. Direct casts (`j['field'] as String`) are forbidden.
- Router (`lib/core/router/app_router.dart`) uses `GoRouter` with a `redirect` guard keyed on `authControllerProvider`. Unauthenticated users go to `/login`; authenticated users skip auth routes.
- Active role (`passenger` / `driver`) is a separate `activeRoleProvider` in `shared/providers/`. The shell screen uses it to toggle home screens; datasources that need role-aware endpoints read it too.

### Real-time (Location Service)

The location service runs two servers: a Fastify HTTP server (REST endpoints at `/api/v1/locations/*` and `/api/v1/trips/*`) and a raw `ws` WebSocket server on a separate port.

- **`/ws/driver`** — drivers connect here to broadcast GPS updates. Messages: `{ type: 'location', lat, lng, bearing?, speedKmh? }`.
- **`/ws/location`** (passenger) or **`/ws/passenger`** — passengers connect with `?booking_id=...&token=...` to receive `{ type: 'location_update', payload: DriverLocationUpdate }` frames.

Mobile WebSocket client is in `lib/features/trip/presentation/providers/trip_provider.dart` (`DriverTrackingNotifier` for passengers, `DriverBroadcastNotifier` for drivers).

### Payment

Payment is provider-agnostic in the codebase. The `payment-service` accepts `method: 'azampay' | 'mpesa' | 'tigopesa' | 'airtel'`; Azampay is the primary S3 integration. Mobile initiates payment via `POST /api/v1/payments/initiate`, then polls `GET /api/v1/payments/:id/status`. Refunds are triggered server-side on booking cancellation — mobile does not call the refund endpoint directly.

---

## Key Invariants

- **Route service endpoint**: `/api/v1/routes/me` (not `/mine`). The `/mine` fallback in `route_remote_datasource.dart` is dead code.
- **Field naming**: auth service schemas use camelCase (`fullName`); user service schemas use snake_case (`full_name`). Match the target service's Zod schema exactly.
- **`_toInt` in `booking_models.dart`** does not throw on null (returns 0); the same helper in `route_models.dart` also has a configurable fallback. Keep them consistent.
- **Notification reads** in the mobile notifications screen are currently local-only (no `PATCH /notifications/:id/read` call). Device token registration (`POST /api/v1/devices`) is not yet wired.
- Driver trip management (`start-trip`, `complete-trip`) exists on the backend (`POST /api/v1/bookings/:id/start-trip|complete-trip`) but is not yet implemented on mobile.
