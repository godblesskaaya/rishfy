# Rishfy Development Handoff Package

> **This document is your entry point. Read this first.**
>
> Everything in this repository is production-grade scaffolding, not throwaway academic code. When you start coding on Day 1, you will build on top of real foundations.

---

## What You're Looking At

This is a **complete, executable handoff package** prepared for the 4-person Rishfy development team. It contains:

- **13 comprehensive documentation files** covering architecture, APIs, databases, events, security, testing, deployment, and operations
- **Complete infrastructure** as code (Docker Compose, NGINX, Prometheus, init scripts)
- **Service scaffolding for all 7 microservices** with consistent TypeScript/Fastify boilerplate
- **8 protobuf files** defining every gRPC contract between services
- **Flutter mobile app** — auth flow end-to-end, 11 screens, Riverpod state, go_router, localization (EN/SW)
- **Next.js 14 admin dashboard** — NextAuth, shadcn/ui, TanStack Query, 9 pages including LATRA export
- **Automated setup scripts** that take you from fresh clone to running stack in ~10 minutes
- **CI/CD-ready config** (ESLint, Prettier, commitlint, Vitest)

Total: **200+ files, ~25,000 lines** of carefully-designed foundation across backend, mobile, and admin.

---

## Day 1 Checklist (Each Developer)

### 1. Machine Setup (30 min)

Install prerequisites:

- Docker Desktop 24+ (with Compose v2)
- Node.js 20 LTS (use `nvm`)
- Flutter 3.x (only needed if working on mobile)
- Git, VS Code (recommended) or your preferred IDE

### 2. Clone & Bootstrap (10 min)

```bash
git clone git@github.com:rishfy/rishfy.git
cd rishfy
./scripts/setup.sh
```

That's it. The script handles:
- Prerequisite checks
- `.env` generation
- JWT keypair generation
- Dependency installation for all services
- Protobuf code generation
- Starting the full stack in Docker
- Running database migrations

### 3. Verify (5 min)

```bash
curl http://localhost/health          # Should return 200
./scripts/dev.sh status               # All services "healthy"
open http://localhost/docs            # Swagger UI
open http://localhost:8090            # Kafka UI
open http://localhost:3001            # Grafana (admin/admin)
```

### 4. Read the Essentials (2 hours, in order)

1. [**`docs/ARCHITECTURE.md`**](docs/ARCHITECTURE.md) — How the system fits together
2. [**`docs/REPO_STRUCTURE.md`**](docs/REPO_STRUCTURE.md) — Where things live and why
3. [**`docs/DATABASE_SCHEMA.md`**](docs/DATABASE_SCHEMA.md) — Data model
4. [**`docs/API_CONTRACTS.md`**](docs/API_CONTRACTS.md) — External HTTP endpoints
5. [**Your service's README**](services/) (e.g., `services/auth/README.md`) — What you're building

### 5. Know Your Specialty

| Developer | Backend Services | Frontend Track |
|---|---|---|
| **Stella Kahungo** | auth, user | — |
| **Godbless Kaaya** | route, location | **Admin dashboard lead** (Next.js) |
| **Ezekiel Mazwa** | booking, payment | — |
| **Fatma Abdallah** | notification, LATRA integration | **Mobile app lead** (Flutter) |

You own your services end-to-end but everyone contributes features for their own services on mobile + admin. Cross-cutting concerns (theme, router, gateway, shared types, auth) are reviewed by all.

---

## Package Contents by Purpose

### "I need to understand the system" → Start here

- [`README.md`](README.md) — Project overview
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — System design + ADRs
- [`docs/DATABASE_SCHEMA.md`](docs/DATABASE_SCHEMA.md) — ERD + all tables
- [`docs/SECURITY.md`](docs/SECURITY.md) — Threat model + auth design

### "I need to write code"

- [`docs/REPO_STRUCTURE.md`](docs/REPO_STRUCTURE.md) — Directory layout
- [`docs/CODING_STANDARDS.md`](docs/CODING_STANDARDS.md) — Style, commits, PR process
- [`docs/API_CONTRACTS.md`](docs/API_CONTRACTS.md) — REST specs
- [`docs/EVENT_SCHEMAS.md`](docs/EVENT_SCHEMAS.md) — Kafka topic definitions
- [`shared/protos/`](shared/protos/) — gRPC contracts (source of truth for inter-service APIs)
- [`services/<yours>/`](services/) — Your service starter

### "I need to work on the mobile app"

- [`mobile/README.md`](mobile/README.md) — Flutter setup, architecture, testing
- [`mobile/lib/features/`](mobile/lib/) — Feature modules (auth, bookings, routes, trip, etc.)
- [`mobile/lib/core/`](mobile/lib/core/) — Cross-cutting: network, router, theme, storage
- Run: `cd mobile && flutter pub get && flutter run --dart-define=ENV=dev`

### "I need to work on the admin dashboard"

- [`admin/README.md`](admin/README.md) — Next.js setup, architecture, patterns
- [`admin/app/(dashboard)/`](admin/app/) — Dashboard pages
- [`admin/components/ui/`](admin/components/ui/) — shadcn/ui primitives
- [`admin/lib/api/endpoints.ts`](admin/lib/api/endpoints.ts) — Typed backend calls
- Run: `cd admin && npm install && npm run dev`

### "I need to set something up"

- [`docs/SETUP_GUIDE.md`](docs/SETUP_GUIDE.md) — Dev env walkthrough
- [`scripts/setup.sh`](scripts/setup.sh) — One-command bootstrap
- [`scripts/dev.sh`](scripts/dev.sh) — Daily dev helper
- [`docker-compose.yml`](docker-compose.yml) — Full stack definition

### "I need to test something"

- [`docs/TESTING_STRATEGY.md`](docs/TESTING_STRATEGY.md) — Pyramid + tooling
- Each service's `tests/` directory (unit + integration + fixtures)

### "I need to deploy"

- [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) — Topology + CI/CD
- [`infrastructure/nginx.conf`](infrastructure/nginx.conf) — API gateway
- [`infrastructure/prometheus.yml`](infrastructure/prometheus.yml) — Metrics

### "I need to plan"

- [`docs/SPRINT_PLAN.md`](docs/SPRINT_PLAN.md) — 12-week breakdown

### "I need to comply with LATRA"

- [`docs/LATRA_COMPLIANCE.md`](docs/LATRA_COMPLIANCE.md) — Requirements mapping

### "Something is broken"

- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) — Common issues
- [`./scripts/dev.sh logs <service>`](scripts/dev.sh) — Tail logs

