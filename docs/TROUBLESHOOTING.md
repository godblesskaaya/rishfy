# Troubleshooting Runbook

> **When something breaks — start here.** This doc is a growing knowledge base of real issues the team has hit.

**How to use this doc:** Search for your error message (Ctrl+F). If it's not here, debug it, fix it, then add an entry so the next person doesn't re-solve your problem.

---

## Table of Contents

1. [Development Environment Issues](#1-development-environment-issues)
2. [Docker Compose Problems](#2-docker-compose-problems)
3. [Database Issues](#3-database-issues)
4. [Redis Issues](#4-redis-issues)
5. [Kafka Issues](#5-kafka-issues)
6. [Service Startup Issues](#6-service-startup-issues)
7. [API Gateway / NGINX Issues](#7-api-gateway--nginx-issues)
8. [Auth & JWT Issues](#8-auth--jwt-issues)
9. [gRPC Issues](#9-grpc-issues)
10. [Mobile Money / Webhook Issues](#10-mobile-money--webhook-issues)
11. [LATRA Compliance Issues](#11-latra-compliance-issues)
12. [Testing Issues](#12-testing-issues)

---

## 1. Development Environment Issues

### `setup.sh` fails: "docker compose not found"

**Cause:** You have the legacy `docker-compose` (Compose v1), not Compose v2.

**Fix:**
- Update Docker Desktop (v4.x includes Compose v2)
- Or Linux: `sudo apt-get install docker-compose-plugin`
- Verify: `docker compose version` → should show v2.x

---

### `setup.sh` fails: "Node.js 20+ required"

**Fix:** Install Node 20 LTS via `nvm`:

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
source ~/.bashrc
nvm install 20
nvm use 20
```

---

### `openssl: command not found`

**macOS:** `brew install openssl`
**Linux:** `sudo apt-get install openssl`
**Windows:** Use WSL2.

---

### Port already in use (80, 5432, 6379, etc.)

**Diagnose:**
```bash
# macOS/Linux
lsof -i :5432
# Linux alternative
ss -tlnp | grep 5432
```

**Fix options:**

1. Kill the conflicting process: `kill <PID>`
2. Or change Rishfy's port mapping in `docker-compose.yml`:
   ```yaml
   ports:
     - "5433:5432"   # Use 5433 on host
   ```
3. For local Postgres installations: `brew services stop postgresql` (macOS)

---

## 2. Docker Compose Problems

### `docker compose up` hangs at "waiting for services"

**Diagnose:**
```bash
./scripts/dev.sh ps
docker compose logs postgres | tail -50
```

**Common causes:**

- Not enough Docker resources — raise Docker Desktop's memory to at least 6GB
- Stale volumes from a previous run — `docker compose down -v` then retry
- Apple Silicon + non-ARM image — check image tags support `linux/arm64`

---

### `Error response from daemon: network rishfy_network not found`

**Fix:**
```bash
docker compose down
docker network prune
docker compose up -d
```

---

### Containers keep restarting

**Diagnose the crash:**
```bash
docker compose logs --tail=50 <service-name>
docker inspect <container-name> | grep -A 10 "State"
```

**Most common cause:** Missing or wrong environment variable. Check `.env` exists and has all required keys (compare against `.env.example`).

---

### "No space left on device"

Docker images and volumes accumulate.

```bash
docker system prune -a --volumes  # Nuclear option, frees GBs
docker volume prune              # Just unused volumes
```

---

## 3. Database Issues

### `ECONNREFUSED` when connecting to PostgreSQL

**Check:**
```bash
./scripts/dev.sh ps
# Is postgres listed as "healthy"?
```

If not healthy:
```bash
docker compose logs postgres --tail=30
```

Common sub-causes:

- **First-run init failed:** Check `init-databases.sql` didn't error. Usually PostGIS extension issues.
- **Volume has stale data:** `docker compose down -v` wipes the volume, then retry.

---

### `permission denied for schema public`

**Cause:** Wrong user connecting to a database they don't own.

**Recall:** Each service has its own DB user. `auth-service` must use `auth_user`, not `rishfy_root`.

**Fix:** Check `DATABASE_URL` in the service's env matches the pattern `postgres://<service>_user:...@postgres:5432/<service>_db`.

---

### PostGIS function not found (`ST_DWithin does not exist`)

**Cause:** PostGIS extension not enabled in the database.

**Fix:**
```bash
./scripts/dev.sh db route
```

Then in psql:
```sql
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_topology;
\dx
```

---

### Migration fails: "relation already exists"

**Cause:** Migration ran partially before failing; state is inconsistent.

**Fix (dev only!):**
```bash
./scripts/dev.sh db <service>
```
```sql
-- Check what's in pgmigrations
SELECT * FROM pgmigrations ORDER BY run_on DESC;
-- Manually mark a migration as run, or drop tables and re-run
```

**Safer alternative:** `docker compose down -v` and start fresh.

---

### TimescaleDB hypertable creation fails

**Error:** `function create_hypertable(...) does not exist`

**Fix:** We use the `timescale/timescaledb-ha` Docker image which includes TimescaleDB. If you swapped to plain `postgis/postgis`, TimescaleDB is missing. Restore the correct image in `docker-compose.yml`.

---

## 4. Redis Issues

### `MOVED` error when running commands

**Cause:** Trying to use Redis Cluster commands against a single-node Redis.

**Fix:** The dev env uses single-node Redis. Cluster mode is prod-only. Use regular commands, not `CLUSTER ...`.

---

### Redis keys evicted unexpectedly

**Cause:** `maxmemory-policy allkeys-lru` evicts oldest keys when memory is full.

**Fix (if needed):**
- Use a dedicated DB index per service (we already do: auth=0, user=1, ...)
- Set longer TTLs on critical keys
- For caches that must not evict, use `noeviction` policy and handle write failures

---

## 5. Kafka Issues

### Consumer lag keeps growing

**Diagnose:**
```bash
# In Kafka UI: http://localhost:8090
# Or via CLI:
docker compose exec kafka kafka-consumer-groups \
  --bootstrap-server localhost:9092 \
  --describe --group notification-service
```

**Common causes:**

- Consumer is slow (CPU-bound) — optimize or add partitions + more consumers
- Consumer crashing and restarting — check service logs
- Messages are large and network is bottlenecked — shrink payloads

---

### Topic auto-creation not working

**Check:** `KAFKA_AUTO_CREATE_TOPICS_ENABLE: "true"` in `docker-compose.yml` (already set for dev).

**For production:** Turn this OFF and pre-create topics with correct partition counts and replication factor.

---

### "Broker may not be available"

**Fix sequence:**
1. Verify Kafka is healthy: `./scripts/dev.sh status`
2. From inside the Docker network, use `kafka:9092` (not `localhost:29092`)
3. Service env has `KAFKA_BROKERS=kafka:9092` — check `.env` wasn't overridden

---

## 6. Service Startup Issues

### "Config validation failed"

Example:
```
ZodError: [
  { path: ["DATABASE_URL"], message: "Required" }
]
```

**Fix:** Missing env var. Check `.env.example` for the full list, copy to `.env`, fill in values.

---

### Service listens on port but doesn't accept connections from host

**Cause:** Service bound to `127.0.0.1` instead of `0.0.0.0`.

**Check** `src/server.ts`:
```typescript
await app.listen({ port, host: '0.0.0.0' });  // ✓
// NOT: await app.listen({ port });           // ✗ — defaults to localhost inside container
```

---

### Hot reload not working

**Cause:** Volume mount is out of sync, or `tsx watch` not running.

**Fix:**
```bash
./scripts/dev.sh restart <service>
```

If using a non-standard IDE or OS, volumes sometimes don't watch correctly. Workaround: rebuild the container.

---

## 7. API Gateway / NGINX Issues

### 502 Bad Gateway

**Cause:** Upstream service is down, crashing, or unreachable.

**Diagnose:**
```bash
./scripts/dev.sh status           # Any unhealthy?
docker compose logs nginx --tail=20
./scripts/dev.sh logs <upstream-service>
```

---

### 429 Rate Limited when testing

**Cause:** Hit the per-IP or per-endpoint limit while load testing.

**Temporary dev fix:** Raise the limit in `infrastructure/nginx.conf`:
```nginx
limit_req_zone $binary_remote_addr zone=global_ip:10m rate=300r/s;  # Was 30r/s
```
Then `docker compose restart nginx`.

**Don't commit these changes** — they're dev-only.

---

### CORS errors in mobile app / browser

**Current config:** `origin: true` in Fastify, permissive for dev.

**For production:** Set explicit allowed origins:
```typescript
await app.register(fastifyCors, {
  origin: ['https://rishfy.tz', 'https://app.rishfy.tz'],
  credentials: true,
});
```

---

## 8. Auth & JWT Issues

### "Invalid signature" errors

**Diagnose:**

1. Are services using the same `jwt_public_key.pem`? Check:
   ```bash
   docker compose exec auth-service cat /run/secrets/jwt_public_key | head -2
   docker compose exec user-service cat /run/secrets/jwt_public_key | head -2
   ```
2. Did the key change since the token was issued? Re-login to get a fresh token.

---

### OTP not delivered

**Dev environment:** SMS sandbox (AfricasTalking) may not actually deliver. OTP is also logged in `notification-service` logs:

```bash
./scripts/dev.sh logs notification | grep OTP
```

Look for the 6-digit code and use it.

---

### "Token expired" but user just logged in

**Clock skew!** Container clocks can drift. Check:
```bash
docker compose exec auth-service date
date
```

If >30s apart, restart Docker or sync host clock (on Linux: `sudo ntpdate time.google.com`).

---

## 9. gRPC Issues

### `UNAVAILABLE: No connection established`

**Cause:** gRPC server not yet started, or wrong port.

**Check:**
- Server is listening: `./scripts/dev.sh logs <service> | grep gRPC`
- Client URL matches: should be `<service>-service:<grpc-port>` inside the Docker network

---

### `UNIMPLEMENTED: The server does not implement this method`

**Cause:** `.proto` regenerated but server didn't reload, or method actually isn't implemented yet.

**Fix:**
1. Regenerate protos: `npm run proto:generate`
2. Restart service: `./scripts/dev.sh restart <service>`
3. If still failing, check the server actually registered the method (`grpc-server.ts`)

---

## 10. Mobile Money / Webhook Issues

### Webhook signature verification failing

**Diagnose:**
```bash
./scripts/dev.sh logs payment | grep "signature"
```

**Common causes:**

1. Provider and our service disagree on the hashing algorithm (HMAC-SHA256 vs SHA-1)
2. Body was modified by middleware (JSON re-serialization changes bytes)
3. Wrong secret — each provider has its own secret

**Fix:** Read the raw body for signature verification, not the parsed JSON. Our payment-service does this correctly — don't add body parsers before the verification middleware.

---

### Duplicate payments being created

**Cause:** Missing idempotency check on provider retries.

**Verify:**
- Every webhook handler checks `provider_reference` uniqueness before creating a payment
- Database has a unique constraint on `payments.provider_reference`

---

### Sandbox provider always fails

**Known quirk:** Some sandbox providers require specific phone number prefixes (like `+255700000000`) for successful test flows. Check provider docs for sandbox test numbers.

---

## 11. LATRA Compliance Issues

### LATRA report endpoint returns empty trips

**Check:**
1. Are there `COMPLETED` bookings in the date range?
2. Are they joined correctly to the trip records in location-service?
3. Is the requesting token using the `latra:read` scope?

```bash
./scripts/dev.sh db booking
```
```sql
SELECT status, COUNT(*) FROM bookings
WHERE trip_completed_at BETWEEN '2026-02-01' AND '2026-02-28'
GROUP BY status;
```

---

### LATRA test suite failing: "Invalid timestamp format"

**Cause:** LATRA spec requires `YYYY-MM-DD HH:MM:SS` (no 'T' separator, no decimal seconds).

**Fix:** Use the `formatForLATRA()` utility in `shared/utils` — don't call `.toISOString()` directly.

---

## 12. Testing Issues

### Testcontainers fail to start

**Error:** `Could not find a valid Docker environment`

**Fix:**
```bash
# Make sure Docker is running
docker ps
# Set the socket path if needed
export DOCKER_HOST=unix:///var/run/docker.sock
```

**macOS Docker Desktop 4.x:** Enable "Allow the default Docker socket to be used" in Settings → Advanced.

---

### Tests pass locally but fail in CI

Classic causes, in order of likelihood:

1. **Time zone:** CI often uses UTC; your machine doesn't. Use `date-fns-tz` and explicit zones in tests.
2. **Flaky tests:** Relies on timing (`setTimeout`, polling) — replace with deterministic fakes.
3. **Missing env var:** CI has different secrets; check CI logs for validation errors.
4. **Port conflicts:** CI runs services in parallel — use dynamic ports via testcontainers.

---

### Coverage suddenly dropped

**Cause:** Someone added uncovered code or removed tests.

**Fix:** Run locally with coverage and identify the gap:
```bash
npm run test:coverage
open coverage/index.html
```

---

## Adding New Entries

When you solve a weird issue, **add an entry**. Format:

```markdown
### Short, searchable error summary

**Cause:** What was actually wrong.

**Diagnose:**
```bash
commands to identify the issue
```

**Fix:** Clear steps to resolve.
```

The best runbook is one that grows with the team's collective debugging hours.
