# Rishfy Repository Structure

> **Monorepo layout and conventions**
> Repository: `github.com/rishfy/platform`

---

## Directory Layout

```
rishfy-platform/
├── .github/                      # GitHub-specific files
│   ├── workflows/                # GitHub Actions CI/CD
│   │   ├── ci.yml
│   │   ├── deploy-staging.yml
│   │   └── deploy-production.yml
│   ├── ISSUE_TEMPLATE/
│   └── PULL_REQUEST_TEMPLATE.md
│
├── .vscode/                      # VS Code workspace settings
│   ├── settings.json
│   ├── launch.json
│   └── extensions.json
│
├── api-contracts/                # OpenAPI 3.0 specifications
│   ├── auth-service.yaml
│   ├── user-service.yaml
│   ├── route-service.yaml
│   ├── booking-service.yaml
│   ├── payment-service.yaml
│   ├── location-service.yaml
│   ├── notification-service.yaml
│   └── admin-api.yaml
│
├── docs/                         # All documentation
│   ├── ARCHITECTURE.md
│   ├── API_CONTRACTS.md
│   ├── DATABASE_SCHEMA.md
│   ├── EVENT_SCHEMAS.md
│   ├── SETUP_GUIDE.md
│   ├── REPO_STRUCTURE.md
│   ├── SPRINT_PLAN.md
│   ├── CODING_STANDARDS.md
│   ├── LATRA_COMPLIANCE.md
│   ├── SECURITY.md
│   ├── TESTING_STRATEGY.md
│   ├── DEPLOYMENT.md
│   └── TROUBLESHOOTING.md
│
├── diagrams/                     # Source files for diagrams
│   ├── system-context.mermaid
│   ├── c4-container.mermaid
│   ├── booking-sequence.mermaid
│   └── er-master.mermaid
│
├── infrastructure/               # Infrastructure-as-code
│   ├── docker-compose.yml        # Local dev environment
│   ├── docker-compose.prod.yml   # Production overlay
│   ├── nginx/
│   │   ├── nginx.conf
│   │   └── conf.d/
│   ├── init-databases.sql        # Schema initialization
│   ├── prometheus/
│   │   └── prometheus.yml
│   ├── grafana/
│   │   ├── dashboards/
│   │   └── datasources/
│   └── k8s/                      # Kubernetes manifests (future)
│       ├── base/
│       └── overlays/
│
├── services/                     # All microservices
│   ├── auth/                     # Auth Service
│   ├── user/                     # User Service
│   ├── route/                    # Route Service
│   ├── booking/                  # Booking Service
│   ├── payment/                  # Payment Service
│   ├── location/                 # Location Service
│   └── notification/             # Notification Service
│
├── shared/                       # Code shared across services
│   ├── types/                    # TypeScript interfaces
│   │   ├── entities/
│   │   ├── events/
│   │   └── dto/
│   ├── protos/                   # gRPC .proto files
│   │   ├── auth.proto
│   │   ├── user.proto
│   │   ├── route.proto
│   │   ├── booking.proto
│   │   ├── payment.proto
│   │   └── location.proto
│   ├── utils/                    # Common utilities
│   │   ├── errors.ts
│   │   ├── logger.ts
│   │   ├── validators.ts
│   │   └── jwt.ts
│   └── constants/
│       ├── error-codes.ts
│       └── event-types.ts
│
├── mobile/                       # Flutter mobile app
│   ├── lib/
│   ├── android/
│   ├── ios/
│   ├── test/
│   └── pubspec.yaml
│
├── admin/                        # React admin panel (later)
│   ├── src/
│   └── package.json
│
├── scripts/                      # Automation scripts
│   ├── setup.sh                  # One-time setup
│   ├── dev.sh                    # Start dev environment
│   ├── seed.sh                   # Seed test data
│   ├── reset.sh                  # Reset everything
│   ├── backup.sh                 # Backup databases
│   └── seeds/                    # Seed data files
│       ├── 01_admin_user.sql
│       ├── 02_test_drivers.sql
│       └── 03_test_routes.sql
│
├── tests/                        # Cross-service integration tests
│   ├── e2e/
│   │   ├── booking-flow.test.ts
│   │   └── payment-flow.test.ts
│   └── load/                     # Load tests (k6 scripts)
│       └── booking-load.js
│
├── .env.example                  # Template for environment variables
├── .gitignore
├── .editorconfig
├── .nvmrc                        # Node version (20)
├── .prettierrc
├── .eslintrc.js
├── package.json                  # Root package.json (workspace root)
├── tsconfig.base.json            # Shared TypeScript config
├── turbo.json                    # Turborepo config (if used)
├── README.md                     # Main entry point
└── LICENSE
```

