# route-service

**Owner:** Godbless Kaaya
**HTTP Port:** 8083
**gRPC Port:** 50053
**Database:** `route_db`

Route posting, geospatial search, seat reservations

## Quick Start

```bash
# From repo root
./scripts/dev.sh up
./scripts/dev.sh logs route
```

## Local Development

```bash
cd services/route
npm install
cp .env.example .env
npm run dev
```

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
