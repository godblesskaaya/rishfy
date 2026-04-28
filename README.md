# Rishfy Platform

> **Tanzania's first D5-licensed digital ride-sharing platform**

[![License](https://img.shields.io/badge/License-Proprietary-red)]()
[![Node](https://img.shields.io/badge/Node-20.x_LTS-green)]()
[![TypeScript](https://img.shields.io/badge/TypeScript-5.x-blue)]()
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15+-336791)]()
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B)]()

---

## Project Overview

Rishfy solves Dar es Salaam's urban transport crisis by connecting private vehicle owners (drivers) with passengers traveling along shared routes. Unlike traditional ride-hailing, Rishfy focuses on **pre-scheduled commutes** using LATRA's D5 ride-sharing regulatory framework.

**Key Facts:**
- **Target Market**: 6M+ residents of Dar es Salaam
- **Regulatory**: LATRA D5 ride-sharing license (Tanzania's first)
- **Scale Target**: 1,000–50,000 active users (Phase 2 SOA)
- **Team**: 4 developers, 12-week academic timeline
- **Supervisor**: Dr. Abdullah Ally, University of Dar es Salaam

---

## Documentation Map

This repository contains the complete handoff package for development. Start here and follow the links.

### Essential Reading (Read in This Order)

| # | Document | Purpose | Audience |
|---|----------|---------|----------|
| 1 | [ARCHITECTURE.md](docs/ARCHITECTURE.md) | System design, service boundaries, tech decisions | All developers |
| 2 | [SETUP_GUIDE.md](docs/SETUP_GUIDE.md) | Get your dev environment running in 30 minutes | All developers |
| 3 | [REPO_STRUCTURE.md](docs/REPO_STRUCTURE.md) | Monorepo layout and conventions | All developers |
| 4 | [DATABASE_SCHEMA.md](docs/DATABASE_SCHEMA.md) | ERD, tables, relationships | Backend developers |
| 5 | [API_CONTRACTS.md](docs/API_CONTRACTS.md) | REST/gRPC/WebSocket specs per service | Backend + Mobile |
| 6 | [EVENT_SCHEMAS.md](docs/EVENT_SCHEMAS.md) | Async event definitions | Backend developers |
| 7 | [SPRINT_PLAN.md](docs/SPRINT_PLAN.md) | 12-week task breakdown | All developers + PM |
| 8 | [CODING_STANDARDS.md](docs/CODING_STANDARDS.md) | Style guide, commit conventions, PR process | All developers |
| 9 | [SPRINT1_STATUS_REVIEW.md](docs/SPRINT1_STATUS_REVIEW.md) | Audited current Sprint 1 implementation status and blockers | All developers |

### Reference Documents

| Document | Purpose |
|----------|---------|
| [LATRA_COMPLIANCE.md](docs/LATRA_COMPLIANCE.md) | Regulatory requirements mapping |
| [SECURITY.md](docs/SECURITY.md) | Security practices and threat model |
| [TESTING_STRATEGY.md](docs/TESTING_STRATEGY.md) | Unit, integration, E2E test approach |
| [DEPLOYMENT.md](docs/DEPLOYMENT.md) | CI/CD, environments, rollback |
| [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Common issues and fixes |

### Frontend Apps

| App | README | Purpose |
|-----|--------|---------|
| 📱 Mobile (Flutter) | [mobile/README.md](mobile/README.md) | Passenger + driver app (role toggle) |
| 🖥️ Admin (Next.js) | [admin/README.md](admin/README.md) | Admin dashboard for ops + LATRA reporting |

---

## Architecture at a Glance

Rishfy uses **Service-Oriented Architecture (SOA)** with 7 core services:

```
                      [ Flutter Mobile App ]
                              │
                              ▼
                      [ NGINX API Gateway ]
                              │
         ┌────────┬───────────┼───────────┬────────┐
         ▼        ▼           ▼           ▼        ▼
      [ Auth ] [ User ] [ Route ] [ Booking ] [ Payment ]
                    │       │          │          │
                    └───────┴──────────┴──────────┘
                              │
                  ┌───────────┼───────────┐
                  ▼           ▼           ▼
            [ Location ] [ Notify ]  [ LATRA Report ]
                  │           │           │
         ┌────────┴───────────┴───────────┘
         ▼
   [ PostgreSQL + PostGIS + TimescaleDB ]
   [ Redis Cache ]
   [ Kafka Event Bus ]
```

**Full architecture**: See [ARCHITECTURE.md](docs/ARCHITECTURE.md)

---

## Tech Stack

### Backend
- **Runtime**: Node.js 20.x LTS
- **Language**: TypeScript 5.x
- **Framework**: Fastify (REST), gRPC (inter-service)
- **Database**: PostgreSQL 15 + PostGIS + TimescaleDB
- **Cache**: Redis 7.x
- **Message Bus**: Apache Kafka 3.x
- **Auth**: JWT (access + refresh tokens) + OTP via SMS

### Mobile
- **Framework**: Flutter 3.x / Dart
- **State Management**: flutter_bloc
- **Real-time**: socket.io_client
- **Maps**: google_maps_flutter

### Infrastructure
- **Container**: Docker + Docker Compose (dev), Kubernetes (prod)
- **Reverse Proxy**: NGINX (SSL, rate limiting, load balancing)
- **Monitoring**: Prometheus + Grafana
- **Logging**: ELK Stack (Elasticsearch, Logstash, Kibana)
- **Tracing**: Jaeger
- **CI/CD**: GitHub Actions

### External Integrations
- **Payment**: M-Pesa, TigoPesa, Airtel Money
- **Maps**: Google Maps Platform (Places, Directions, Distance Matrix)
- **SMS**: Twilio / local provider (Beem, NextSMS)
- **Push**: Firebase Cloud Messaging (FCM)
- **Regulatory**: LATRA API (D5 reporting)

---

## Getting Started

### Prerequisites

```bash
# Required
Node.js 20.x LTS
Docker 24+
Docker Compose 2.x
Git
Flutter 3.x (for mobile)

# Recommended
Visual Studio Code + recommended extensions
Postman or Insomnia
DBeaver or pgAdmin
```

### Quick Setup (30 minutes)

```bash
# 1. Clone repository
git clone git@github.com:rishfy/platform.git
cd platform

# 2. Run the setup script
./scripts/setup.sh

# 3. Start all services
./scripts/dev.sh

# 4. Verify everything is running
curl http://localhost:8080/health

# 5. Open Swagger UI for API exploration
open http://localhost:8080/docs
```

**Detailed setup instructions**: See [SETUP_GUIDE.md](docs/SETUP_GUIDE.md)

---

## Team & Responsibilities

| Team Member | Registration | Primary Services | Secondary |
|-------------|--------------|------------------|-----------|
| **Stella Kahungo** | 2023-04-03737 | Auth Service, User Service | Mobile App |
| **Godbless Kaaya** | 2023-04-03579 | Route Service, Location Service | Mobile App |
| **Ezekiel Mazwa** | 2023-04-07139 | Booking Service, Payment Service | Admin Panel |
| **Fatma Abdallah** | 2023-04-00047 | Notification Service, LATRA Integration | Testing/QA |

**Note**: Assignments are suggested based on complexity balance. Adjust based on individual strengths and interest.

---

## Development Workflow

### Daily Workflow

```bash
# 1. Pull latest changes
git pull origin develop

# 2. Create feature branch
git checkout -b feature/RSHFY-123-add-otp-verification

# 3. Start dev environment
./scripts/dev.sh

# 4. Make changes, write tests
# ... code ...

# 5. Run tests
npm test

# 6. Run linter
npm run lint

# 7. Commit (follows conventional commits)
git commit -m "feat(auth): add OTP verification endpoint"

# 8. Push and create PR
git push origin feature/RSHFY-123-add-otp-verification
# Open PR to develop branch
```

### Branching Strategy

```
main         → Production (protected, auto-deploy)
  │
  └─ develop → Staging (protected, integration branch)
        │
        ├─ feature/RSHFY-XXX-description
        ├─ bugfix/RSHFY-XXX-description
        └─ hotfix/RSHFY-XXX-description
```

**Full workflow**: See [CODING_STANDARDS.md](docs/CODING_STANDARDS.md)

---

## Sprint Schedule

| Sprint | Weeks | Focus | Deliverable |
|--------|-------|-------|-------------|
| Sprint 0 | Pre-dev | Setup, onboarding, environment | All devs can run project locally |
| Sprint 1 | 1–2 | Infrastructure + Auth Service | Working JWT auth with OTP |
| Sprint 2 | 3–4 | User + Route Services | Drivers can post routes |
| Sprint 3 | 5–6 | Booking + Payment Services | End-to-end booking with M-Pesa |
| Sprint 4 | 7–8 | Location + Notification + Mobile | Real-time tracking working |
| Sprint 5 | 9–10 | Integration + LATRA compliance | Full E2E flow + LATRA reporting |
| Sprint 6 | 11–12 | Testing, polish, documentation | Production-ready submission |

**Full plan**: See [SPRINT_PLAN.md](docs/SPRINT_PLAN.md)

---

## Key Contacts

| Role | Name | Contact |
|------|------|---------|
| **Project Lead** | Blenko | [email] |
| **Supervisor** | Dr. Abdullah Ally | [email] |
| **Department** | Computer Science, UDSM | [email] |

---

## License & Confidentiality

This is a proprietary project developed as a Final Year Project at the University of Dar es Salaam. All code and documentation are confidential and not for redistribution without explicit permission.

© 2026 Rishfy Team, University of Dar es Salaam. All rights reserved.

---

## Next Steps for New Developers

1. ✅ Read this README completely
2. ✅ Read [ARCHITECTURE.md](docs/ARCHITECTURE.md) (45 min)
3. ✅ Complete [SETUP_GUIDE.md](docs/SETUP_GUIDE.md) (30 min)
4. ✅ Review your assigned services in [API_CONTRACTS.md](docs/API_CONTRACTS.md)
5. ✅ Check [SPRINT_PLAN.md](docs/SPRINT_PLAN.md) for your Sprint 1 tasks
6. ✅ Join the team Slack/Discord
7. ✅ Schedule pair programming session with team lead

**Questions?** Check [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) first, then ask in #dev-help.