---

## Service Internal Structure

Every service in `services/<name>/` follows this exact layout:

```
services/<service-name>/
├── src/
│   ├── controllers/              # HTTP/gRPC request handlers
│   │   ├── auth.controller.ts
│   │   └── health.controller.ts
│   │
│   ├── services/                 # Business logic layer
│   │   ├── auth.service.ts
│   │   └── otp.service.ts
│   │
│   ├── repositories/             # Data access layer
│   │   ├── auth-user.repository.ts
│   │   └── refresh-token.repository.ts
│   │
│   ├── models/                   # Domain entities
│   │   └── auth-user.model.ts
│   │
│   ├── dto/                      # Data Transfer Objects
│   │   ├── requests/
│   │   │   ├── register.dto.ts
│   │   │   └── login.dto.ts
│   │   └── responses/
│   │       └── auth-response.dto.ts
│   │
│   ├── validators/               # Input validation schemas
│   │   ├── register.validator.ts
│   │   └── login.validator.ts
│   │
│   ├── middleware/               # Request middleware
│   │   ├── auth.middleware.ts
│   │   ├── error-handler.middleware.ts
│   │   └── request-logger.middleware.ts
│   │
│   ├── events/                   # Kafka publishers/consumers
│   │   ├── publishers/
│   │   │   └── user-registered.publisher.ts
│   │   └── consumers/
│   │       └── payment-completed.consumer.ts
│   │
│   ├── clients/                  # gRPC clients to other services
│   │   ├── user-service.client.ts
│   │   └── sms-provider.client.ts
│   │
│   ├── config/                   # Configuration
│   │   ├── env.config.ts
│   │   ├── database.config.ts
│   │   └── kafka.config.ts
│   │
│   ├── utils/                    # Service-specific utilities
│   │   └── password-hasher.ts
│   │
│   ├── types/                    # Service-specific types
│   │   └── index.ts
│   │
│   ├── grpc/                     # gRPC server implementation
│   │   └── auth-grpc.server.ts
│   │
│   ├── app.ts                    # Express/Fastify app setup
│   └── server.ts                 # Entry point (starts app)
│
├── tests/
│   ├── unit/                     # Unit tests (mirror src structure)
│   │   ├── services/
│   │   │   └── auth.service.test.ts
│   │   └── validators/
│   ├── integration/              # Integration tests
│   │   └── auth.integration.test.ts
│   ├── fixtures/                 # Test data
│   │   └── users.fixture.ts
│   └── helpers/                  # Test utilities
│       └── db-cleaner.ts
│
├── migrations/                   # Database migrations
│   ├── 1700000000001_initial_schema.js
│   └── 1700000000002_add_locked_until.js
│
├── protos/                       # Service's own gRPC definitions
│   └── auth.proto
│
├── Dockerfile
├── Dockerfile.dev                # For local development (hot reload)
├── package.json
├── tsconfig.json
├── jest.config.js
├── .env.example                  # Service-specific env template
└── README.md                     # Service-specific documentation
```

---

## Shared Code Strategy

### When to Use `shared/`

✅ **Put in shared**:
- TypeScript interfaces used across services (DTOs, entities)
- gRPC `.proto` files
- Error code constants
- Event type enums
- Pure utility functions (no service state)

❌ **Don't put in shared**:
- Business logic
- Database queries
- Service-specific configuration
- Anything that creates coupling

### Import Pattern