---

## Architectural Principles (Non-Negotiable)

These decisions are locked in — don't re-litigate them without a full team discussion + supervisor sign-off.

1. **Database-per-service.** No cross-service FKs in PostgreSQL. Join at the app layer via gRPC.
2. **Service-to-service via gRPC.** Public-facing APIs only via REST through NGINX.
3. **Events via Kafka.** Async workflows (e.g., post-booking notifications) are always event-driven, never synchronous call chains.
4. **JWT RS256 only.** No HS256 secrets shared across services.
5. **Idempotency keys on all write endpoints.** Clients must send, services must check.
6. **LATRA compliance is a first-class concern.** Every feature considers the 11 required fields.
7. **Mobile-money-first, card-money-later.** M-Pesa/TigoPesa/Airtel before any other payment method.
8. **English + Swahili from Day 1.** All user-facing strings are localized.

---

## What's Deliberately NOT in This Package

We scoped this to what the team needs to start coding. Deferred to when you're ready:

- **Actual production Kubernetes manifests** — templates in `docs/DEPLOYMENT.md`; real manifests come when we pick a cloud provider
- **Grafana dashboard JSON** — infrastructure is ready, dashboards will be built alongside services
- **Production secrets management** — dev uses file-based; prod decision comes at deployment time
- **Firebase project config** — see `mobile/README.md` for setup steps; each env gets its own project
- **CI/CD pipeline YAML files** — templates documented in `DEPLOYMENT.md`, concrete files when you set up the GitHub repo

These are explicitly NOT blockers for starting development.

---

## Questions & Escalation

- **Technical questions about a service** → Ask the service owner first
- **Cross-cutting concerns (auth, gateway, shared types)** → Team discussion in PR review
- **Regulatory questions (LATRA)** → Fatma + supervisor
- **Academic deliverables** → Supervisor
- **Something genuinely broken in this package** → Open an issue in the team channel and we'll fix it

---

## How This Package Was Built

This scaffolding was prepared to reduce time-to-first-commit for the whole team. Every file here has been designed to:

1. Run correctly on Day 1 (infrastructure is executable, not aspirational)
2. Scale to Phase 2 targets (1K–50K users) without architectural rewrites
3. Satisfy LATRA's D5 requirements by design, not retrofit
4. Serve as living documentation — not shelfware

**Update it as you learn.** If something here is wrong, outdated, or could be clearer, fix it in a PR. The next developer will thank you.

---

## Good Luck

You have 12 weeks. The hard architectural decisions are made. The infrastructure is running. The contracts are defined. Go build something great.

— Drafted Sprint 0, ready for Sprint 1 kickoff.
