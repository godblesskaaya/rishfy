# Deployment Reference

> **Audience:** DevOps lead, supervisor, and anyone on-call.
> **Scope:** Staging and production deployment for Rishfy.
> **Current status:** Dev environment runs on Docker Compose locally. Production deployment target is Kubernetes (details below) — implementation is post-academic.

---

## 1. Environments

| Environment | Purpose | Deploy Target | Auto-deploy? |
|---|---|---|---|
| **dev** | Local developer machines | Docker Compose | Manual |
| **staging** | QA, supervisor review, integration testing | Single K8s cluster (small) | On `develop` branch merge |
| **production** | Real users | K8s cluster (multi-node) | On `main` branch tag |

---

## 2. Target Production Topology

```
                    ┌────────────────────┐
                    │   Cloudflare CDN   │
                    │   (static + DDoS)  │
                    └──────────┬─────────┘
                               │ HTTPS
                    ┌──────────▼─────────┐
                    │   Load Balancer    │
                    │   (DigitalOcean LB │
                    │    or AWS ALB)     │
                    └──────────┬─────────┘
                               │
          ┌────────────────────┼────────────────────┐
          │                    │                    │
   ┌──────▼──────┐      ┌──────▼──────┐     ┌──────▼──────┐
   │  NGINX Pod  │      │  NGINX Pod  │     │  NGINX Pod  │
   │  (gateway)  │      │  (gateway)  │     │  (gateway)  │
   └──────┬──────┘      └──────┬──────┘     └──────┬──────┘
          │                    │                    │
          └────────────────────┼────────────────────┘
                               │
                 ┌─────────────┴─────────────┐
                 │     Service Mesh (K8s)    │
                 │                           │
                 │  auth  user  route        │
                 │  booking payment          │
                 │  location notification    │
                 └─────────────┬─────────────┘
                               │
                    ┌──────────┼──────────┐
                    │          │          │
              ┌─────▼────┐ ┌──▼───┐ ┌────▼─────┐
              │PostgreSQL│ │ Redis│ │  Kafka   │
              │ managed  │ │ HA   │ │ 3-broker │
              │  + PITR  │ │      │ │          │
              └──────────┘ └──────┘ └──────────┘
```

### Sizing Recommendations (Phase 2 target: 50K users)

| Component | Prod Resources | Replicas | Notes |
|---|---|---|---|
| NGINX gateway | 500m CPU / 512Mi RAM | 3 | Behind cloud LB |
| auth-service | 500m CPU / 512Mi RAM | 2 | |
| user-service | 500m CPU / 512Mi RAM | 2 | |
| route-service | 1000m CPU / 1Gi RAM | 3 | Heavy geospatial queries |
| booking-service | 500m CPU / 512Mi RAM | 2 | |
| payment-service | 500m CPU / 512Mi RAM | 2 | |
| location-service | 1000m CPU / 1Gi RAM | 3 | High write volume |
| notification-service | 500m CPU / 512Mi RAM | 2 | |
| **PostgreSQL** | 4 vCPU / 8Gi / 100Gi SSD | managed + 1 replica | DigitalOcean managed or AWS RDS |
| **Redis** | 2 vCPU / 4Gi | 3 (cluster) | |
| **Kafka** | 2 vCPU / 4Gi / 100Gi each | 3 brokers (KRaft) | |

**Estimated monthly cloud cost (DigitalOcean):** ~$400–600 USD.
**Estimated monthly cloud cost (AWS):** ~$800–1,200 USD.

---

## 3. Deployment Pipeline

### 3.1 Branch Strategy

```
main           ─────────●─────●─────●────────►  (tagged releases → prod)
                        │     │     │
develop        ──●──●───┴──●──┴──●──┴──●──────►  (continuous → staging)
                  │        │     │     │
feature/XXX    ───┘        │     │     │
fix/XXX           ─────────┘     │     │
feat/XXX                         └─────┘
```

- All work happens on feature branches
- Merge to `develop` triggers staging deploy
- Merge `develop` → `main` via release PR triggers production deploy
- Hotfixes: branch from `main`, merge back to both `main` and `develop`

### 3.2 CI/CD Pipeline (GitHub Actions)

**On every PR:**