From a service:
```typescript
// Good
import { BookingCreatedEvent } from '@rishfy/shared/types/events';
import { ErrorCode } from '@rishfy/shared/constants/error-codes';

// Bad — don't import service code from other services
import { UserService } from '../../user/src/services/user.service'; // ❌
```

Service-to-service communication goes through gRPC or Kafka events only.

---

## Package Management

### Workspace Configuration

Root `package.json` uses npm workspaces:

```json
{
  "name": "rishfy-platform",
  "version": "1.0.0",
  "private": true,
  "workspaces": [
    "services/*",
    "shared",
    "admin"
  ],
  "scripts": {
    "build": "turbo run build",
    "test": "turbo run test",
    "lint": "turbo run lint",
    "dev": "./scripts/dev.sh"
  },
  "devDependencies": {
    "turbo": "^1.12.0",
    "typescript": "^5.3.0",
    "@types/node": "^20.10.0",
    "eslint": "^8.56.0",
    "prettier": "^3.2.0",
    "husky": "^9.0.0",
    "lint-staged": "^15.2.0"
  }
}
```

### Installing Dependencies

```bash
# Install a dependency in a specific service
npm install lodash --workspace=services/auth

# Install a dev dependency at root
npm install -D typescript

# Install everything
npm install
```

---

## Branching Strategy

```
main                          # Production (protected)
  │
  ├─ release/v1.0.0           # Release branches (frozen for testing)
  │
  └─ develop                  # Integration branch (protected)
        │
        ├─ feature/RSHFY-123-add-otp-verification
        ├─ feature/RSHFY-124-driver-search
        ├─ bugfix/RSHFY-125-login-timeout
        └─ hotfix/RSHFY-126-critical-payment-bug
```

### Branch Rules

| Branch | From | Merges To | Protection |
|--------|------|-----------|------------|
| `main` | `release/*` or `hotfix/*` | — | Requires PR + 2 approvals |
| `develop` | `feature/*`, `bugfix/*` | `release/*` | Requires PR + 1 approval + passing CI |
| `feature/*` | `develop` | `develop` | — |
| `bugfix/*` | `develop` | `develop` | — |
| `hotfix/*` | `main` | `main` + `develop` | Requires PR + 1 approval |
| `release/*` | `develop` | `main` + back to `develop` | Feature-frozen |

### Branch Naming

```
<type>/<ticket-id>-<short-description>

Examples:
feature/RSHFY-123-add-otp-verification
bugfix/RSHFY-125-login-timeout
hotfix/RSHFY-126-payment-double-charge
chore/RSHFY-127-update-dependencies
```

### Commit Messages (Conventional Commits)

Format:
```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types**:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `style`: Formatting (no logic change)
- `refactor`: Code refactor (no behavior change)
- `perf`: Performance improvement
- `test`: Adding/updating tests
- `chore`: Build/tooling changes
- `ci`: CI/CD changes

**Scope** (service or area):
- `auth`, `user`, `route`, `booking`, `payment`, `location`, `notification`
- `shared`, `infra`, `mobile`, `admin`, `docs`, `ci`

**Examples**:
```
feat(auth): add OTP rate limiting

Implements sliding window rate limit of 3 OTP requests per phone per minute.
Uses Redis for storage with 1-minute TTL.

Closes RSHFY-123
```

```
fix(payment): handle M-Pesa timeout gracefully

Previously, timeouts caused uncaught exceptions. Now returns 503 with
retry-after header.

Fixes RSHFY-145
```

### Pull Request Template

Located in `.github/PULL_REQUEST_TEMPLATE.md`:

```markdown
## Description
Brief description of what this PR does.

## Related Ticket
- [ ] RSHFY-XXX

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Checklist
- [ ] Code follows style guide
- [ ] Self-reviewed the code
- [ ] Added tests (unit + integration)
- [ ] All tests pass locally
- [ ] Updated documentation
- [ ] No secrets committed
- [ ] Migrations tested (up + down)

## Screenshots (if applicable)

## How to Test
Step-by-step testing instructions.
```

---

**Document Owner**: Platform Team
**Last Updated**: 2026-03-15
**Version**: 1.0
