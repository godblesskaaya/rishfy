# notification-service

**Owner:** Fatma Abdallah
**HTTP Port:** 8087
**gRPC Port:** 50057
**Database:** `notification_db`

Push/SMS/email delivery, OTP sending

## Quick Start

```bash
# From repo root
./scripts/dev.sh up
./scripts/dev.sh logs notification
```

## Local Development

```bash
cd services/notification
npm install
cp .env.example .env
npm run dev
```

Push prerequisites:
- Set either `FIREBASE_SERVICE_ACCOUNT_JSON` or `FIREBASE_SERVICE_ACCOUNT_PATH`
- If the service account JSON does not include `project_id`, also set `FIREBASE_PROJECT_ID`
- In repo-local docker compose, replace `infrastructure/secrets/fcm_service_account.json` with a real Firebase Admin SDK service account before testing push delivery

## Testing

```bash
npm run test              # All tests
npm run test:unit         # Unit tests only
npm run test:integration  # Integration tests with testcontainers
npm run test:coverage     # Generate coverage report
```

## Structure

```
src/
├── server.ts         Entry point
├── app.ts            Fastify app factory
├── config.ts         Env config (Zod-validated)
├── logger.ts         Shared Pino logger
├── db.ts             Kysely DB client
├── redis.ts          Redis client
├── controllers/      REST route handlers
├── services/         Business logic
├── repositories/     DB access layer
├── clients/          Clients to other services (gRPC)
├── events/           Kafka producers & consumers
├── middleware/       Auth, validation, rate limiting
├── grpc/             gRPC server + service implementations
└── utils/            Helpers
```

## Documentation

- [Architecture overview](../../docs/ARCHITECTURE.md)
- [Database schema](../../docs/DATABASE_SCHEMA.md)
- [API contracts](../../docs/API_CONTRACTS.md)
- [Event schemas](../../docs/EVENT_SCHEMAS.md)
