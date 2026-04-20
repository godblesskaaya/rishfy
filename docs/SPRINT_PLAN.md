# Rishfy Sprint Plan

> **12-week development roadmap**
> Team: 4 developers
> Methodology: 2-week sprints with Agile/Scrum lite
> Total: 6 sprints + Sprint 0

---

## Overview

| Sprint | Weeks | Theme | Primary Deliverable |
|--------|-------|-------|---------------------|
| **Sprint 0** | Pre-dev | Foundation | Team onboarded, env running, skeleton services |
| **Sprint 1** | 1–2 | Infrastructure + Auth | Working JWT auth with OTP |
| **Sprint 2** | 3–4 | Users + Routes | Drivers can post routes |
| **Sprint 3** | 5–6 | Bookings + Payments | End-to-end booking with M-Pesa |
| **Sprint 4** | 7–8 | Location + Mobile | Real-time tracking working |
| **Sprint 5** | 9–10 | Integration + LATRA | Full E2E + compliance reporting |
| **Sprint 6** | 11–12 | Polish + Docs | Production-ready submission |

**Ticket prefix**: `RSHFY-XXX`

---

## Team Allocation

| Developer | Sprint 0 | Sprint 1 | Sprint 2 | Sprint 3 | Sprint 4 | Sprint 5 | Sprint 6 |
|-----------|----------|----------|----------|----------|----------|----------|----------|
| **Stella** | Setup, Auth scaffolding | Auth Service | User Service | User API polish | Mobile: Auth flows | LATRA verify | Testing |
| **Godbless** | Setup, Infra | Infra + Gateway | Route Service | Route matching algo | Location + WebSocket | Mobile: Maps | Testing |
| **Ezekiel** | Setup, DB design | Database layer | Booking Service | Payment Service + M-Pesa | Booking flows | LATRA reporting | Testing |
| **Fatma** | Setup, Docs | Shared utilities | Notification Service | SMS + Push | Mobile: Notifications | QA + E2E tests | Docs + Demo |

---

## Sprint 0: Foundation (Pre-Development Week)

**Goal**: Every developer can run the platform locally and has scaffolded their services.

### Tasks

| # | Ticket | Title | Assignee | Points |
|---|--------|-------|----------|--------|
| 1 | RSHFY-001 | Set up monorepo with Turborepo | Godbless | 3 |
| 2 | RSHFY-002 | Configure ESLint + Prettier + Husky | Fatma | 2 |
| 3 | RSHFY-003 | Write Dockerfiles for all 7 services | Godbless | 5 |
| 4 | RSHFY-004 | Create docker-compose.yml with PG + Redis + Kafka | Godbless | 5 |
| 5 | RSHFY-005 | Write init-databases.sql | Ezekiel | 3 |
| 6 | RSHFY-006 | Write setup.sh and dev.sh scripts | Godbless | 3 |
| 7 | RSHFY-007 | Scaffold Auth Service (basic structure) | Stella | 3 |
| 8 | RSHFY-008 | Scaffold User Service | Stella | 2 |
| 9 | RSHFY-009 | Scaffold Route Service | Godbless | 2 |
| 10 | RSHFY-010 | Scaffold Booking Service | Ezekiel | 2 |
| 11 | RSHFY-011 | Scaffold Payment Service | Ezekiel | 2 |
| 12 | RSHFY-012 | Scaffold Location Service | Godbless | 2 |
| 13 | RSHFY-013 | Scaffold Notification Service | Fatma | 2 |
| 14 | RSHFY-014 | Set up GitHub Actions CI pipeline | Fatma | 5 |
| 15 | RSHFY-015 | Create shared types package | Fatma | 3 |
| 16 | RSHFY-016 | Write API Gateway NGINX config | Godbless | 3 |
| 17 | RSHFY-017 | Write PULL_REQUEST_TEMPLATE and contributing docs | All | 2 |

**Total**: 49 points