1. Lint + typecheck
2. Unit tests (all services)
3. Integration tests (all services, parallel)
4. Security scan (`npm audit`, `gitleaks`)
5. Build Docker images (but don't push)

**On merge to `develop`:**

1. All above
2. E2E tests against ephemeral environment
3. Build + push images tagged `staging-<sha>`
4. Deploy to staging via Argo CD or `kubectl apply`
5. Smoke tests against staging
6. Notify team in Slack

**On tag `v*.*.*` on `main`:**

1. Re-run full test suite
2. Build + push images tagged `v1.2.3`
3. Generate release notes from conventional commits
4. Manual approval gate (supervisor + tech lead)
5. Deploy to production (rolling update, 1 pod at a time)
6. Post-deploy smoke tests
7. Monitor for 30 minutes — auto-rollback on error spike

---

## 4. Kubernetes Manifests (Templates)

Actual manifests live in `infrastructure/k8s/` — not included in the academic handoff package but referenced here for future work.

### 4.1 Typical Service Deployment

```yaml
# infrastructure/k8s/base/booking-service.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: booking-service
  labels: { app: booking-service, tier: backend }
spec:
  replicas: 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels: { app: booking-service }
  template:
    metadata:
      labels: { app: booking-service }
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8084"
        prometheus.io/path: "/metrics"
    spec:
      containers:
      - name: booking-service
        image: registry.rishfy.tz/booking-service:v1.0.0
        ports:
        - containerPort: 8084
          name: http
        - containerPort: 50054
          name: grpc
        resources:
          requests: { cpu: 250m, memory: 256Mi }
          limits:   { cpu: 500m, memory: 512Mi }
        envFrom:
        - configMapRef: { name: booking-config }
        - secretRef:    { name: booking-secrets }
        livenessProbe:
          httpGet: { path: /health, port: 8084 }
          initialDelaySeconds: 30
          periodSeconds: 30
        readinessProbe:
          httpGet: { path: /ready, port: 8084 }
          initialDelaySeconds: 5
          periodSeconds: 10
        lifecycle:
          preStop:
            exec:
              command: ["sleep", "10"]  # Allow in-flight requests to complete
```

### 4.2 Horizontal Pod Autoscaler

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: booking-service
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: booking-service
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target: { type: Utilization, averageUtilization: 70 }
  - type: Resource
    resource:
      name: memory
      target: { type: Utilization, averageUtilization: 80 }
```

### 4.3 Secrets Management

**Decision deferred to deployment phase.** Options:

| Option | Pros | Cons |
|---|---|---|
| Kubernetes Secrets + Sealed Secrets | Git-committable encrypted secrets | Keys managed in-cluster |
| HashiCorp Vault | Dynamic secrets, rotation | Ops overhead |
| Cloud provider secrets | Fully managed | Vendor lock-in |

**Recommendation:** Start with Sealed Secrets + cluster-generated keys for Phase 2. Migrate to Vault only if multi-cluster or rotation requirements demand it.

---

## 5. Database Deployment

### 5.1 Production Database

**Do not self-host PostgreSQL for production.** Use managed services:

- **DigitalOcean Managed PostgreSQL** — easiest, supports TimescaleDB extension, ~$60/mo for starter
- **AWS RDS for PostgreSQL** — most mature, supports PostGIS, from ~$80/mo
- **Timescale Cloud** — best if TimescaleDB features are heavily used

**Required extensions:**

- `postgis` + `postgis_topology` (for route_db)
- `timescaledb` (for location_db)
- `pgcrypto`, `uuid-ossp` (all databases)

### 5.2 Backup Strategy

| Backup Type | Frequency | Retention | Storage |
|---|---|---|---|
| Point-in-time recovery | Continuous | 7 days | Provider-managed |
| Full daily backup | Daily at 02:00 TAT | 30 days | S3-compatible (e.g., DO Spaces) |
| Weekly archival | Sunday 03:00 TAT | 1 year | Cold storage |
| Pre-migration snapshot | Ad-hoc | 7 days | Managed service |

**Test restore procedure monthly.** A backup that hasn't been restored is not a backup.

### 5.3 Migration Strategy

Migrations run via a dedicated Kubernetes Job (not a sidecar):

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: booking-migrate-{{.Version}}
spec:
  backoffLimit: 3
  template:
    spec:
      restartPolicy: OnFailure
      containers:
      - name: migrate
        image: registry.rishfy.tz/booking-service:{{.Version}}
        command: ["npm", "run", "migrate:up"]
        envFrom:
        - secretRef: { name: booking-secrets }
```

Migration job runs **before** the rolling deployment so services always see a schema at least as new as their code expects. Backward-compatible migrations only — never drop columns without a deprecation period (two releases).

---

## 6. Mobile Money Provider Configuration

### 6.1 Sandbox → Production Cutover

Each provider has distinct endpoints for sandbox and production. Switch via environment variables at deploy time:

| Env | M-Pesa Base URL | TigoPesa | Airtel |
|---|---|---|---|
| Sandbox | `https://openapi.m-pesa.com/sandbox` | `https://sandbox.tigo.com` | `https://openapiuat.airtel.africa` |
| Production | `https://openapi.m-pesa.com/openapi` | `https://api.tigo.com` | `https://openapi.airtel.africa` |

**Checklist before cutover:**

- [ ] Provider business account verified
- [ ] Production API credentials received and stored in Vault/Sealed Secrets
- [ ] Callback URL registered with provider (HTTPS, verified cert)
- [ ] Provider IP ranges whitelisted in NGINX for webhook endpoint
- [ ] Transaction limits understood (daily caps per account)
- [ ] Reconciliation process established (daily provider reports vs our records)

### 6.2 Webhook URLs

Provide each provider with a stable, versioned URL:

- M-Pesa: `https://api.rishfy.tz/api/v1/webhooks/mpesa`
- TigoPesa: `https://api.rishfy.tz/api/v1/webhooks/tigopesa`
- Airtel: `https://api.rishfy.tz/api/v1/webhooks/airtel`

Never let provider callback URLs change without versioning — some providers don't support URL updates without re-onboarding.

---

## 7. Monitoring & Alerting

### 7.1 SLOs (Service Level Objectives)

| Service | SLO | Measurement Window |
|---|---|---|
| API Gateway availability | 99.9% | 30-day rolling |
| Route search p95 latency | < 1000ms | 1-hour rolling |
| Booking creation success rate | > 99% | 24-hour rolling |
| Payment webhook processing | < 5s p99 | 1-hour rolling |
| Push notification delivery | > 95% within 30s | 24-hour rolling |

### 7.2 Critical Alerts (Page on-call)

- Service pod crash-looping
- Error rate > 5% for 5 minutes
- Payment webhook signature failures spike
- Database connection pool exhausted
- Kafka consumer lag > 10,000 messages
- Certificate expiry within 14 days

### 7.3 Warning Alerts (Team channel)

- Error rate > 1% for 15 minutes
- p95 latency > 2x SLO for 30 minutes
- CPU or memory > 80% sustained for 1 hour
- Disk usage > 75%
- npm audit high-severity CVE in dependencies

### 7.4 Dashboards

Grafana dashboards to maintain (templates in `infrastructure/grafana/dashboards/`):

1. **Platform overview** — RED metrics (Rate, Errors, Duration) per service
2. **Booking funnel** — Creation → payment → confirmation → completion conversion
3. **Payment provider health** — Per-provider success rate, avg settlement time
4. **LATRA compliance** — Reports generated, API hit rate, data completeness
5. **Driver & passenger activity** — DAU/MAU, retention cohorts
6. **Infrastructure** — DB connections, Redis memory, Kafka lag

---

## 8. Disaster Recovery

### 8.1 RTO / RPO Targets

- **RTO (Recovery Time Objective):** 4 hours for full platform restoration
- **RPO (Recovery Point Objective):** 15 minutes of data loss max

### 8.2 Disaster Scenarios & Responses

| Scenario | Response | Recovery Path |
|---|---|---|
| Single pod crash | Auto-restart via K8s | Seconds |
| Single availability zone outage | Traffic shifted by cloud LB | Minutes |
| Database corruption | Restore from PITR snapshot | 1-2 hours |
| Full region outage | Failover to DR region (if configured) | 2-4 hours |
| Data breach | See SECURITY.md incident response | Hours-days |
| Mobile money provider outage | Graceful degradation, queue retries | Dependent on provider |

### 8.3 Quarterly DR Drills

Once per quarter, run a tabletop DR exercise:

- Simulate a scenario
- Walk through the runbook
- Identify gaps
- Update runbook

Document outcomes in `docs/DR_DRILLS/YYYY-QN.md`.

---

## 9. Academic-Project-Specific Notes

For the academic defense / demo, a simplified deployment is acceptable:

**Option A (recommended): DigitalOcean Droplet + Docker Compose**

- Single Ubuntu 22.04 droplet (8GB/4vCPU, ~$48/mo)
- Run `docker-compose.prod.yml` (leaner than dev)
- TLS via Caddy or NGINX + Let's Encrypt
- PostgreSQL managed database (starter tier, ~$15/mo)
- Total: ~$70/mo during the project

**Option B: Render / Railway / Fly.io**

- Pro: No ops, just push
- Con: Harder to demonstrate scaling architecture at defense
- Good for MVP demo

**Do NOT** run production on a laptop or university server for the defense. Judges will want to access the deployed app.

---

## 10. Pre-Launch Checklist

Before going live with real users:

- [ ] TLS certificate installed + auto-renewal
- [ ] Domain DNS pointing to production LB
- [ ] Backups configured and verified with a test restore
- [ ] Monitoring dashboards active + alerts routed to on-call
- [ ] Provider sandbox creds replaced with production creds
- [ ] LATRA operator license application submitted (or interim approval)
- [ ] Privacy policy + terms of service published
- [ ] Data processing agreement with cloud providers signed
- [ ] Incident response runbook distributed to team
- [ ] Load test confirms SLO targets achievable at 2x expected load
- [ ] Legal review of mobile money compliance
- [ ] Team trained on emergency rollback procedure

---

*Last updated: Sprint 0. Review and update at the start of every sprint and before any production deploy.*