**Sprint 0 Definition of Done**:
- [ ] Every developer has cloned repo and run `./scripts/dev.sh` successfully
- [ ] All 7 services return 200 on `/health`
- [ ] CI runs on every PR (lint + test)
- [ ] Each service has a README with setup instructions

---

## Sprint 1: Infrastructure + Auth (Weeks 1–2)

**Goal**: Fully functional Auth Service with JWT + OTP.

### Epic: User Authentication
- RSHFY-100: Auth Service MVP

| # | Ticket | Title | Assignee | Points |
|---|--------|-------|----------|--------|
| 1 | RSHFY-101 | Implement `POST /auth/register` with phone/email validation | Stella | 3 |
| 2 | RSHFY-102 | Implement OTP generation + SMS integration (mock + Beem) | Stella | 5 |
| 3 | RSHFY-103 | Implement `POST /auth/verify-otp` | Stella | 3 |
| 4 | RSHFY-104 | Implement `POST /auth/login` with bcrypt password check | Stella | 3 |
| 5 | RSHFY-105 | Implement JWT access + refresh token generation | Stella | 5 |
| 6 | RSHFY-106 | Implement `POST /auth/refresh-token` with rotation | Stella | 3 |
| 7 | RSHFY-107 | Implement `POST /auth/logout` | Stella | 2 |
| 8 | RSHFY-108 | Implement `POST /auth/reset-password` | Stella | 3 |
| 9 | RSHFY-109 | Implement account lockout after 5 failed logins | Stella | 3 |
| 10 | RSHFY-110 | Implement rate limiting on auth endpoints | Stella | 3 |
| 11 | RSHFY-111 | Add unit tests for auth service (80% coverage) | Stella | 5 |
| 12 | RSHFY-112 | Add integration tests for auth flows | Stella | 5 |

### Epic: API Gateway & Infrastructure

| # | Ticket | Title | Assignee | Points |
|---|--------|-------|----------|--------|
| 13 | RSHFY-113 | Implement NGINX JWT validation | Godbless | 5 |
| 14 | RSHFY-114 | Implement rate limiting at gateway | Godbless | 3 |
| 15 | RSHFY-115 | Set up Prometheus + Grafana dashboards | Godbless | 5 |
| 16 | RSHFY-116 | Set up centralized logging (structured JSON) | Godbless | 3 |
| 17 | RSHFY-117 | Set up Jaeger for distributed tracing | Godbless | 3 |

### Epic: Shared Libraries

| # | Ticket | Title | Assignee | Points |
|---|--------|-------|----------|--------|
| 18 | RSHFY-118 | Build shared error handling library | Fatma | 3 |
| 19 | RSHFY-119 | Build shared logger with correlation IDs | Fatma | 3 |
| 20 | RSHFY-120 | Build shared Kafka producer/consumer utilities | Fatma | 5 |
| 21 | RSHFY-121 | Build shared Redis client wrapper | Fatma | 2 |

### Epic: Database Foundation

| # | Ticket | Title | Assignee | Points |
|---|--------|-------|----------|--------|
| 22 | RSHFY-122 | Implement migration tooling (node-pg-migrate) | Ezekiel | 3 |
| 23 | RSHFY-123 | Write migrations for auth_db | Ezekiel | 3 |
| 24 | RSHFY-124 | Write seed data for development | Ezekiel | 3 |

**Total**: 84 points

**Sprint 1 Definition of Done**:
- [ ] Can register → receive OTP → verify → login → refresh → logout via Postman
- [ ] All auth endpoints protected by rate limits
- [ ] Logs visible in Grafana dashboard
- [ ] Jaeger shows traces across gateway → auth service
- [ ] 80%+ test coverage for Auth Service
- [ ] Swagger UI shows all auth endpoints

---

## Sprint 2: Users + Routes (Weeks 3–4)

**Goal**: Drivers can register, add vehicles, and post routes.

### Epic: User Service

| # | Ticket | Title | Assignee | Points |
|---|--------|-------|----------|--------|
| 1 | RSHFY-200 | Implement `GET /users/me` | Stella | 2 |
| 2 | RSHFY-201 | Implement `PATCH /users/me` | Stella | 2 |
| 3 | RSHFY-202 | Implement profile picture upload (S3/local) | Stella | 5 |
| 4 | RSHFY-203 | Implement `POST /users/me/become-driver` | Stella | 3 |
| 5 | RSHFY-204 | Implement vehicle CRUD endpoints | Stella | 5 |
| 6 | RSHFY-205 | Implement active vehicle selection | Stella | 2 |
| 7 | RSHFY-206 | Implement device registration for FCM | Stella | 3 |
| 8 | RSHFY-207 | Implement `GET /users/drivers/{id}/public` | Stella | 2 |
| 9 | RSHFY-208 | Implement gRPC server for user lookup | Stella | 5 |
| 10 | RSHFY-209 | Publish `user.registered` and `user.driver_upgraded` events | Stella | 3 |
| 11 | RSHFY-210 | Consume `rating.submitted` to update averages | Stella | 3 |
| 12 | RSHFY-211 | Add unit + integration tests | Stella | 5 |

### Epic: Route Service

| # | Ticket | Title | Assignee | Points |
|---|--------|-------|----------|--------|
| 13 | RSHFY-212 | Set up PostGIS extension and geography types | Godbless | 3 |
| 14 | RSHFY-213 | Implement `POST /routes` with Google Maps integration | Godbless | 5 |
| 15 | RSHFY-214 | Implement `GET /routes/search` with PostGIS queries | Godbless | 8 |
| 16 | RSHFY-215 | Implement `GET /routes/{id}` | Godbless | 2 |
| 17 | RSHFY-216 | Implement `PATCH /routes/{id}` with business rules | Godbless | 3 |
| 18 | RSHFY-217 | Implement `DELETE /routes/{id}` (cancellation) | Godbless | 3 |
| 19 | RSHFY-218 | Implement `GET /routes/me` (driver's routes) | Godbless | 2 |
| 20 | RSHFY-219 | Implement route caching with Redis | Godbless | 3 |
| 21 | RSHFY-220 | Implement recurring route generation | Godbless | 5 |
| 22 | RSHFY-221 | Implement gRPC client to User Service | Godbless | 3 |
| 23 | RSHFY-222 | Publish `route.cancelled_by_driver` events | Godbless | 2 |
| 24 | RSHFY-223 | Add unit + integration tests | Godbless | 5 |

### Epic: Mobile Foundation

| # | Ticket | Title | Assignee | Points |
|---|--------|-------|----------|--------|
| 25 | RSHFY-224 | Set up Flutter project structure | Fatma | 3 |
| 26 | RSHFY-225 | Implement registration/login screens | Fatma | 5 |
| 27 | RSHFY-226 | Implement profile screen | Fatma | 3 |
| 28 | RSHFY-227 | Set up state management (flutter_bloc) | Fatma | 3 |

### Epic: Documentation

| # | Ticket | Title | Assignee | Points |
|---|--------|-------|----------|--------|
| 29 | RSHFY-228 | Update API docs for user + route services | Ezekiel | 2 |

**Total**: 93 points

**Sprint 2 Definition of Done**:
- [ ] User can register → become driver → add vehicle → post route (via Postman and mobile)
- [ ] Passenger can search routes by origin/destination
- [ ] PostGIS queries return within 500ms for city-wide searches
- [ ] Mobile app has working auth + profile screens
- [ ] All endpoints documented in Swagger UI

---

## Sprint 3: Bookings + Payments (Weeks 5–6)

**Goal**: End-to-end booking with real M-Pesa integration.

### Epic: Booking Service

| # | Ticket | Title | Assignee | Points |
|---|--------|-------|----------|--------|
| 1 | RSHFY-300 | Implement `POST /bookings` with seat reservation via gRPC | Ezekiel | 5 |
| 2 | RSHFY-301 | Implement booking expiry (2-min timeout job) | Ezekiel | 3 |
| 3 | RSHFY-302 | Implement `GET /bookings/{id}` and `GET /bookings/me` | Ezekiel | 3 |
| 4 | RSHFY-303 | Implement `POST /bookings/{id}/cancel` with refund rules | Ezekiel | 5 |
| 5 | RSHFY-304 | Implement `POST /bookings/{id}/start-trip` | Ezekiel | 3 |
| 6 | RSHFY-305 | Implement `POST /bookings/{id}/complete-trip` | Ezekiel | 3 |
| 7 | RSHFY-306 | Implement `POST /bookings/{id}/rate` | Ezekiel | 3 |
| 8 | RSHFY-307 | Implement `POST /bookings/{id}/emergency` | Ezekiel | 3 |
| 9 | RSHFY-308 | Implement confirmation code generation (8-char unique) | Ezekiel | 2 |
| 10 | RSHFY-309 | Publish all booking events (created/confirmed/cancelled/etc.) | Ezekiel | 5 |
| 11 | RSHFY-310 | Consume `payment.completed` and `payment.failed` | Ezekiel | 3 |
| 12 | RSHFY-311 | Add booking audit trail (booking_events table) | Ezekiel | 3 |
| 13 | RSHFY-312 | Add unit + integration tests | Ezekiel | 5 |

### Epic: Payment Service

| # | Ticket | Title | Assignee | Points |
|---|--------|-------|----------|--------|
| 14 | RSHFY-313 | Design PaymentProvider interface | Ezekiel | 3 |
| 15 | RSHFY-314 | Implement M-Pesa Daraja STK Push integration | Ezekiel | 8 |
| 16 | RSHFY-315 | Implement M-Pesa callback handler with signature verification | Ezekiel | 5 |
| 17 | RSHFY-316 | Implement TigoPesa integration | Ezekiel | 5 |
| 18 | RSHFY-317 | Implement Airtel Money integration | Ezekiel | 5 |
| 19 | RSHFY-318 | Implement `POST /payments/initiate` with idempotency | Ezekiel | 3 |
| 20 | RSHFY-319 | Implement `GET /payments/{id}/status` | Ezekiel | 2 |
| 21 | RSHFY-320 | Implement payment splits (driver earning + platform fee) | Ezekiel | 3 |
| 22 | RSHFY-321 | Implement refund flow | Ezekiel | 5 |
| 23 | RSHFY-322 | Implement driver earnings summary endpoint | Ezekiel | 3 |
| 24 | RSHFY-323 | Publish `payment.completed/failed/refunded` events | Ezekiel | 3 |
| 25 | RSHFY-324 | Add unit + integration tests (with mocked providers) | Ezekiel | 5 |

### Epic: Notification Service

| # | Ticket | Title | Assignee | Points |
|---|--------|-------|----------|--------|
| 26 | RSHFY-325 | Implement notification queue with priority | Fatma | 3 |
| 27 | RSHFY-326 | Implement notification worker with retry | Fatma | 3 |
| 28 | RSHFY-327 | Implement notification templates (EN + SW) | Fatma | 3 |
| 29 | RSHFY-328 | Consume booking + payment events | Fatma | 5 |
| 30 | RSHFY-329 | Implement `GET /notifications/me` | Fatma | 2 |
| 31 | RSHFY-330 | Implement mark-as-read endpoints | Fatma | 2 |
| 32 | RSHFY-331 | Add unit + integration tests | Fatma | 3 |

### Epic: Mobile

| # | Ticket | Title | Assignee | Points |
|---|--------|-------|----------|--------|
| 33 | RSHFY-332 | Implement route search UI | Fatma | 5 |
| 34 | RSHFY-333 | Implement booking flow UI | Fatma | 5 |
| 35 | RSHFY-334 | Integrate M-Pesa STK UI | Fatma | 5 |

**Total**: 127 points

**Sprint 3 Definition of Done**:
- [ ] Passenger can: search → book → pay with M-Pesa → receive confirmation
- [ ] Driver receives SMS + push on new booking
- [ ] Payment flow works end-to-end with real M-Pesa sandbox
- [ ] All events flow correctly through Kafka
- [ ] Notifications deliver within 5 seconds

---

## Sprint 4: Location + Notifications + Mobile (Weeks 7–8)

**Goal**: Real-time driver tracking with maps.

### Epic: Location Service

| # | Ticket | Title | Assignee | Points |
|---|--------|-------|----------|--------|
| 1 | RSHFY-400 | Set up TimescaleDB hypertables | Godbless | 3 |
| 2 | RSHFY-401 | Implement WebSocket server (socket.io) | Godbless | 5 |
| 3 | RSHFY-402 | Implement driver location update flow | Godbless | 5 |
| 4 | RSHFY-403 | Implement passenger subscription to trip | Godbless | 3 |
| 5 | RSHFY-404 | Implement Redis geospatial index | Godbless | 3 |
| 6 | RSHFY-405 | Implement driver arrival detection (100m radius) | Godbless | 5 |
| 7 | RSHFY-406 | Implement `GET /location/drivers/{id}/current` | Godbless | 3 |
| 8 | RSHFY-407 | Implement trip path storage on completion | Godbless | 3 |
| 9 | RSHFY-408 | Publish `driver.arrived` and `driver.location.updated` events | Godbless | 3 |
| 10 | RSHFY-409 | Implement compression policies | Godbless | 2 |
| 11 | RSHFY-410 | Add unit + integration tests | Godbless | 5 |

### Epic: Push Notifications

| # | Ticket | Title | Assignee | Points |
|---|--------|-------|----------|--------|
| 12 | RSHFY-411 | Integrate Firebase Cloud Messaging | Fatma | 5 |
| 13 | RSHFY-412 | Implement push notification delivery | Fatma | 3 |
| 14 | RSHFY-413 | Handle token refresh and invalidation | Fatma | 3 |
| 15 | RSHFY-414 | Implement silent notifications (for refresh) | Fatma | 3 |

### Epic: Mobile App

| # | Ticket | Title | Assignee | Points |
|---|--------|-------|----------|--------|
| 16 | RSHFY-415 | Integrate Google Maps in Flutter | Godbless | 5 |
| 17 | RSHFY-416 | Implement real-time driver tracking on map | Godbless | 8 |
| 18 | RSHFY-417 | Implement driver location broadcasting | Fatma | 5 |
| 19 | RSHFY-418 | Implement trip in-progress screen | Fatma | 5 |
| 20 | RSHFY-419 | Implement ratings UI | Fatma | 3 |
| 21 | RSHFY-420 | Implement notification list screen | Fatma | 3 |
| 22 | RSHFY-421 | Implement driver mode (separate UI) | Stella | 5 |
| 23 | RSHFY-422 | Implement emergency button | Stella | 3 |

### Epic: Admin Panel MVP

| # | Ticket | Title | Assignee | Points |
|---|--------|-------|----------|--------|
| 24 | RSHFY-423 | Set up React admin panel project | Ezekiel | 3 |
| 25 | RSHFY-424 | Implement admin login | Ezekiel | 3 |
| 26 | RSHFY-425 | Implement user list + search | Ezekiel | 3 |
| 27 | RSHFY-426 | Implement metrics dashboard | Ezekiel | 5 |

**Total**: 100 points

**Sprint 4 Definition of Done**:
- [ ] Passenger sees driver moving in real-time on map
- [ ] Driver gets push notification when passenger books
- [ ] "Driver has arrived" notification triggers correctly
- [ ] Mobile app works end-to-end for rider flow
- [ ] Admin can view users and metrics

---

## Sprint 5: Integration + LATRA Compliance (Weeks 9–10)

**Goal**: Full LATRA compliance + polished end-to-end flows.

### Epic: LATRA Compliance

| # | Ticket | Title | Assignee | Points |
|---|--------|-------|----------|--------|
| 1 | RSHFY-500 | Build mock LATRA server for testing | Ezekiel | 5 |
| 2 | RSHFY-501 | Implement LATRA Reporter service (cron-based) | Ezekiel | 5 |
| 3 | RSHFY-502 | Implement trip data export in LATRA JSON format | Ezekiel | 3 |
| 4 | RSHFY-503 | Implement OAuth 2.0 client for LATRA | Ezekiel | 3 |
| 5 | RSHFY-504 | Implement vehicle verification integration (mock) | Stella | 3 |
| 6 | RSHFY-505 | Implement driver LATRA verification flow (admin) | Stella | 3 |
| 7 | RSHFY-506 | Audit logging for all admin actions | Ezekiel | 5 |
| 8 | RSHFY-507 | Implement `GET /admin/latra/report` endpoint | Ezekiel | 3 |

### Epic: Feature Completion

| # | Ticket | Title | Assignee | Points |
|---|--------|-------|----------|--------|
| 9 | RSHFY-508 | Implement emergency contact SMS | Fatma | 3 |
| 10 | RSHFY-509 | Implement driver rating aggregation | Stella | 3 |
| 11 | RSHFY-510 | Implement trip history with paths on map | Fatma | 5 |
| 12 | RSHFY-511 | Implement recurring route UI (mobile) | Godbless | 5 |
| 13 | RSHFY-512 | Implement in-app notification preferences | Fatma | 3 |

### Epic: Testing & Quality

| # | Ticket | Title | Assignee | Points |
|---|--------|-------|----------|--------|
| 14 | RSHFY-513 | Write E2E test: full booking flow | Fatma | 5 |
| 15 | RSHFY-514 | Write E2E test: full driver flow | Fatma | 5 |
| 16 | RSHFY-515 | Write E2E test: cancellation + refund | Fatma | 3 |
| 17 | RSHFY-516 | Write load tests (k6) for 1000 concurrent users | Godbless | 5 |
| 18 | RSHFY-517 | Security audit: run OWASP ZAP scan | Fatma | 3 |
| 19 | RSHFY-518 | Fix security findings | All | 5 |

### Epic: Admin Polish

| # | Ticket | Title | Assignee | Points |
|---|--------|-------|----------|--------|
| 20 | RSHFY-519 | Admin: booking search and details | Ezekiel | 3 |
| 21 | RSHFY-520 | Admin: driver verification queue | Stella | 3 |
| 22 | RSHFY-521 | Admin: emergency alerts dashboard | Ezekiel | 3 |

**Total**: 84 points

**Sprint 5 Definition of Done**:
- [ ] LATRA daily report generates successfully
- [ ] All 11 LATRA data fields present and correct
- [ ] Full E2E flow works without manual intervention
- [ ] Load tests pass 1000 concurrent users
- [ ] Security scan finds no critical issues

---

## Sprint 6: Polish + Demo + Documentation (Weeks 11–12)

**Goal**: Production-ready deliverable for FYP submission.

### Epic: Bug Fixing

| # | Ticket | Title | Assignee | Points |
|---|--------|-------|----------|--------|
| 1 | RSHFY-600 | Bug triage: all P0/P1 bugs | All | 5 |
| 2 | RSHFY-601 | UI polish: mobile app | Fatma | 8 |
| 3 | RSHFY-602 | UI polish: admin panel | Ezekiel | 3 |
| 4 | RSHFY-603 | Performance optimization: search | Godbless | 5 |
| 5 | RSHFY-604 | Performance optimization: booking flow | Ezekiel | 3 |

### Epic: Documentation

| # | Ticket | Title | Assignee | Points |
|---|--------|-------|----------|--------|
| 6 | RSHFY-605 | Write FYP Final Report (all chapters) | All | 13 |
| 7 | RSHFY-606 | Create demo video (5-minute walkthrough) | Fatma | 5 |
| 8 | RSHFY-607 | Finalize API documentation | Stella | 3 |
| 9 | RSHFY-608 | Finalize deployment documentation | Godbless | 3 |
| 10 | RSHFY-609 | Write user guide (EN + SW) | Fatma | 5 |

### Epic: Deployment

| # | Ticket | Title | Assignee | Points |
|---|--------|-------|----------|--------|
| 11 | RSHFY-610 | Set up staging environment | Godbless | 5 |
| 12 | RSHFY-611 | Deploy to staging | Godbless | 3 |
| 13 | RSHFY-612 | Build Android APK for demo | Fatma | 3 |
| 14 | RSHFY-613 | Prepare Play Store listing (optional) | Fatma | 5 |

### Epic: Defense Preparation

| # | Ticket | Title | Assignee | Points |
|---|--------|-------|----------|--------|
| 15 | RSHFY-614 | Prepare defense presentation | All | 8 |
| 16 | RSHFY-615 | Dry run defense + incorporate feedback | All | 3 |

**Total**: 80 points

**Sprint 6 Definition of Done**:
- [ ] All critical bugs fixed
- [ ] FYP report submitted and approved by supervisor
- [ ] Demo video published
- [ ] Android APK available for demo
- [ ] All documentation reviewed and approved
- [ ] Team prepared for defense

---

## Sprint Ceremonies

### Daily Standup (15 min, Mon–Fri, 9:00 AM)

Each person shares:
- What I did yesterday
- What I'm doing today
- Any blockers

### Sprint Planning (2 hours, Start of Sprint)

- Review Product Backlog
- Break epics into tickets
- Estimate points (Fibonacci: 1, 2, 3, 5, 8, 13)
- Commit to sprint backlog

### Sprint Review (1 hour, End of Sprint)

- Demo completed features to supervisor
- Gather feedback
- Update Product Backlog

### Sprint Retrospective (1 hour, End of Sprint)

- What went well?
- What didn't go well?
- Action items for next sprint

---

## Definition of Done (Every Ticket)

For every ticket to be considered done:

- [ ] Code implemented and meets acceptance criteria
- [ ] Unit tests written (>80% coverage for new code)
- [ ] Integration tests written (for new endpoints/flows)
- [ ] Code reviewed and approved by 1+ peer
- [ ] Documentation updated (API docs, README if relevant)
- [ ] No new linting errors
- [ ] No security vulnerabilities introduced
- [ ] Merged to `develop` branch via PR
- [ ] Deployed to development environment successfully
- [ ] Ticket moved to "Done" column with summary

---

## Risk Register

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| M-Pesa sandbox limitations | Medium | High | Build mock provider early, test integration late |
| Team member unavailable (illness, exam) | High | Medium | Cross-train, pair program on critical path |
| LATRA API changes | Low | High | Use abstraction layer, mock for now |
| Scope creep | High | High | Strict change control, defer to post-FYP |
| Integration issues between services | High | High | Daily integration tests, contract testing |
| Performance issues at scale | Medium | Medium | Load test in Sprint 5, optimize Sprint 6 |
| Supervisor feedback requires rework | Medium | High | Show progress early, get feedback weekly |

---

## Velocity Tracking

Track estimated vs. actual points per sprint:

| Sprint | Committed | Completed | Velocity | Notes |
|--------|-----------|-----------|----------|-------|
| Sprint 0 | 49 | — | — | — |
| Sprint 1 | 84 | — | — | — |
| Sprint 2 | 93 | — | — | — |
| Sprint 3 | 127 | — | — | ⚠️ High — monitor carefully |
| Sprint 4 | 100 | — | — | — |
| Sprint 5 | 84 | — | — | — |
| Sprint 6 | 80 | — | — | — |

**Target velocity**: 80-90 points/sprint (for a 4-person team doing part-time work alongside studies).

If velocity is consistently below target:
1. Reduce scope on future sprints
2. Move non-critical items to "Phase 2" post-FYP

---

**Document Owner**: Project Management
**Last Updated**: 2026-03-15
**Version**: 1.0
**Status**: Approved for Execution
