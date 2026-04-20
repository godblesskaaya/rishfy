# Rishfy Development Setup Guide

> **From zero to running locally in 30 minutes**
> Target audience: New developers joining the Rishfy team

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Initial Setup](#2-initial-setup)
3. [Running the Platform](#3-running-the-platform)
4. [IDE Configuration](#4-ide-configuration)
5. [Mobile App Setup (Flutter)](#5-mobile-app-setup-flutter)
6. [Common Workflows](#6-common-workflows)
7. [Troubleshooting](#7-troubleshooting)

---

## 1. Prerequisites

### 1.1 Required Software

| Software | Version | Verify Command |
|----------|---------|----------------|
| **Git** | 2.40+ | `git --version` |
| **Node.js** | 20.x LTS | `node --version` |
| **npm** | 10.x+ | `npm --version` |
| **Docker** | 24.x+ | `docker --version` |
| **Docker Compose** | 2.x | `docker compose version` |
| **Flutter** | 3.16+ | `flutter --version` |

### 1.2 Installation Instructions

#### On macOS (using Homebrew)
```bash
brew install git node docker flutter
```

#### On Ubuntu 22.04 / 24.04
```bash
# Git
sudo apt update && sudo apt install -y git

# Node.js 20 LTS via nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
source ~/.bashrc
nvm install 20
nvm use 20
nvm alias default 20

# Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
# Log out and back in for group changes to apply

# Docker Compose (already included with recent Docker)
docker compose version

# Flutter
sudo snap install flutter --classic
flutter doctor
```

#### On Windows (WSL2 recommended)

1. Install WSL2: `wsl --install`
2. Install Ubuntu from Microsoft Store
3. Follow the Ubuntu instructions above inside WSL2
4. Install Docker Desktop for Windows (with WSL2 backend)

### 1.3 Recommended Tools

| Tool | Purpose | Optional |
|------|---------|----------|
| **VS Code** | Code editor | Highly recommended |
| **Postman** or **Insomnia** | API testing | Yes |
| **DBeaver** or **pgAdmin** | Database GUI | Yes |
| **Redis Insight** | Redis GUI | Yes |
| **Offset Explorer** | Kafka GUI | Yes |

### 1.4 Accounts Needed

Before starting, request access to:

- [ ] GitHub organization (`rishfy`)
- [ ] Project management tool (Jira/Linear)
- [ ] Team Slack/Discord
- [ ] Google Maps API key (shared dev key)
- [ ] M-Pesa Daraja sandbox (for payment testing)

---

## 2. Initial Setup

### 2.1 Clone the Repository

```bash
# Navigate to your workspace
cd ~/projects

# Clone with SSH (recommended)
git clone git@github.com:rishfy/platform.git

# OR with HTTPS
git clone https://github.com/rishfy/platform.git

cd platform
```

### 2.2 Run the Setup Script

```bash
./scripts/setup.sh
```

This script will:
1. ✅ Check all prerequisites are installed
2. ✅ Copy `.env.example` → `.env` files
3. ✅ Install npm dependencies for all services
4. ✅ Pull Docker images
5. ✅ Create PostgreSQL databases and schemas
6. ✅ Seed initial test data
7. ✅ Build Docker images for local services
8. ✅ Set up git hooks (pre-commit, commit-msg)

**Expected duration**: 5-10 minutes (first run)

### 2.3 Configure Environment Variables

Edit `.env` in the root directory with your specific values:

```bash
# API Gateway
NODE_ENV=development
API_GATEWAY_PORT=8080

# Database (use defaults for local Docker)
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_USER=rishfy
POSTGRES_PASSWORD=dev_password_change_me

# Redis
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=

# Kafka
KAFKA_BROKERS=kafka:9092

# JWT Secrets (generate your own!)
JWT_ACCESS_SECRET=your-access-secret-min-32-chars
JWT_REFRESH_SECRET=your-refresh-secret-min-32-chars
JWT_ACCESS_TTL=15m
JWT_REFRESH_TTL=7d

# Google Maps (get shared dev key from team lead)
GOOGLE_MAPS_API_KEY=your_api_key_here

# SMS Provider (use dev sandbox)
SMS_PROVIDER=mock  # 'mock' for dev, 'beem' or 'twilio' for prod
SMS_API_KEY=
SMS_SENDER_ID=RISHFY

# M-Pesa Sandbox
MPESA_CONSUMER_KEY=
MPESA_CONSUMER_SECRET=
MPESA_SHORTCODE=174379
MPESA_PASSKEY=
MPESA_CALLBACK_URL=http://localhost:8080/api/v1/payments/webhooks/m-pesa

# LATRA (dev uses mock endpoints)
LATRA_API_URL=http://localhost:9999/mock/latra
LATRA_CLIENT_ID=mock_client
LATRA_CLIENT_SECRET=mock_secret
```

**Generate JWT secrets**:
```bash
node -e "console.log(require('crypto').randomBytes(64).toString('hex'))"
```

**Security**: Never commit `.env`. It's in `.gitignore` but double-check with:
```bash
git check-ignore .env  # Should output: .env
```

---

## 3. Running the Platform

### 3.1 Start Everything

```bash
./scripts/dev.sh
```

This starts:
- 🐘 PostgreSQL + PostGIS + TimescaleDB
- 🔴 Redis
- 🌀 Kafka + Zookeeper
- 🔀 NGINX API Gateway
- 🔐 Auth Service
- 👤 User Service
- 🚗 Route Service
- 📅 Booking Service
- 💰 Payment Service
- 📍 Location Service
- 🔔 Notification Service
- 📊 Prometheus + Grafana
- 🔍 Jaeger (tracing)

**Alternative: Start in detached mode**
```bash
docker compose up -d
```

**Logs for all services**:
```bash
docker compose logs -f
```

**Logs for specific service**:
```bash
docker compose logs -f auth-service
```

### 3.2 Verify Everything Is Running

Open a new terminal and run:

```bash
# Health check the gateway
curl http://localhost:8080/health

# Expected response:
# {"status":"ok","services":{"auth":"ok","user":"ok",...}}
```

Check individual service health:
```bash
curl http://localhost:3001/health  # Auth
curl http://localhost:3002/health  # User
curl http://localhost:3003/health  # Route
curl http://localhost:3004/health  # Booking
curl http://localhost:3005/health  # Payment
curl http://localhost:3007/health  # Notification
```

### 3.3 Access Development Tools

| Tool | URL | Credentials |
|------|-----|-------------|
| **Swagger UI** | http://localhost:8080/docs | - |
| **Grafana** | http://localhost:3000 | admin / admin |
| **Prometheus** | http://localhost:9090 | - |
| **Jaeger UI** | http://localhost:16686 | - |
| **PostgreSQL** | localhost:5432 | rishfy / dev_password |
| **Redis** | localhost:6379 | - |
| **Kafka UI** | http://localhost:8090 | - |

### 3.4 Seed Test Data

```bash
./scripts/seed.sh
```

This creates:
- 1 admin user (phone: `+255700000001`, password: `Admin@123`)
- 10 test drivers with vehicles
- 50 test passengers
- 20 scheduled test routes
- 10 sample bookings

### 3.5 Stop Everything

```bash
# Graceful stop
docker compose down

# Stop and remove all data (RESET)
docker compose down -v
```

---

## 4. IDE Configuration

### 4.1 VS Code Setup

#### Recommended Extensions

Install the recommended extensions when prompted, or manually:

```bash
code --install-extension dbaeumer.vscode-eslint
code --install-extension esbenp.prettier-vscode
code --install-extension ms-vscode.vscode-typescript-next
code --install-extension Prisma.prisma
code --install-extension mtxr.sqltools
code --install-extension mtxr.sqltools-driver-pg
code --install-extension humao.rest-client
code --install-extension hediet.vscode-drawio
code --install-extension redhat.vscode-yaml
code --install-extension Dart-Code.dart-code
code --install-extension Dart-Code.flutter
```

#### Workspace Settings

A `.vscode/settings.json` is included. Key settings:

```json
{
  "editor.formatOnSave": true,
  "editor.defaultFormatter": "esbenp.prettier-vscode",
  "editor.codeActionsOnSave": {
    "source.fixAll.eslint": "explicit"
  },
  "typescript.tsdk": "node_modules/typescript/lib",
  "files.eol": "\n",
  "[typescript]": {
    "editor.tabSize": 2
  },
  "[dart]": {
    "editor.tabSize": 2
  }
}
```

#### Debugging Setup

Launch configurations are pre-configured in `.vscode/launch.json` for each service. To debug:

1. Set breakpoints in TypeScript code
2. Press `F5` or use the Run menu
3. Select the service to debug (e.g., "Debug: Auth Service")

### 4.2 Git Configuration

Set up your git identity:

```bash
git config user.name "Your Name"
git config user.email "your.email@example.com"
```

Commit message signing (optional but recommended):

```bash
git config commit.gpgsign true
```

---

## 5. Mobile App Setup (Flutter)

### 5.1 Flutter Environment Check

```bash
flutter doctor
```

Fix any issues reported. You need at least:
- ✅ Flutter (Channel stable)
- ✅ Android toolchain OR iOS toolchain
- ✅ VS Code or Android Studio

### 5.2 Install Dependencies

```bash
cd mobile
flutter pub get
```

### 5.3 Configure API Endpoint

Edit `mobile/lib/core/config/environment.dart`:

```dart
class Environment {
  static const String apiBaseUrl = 'http://10.0.2.2:8080/api/v1';
  // 10.0.2.2 is Android emulator's loopback to host machine
  // For iOS simulator: use 'http://localhost:8080/api/v1'
  // For physical device: use your machine's LAN IP (e.g., 'http://192.168.1.100:8080/api/v1')

  static const String wsBaseUrl = 'ws://10.0.2.2:3006';
  static const String googleMapsApiKey = 'YOUR_KEY';
}
```

### 5.4 Run the App

#### On Android Emulator
```bash
# List available emulators
flutter emulators

# Launch an emulator
flutter emulators --launch <emulator_id>

# Run the app
cd mobile
flutter run
```

#### On iOS Simulator (macOS only)
```bash
open -a Simulator
cd mobile
flutter run
```

#### On Physical Device
1. Enable Developer Options + USB Debugging (Android)
2. Connect via USB
3. Trust computer on device
4. `flutter devices` should show your device
5. `flutter run`

### 5.5 Hot Reload

While running, press:
- `r` — Hot reload (fast, preserves state)
- `R` — Hot restart (resets state)
- `q` — Quit

---

## 6. Common Workflows

### 6.1 Creating a New Feature

```bash
# 1. Make sure develop is up to date
git checkout develop
git pull origin develop

# 2. Create feature branch
git checkout -b feature/RSHFY-123-short-description

# 3. Start dev environment
./scripts/dev.sh

# 4. Make your changes
# ... edit files ...

# 5. Run tests as you go
cd services/auth
npm test
npm run test:watch  # For TDD workflow

# 6. Run linter
npm run lint
npm run lint:fix

# 7. Commit (use conventional commits)
git add .
git commit -m "feat(auth): add OTP rate limiting"

# 8. Push and create PR
git push origin feature/RSHFY-123-short-description
# Open PR on GitHub to 'develop' branch
```

### 6.2 Running Migrations

```bash
# Navigate to the service
cd services/auth

# Create a new migration
npm run migrate create add-locked-until-to-auth-users

# This generates: migrations/TIMESTAMP_add-locked-until-to-auth-users.js
# Edit the file, then run:

npm run migrate up

# Rollback if needed
npm run migrate down

# Check status
npm run migrate status
```

### 6.3 Database Access

#### Via CLI
```bash
# Connect to PostgreSQL container
docker compose exec postgres psql -U rishfy -d auth_db

# Or from host (if psql installed)
psql -h localhost -U rishfy -d auth_db
```

#### Via DBeaver
1. Open DBeaver → New Connection → PostgreSQL
2. Host: `localhost`, Port: `5432`
3. Database: `auth_db` (or `user_db`, `route_db`, etc.)
4. Username: `rishfy`, Password: from `.env`

### 6.4 Redis Access

```bash
# Connect to Redis
docker compose exec redis redis-cli

# Or from host
redis-cli -h localhost -p 6379

# Useful commands:
> KEYS *           # List all keys (don't use in prod!)
> KEYS session:*   # List session keys
> GET session:123
> TTL session:123
> GEORADIUS drivers:online -6.7924 39.2083 5 km
```

### 6.5 Kafka Inspection

```bash
# List topics
docker compose exec kafka kafka-topics \
  --list --bootstrap-server localhost:9092

# Consume messages from a topic
docker compose exec kafka kafka-console-consumer \
  --topic booking.created \
  --from-beginning \
  --bootstrap-server localhost:9092

# Produce a test message
docker compose exec kafka kafka-console-producer \
  --topic test \
  --bootstrap-server localhost:9092
```

### 6.6 Making a Test API Call

```bash
# Register a test user
curl -X POST http://localhost:8080/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "phone": "+255712345678",
    "password": "TestPass123!",
    "first_name": "Test",
    "last_name": "User",
    "user_type": "rider"
  }'

# Check OTP in mock SMS provider logs
docker compose logs sms-mock | grep OTP

# Verify OTP (replace with actual code)
curl -X POST http://localhost:8080/api/v1/auth/verify-otp \
  -H "Content-Type: application/json" \
  -d '{
    "phone": "+255712345678",
    "code": "123456",
    "type": "registration"
  }'

# Save the access_token from response, then make authenticated call
TOKEN="eyJhbGc..."
curl -X GET http://localhost:8080/api/v1/users/me \
  -H "Authorization: Bearer $TOKEN"
```

### 6.7 Adding a New Service Endpoint

Follow this checklist for every new endpoint:

1. [ ] Add OpenAPI spec in `api-contracts/<service>.yaml`
2. [ ] Add DTOs in `src/dto/`
3. [ ] Add validation schema (zod) in `src/validators/`
4. [ ] Implement controller method in `src/controllers/`
5. [ ] Implement business logic in `src/services/`
6. [ ] Implement data access in `src/repositories/`
7. [ ] Add unit tests in `tests/unit/`
8. [ ] Add integration test in `tests/integration/`
9. [ ] Update API_CONTRACTS.md documentation
10. [ ] Test via Swagger UI
11. [ ] Update Postman collection

---

## 7. Troubleshooting

### 7.1 Docker Issues

**Problem**: `docker compose up` fails with "port already in use"

**Solution**:
```bash
# Find what's using the port (e.g., 5432)
sudo lsof -i :5432
# Kill the process or change the port in docker-compose.yml
```

**Problem**: "Cannot connect to the Docker daemon"

**Solution**:
```bash
# Start Docker daemon
sudo systemctl start docker

# Add yourself to docker group (log out/in after)
sudo usermod -aG docker $USER
```

### 7.2 Database Issues

**Problem**: Migrations fail with "database does not exist"

**Solution**:
```bash
# Re-run the initialization
docker compose exec postgres psql -U postgres -f /docker-entrypoint-initdb.d/init-databases.sql
```

**Problem**: "Connection refused" when connecting from service to postgres

**Solution**: Service is starting before postgres is ready. Check `docker-compose.yml` uses `depends_on` with health check.

### 7.3 Service Startup Failures

**Problem**: Service keeps restarting

**Solution**:
```bash
# Check logs
docker compose logs auth-service

# Common causes:
# 1. Missing .env variables → check .env.example
# 2. Port conflict → another instance already running
# 3. Dependency not ready → increase start_period in healthcheck
```

### 7.4 npm Issues

**Problem**: `npm install` fails with permission errors

**Solution**:
```bash
# Never use sudo npm! Fix ownership instead:
sudo chown -R $(whoami) ~/.npm
sudo chown -R $(whoami) node_modules
```

**Problem**: Node version mismatch

**Solution**:
```bash
# Use the project's required Node version
nvm use  # Reads .nvmrc file
```

### 7.5 Git Issues

**Problem**: Merge conflicts on every pull

**Solution**: Use rebase strategy:
```bash
git config --global pull.rebase true
```

### 7.6 Mobile App Issues

**Problem**: Can't connect to API from Android emulator

**Solution**: Android emulator uses `10.0.2.2` to reach host machine, not `localhost`.

**Problem**: Can't connect from physical device

**Solution**: Ensure phone and computer are on the same WiFi. Use your machine's LAN IP:
```bash
# Find LAN IP
ip addr show  # Linux
ifconfig      # macOS
```

Then update `apiBaseUrl` in `environment.dart` to `http://<YOUR_LAN_IP>:8080/api/v1`.

### 7.7 Getting Help

1. Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for detailed solutions
2. Search team Slack `#dev-help` channel
3. Ask in #dev-help with:
   - What you're trying to do
   - What you expected to happen
   - What actually happened
   - Relevant logs (use code blocks!)
4. Schedule a pairing session if stuck > 30 minutes

---

## Quick Reference Card

### Daily Commands
```bash
./scripts/dev.sh                    # Start everything
docker compose logs -f <service>    # Watch logs
docker compose restart <service>    # Restart service
docker compose down                 # Stop everything
docker compose down -v              # Stop and wipe data
```

### Git Commands
```bash
git checkout develop && git pull
git checkout -b feature/RSHFY-XXX-description
git commit -m "feat(service): description"
git push origin feature/RSHFY-XXX-description
```

### Testing
```bash
npm test                # All tests
npm run test:unit       # Unit tests only
npm run test:integration # Integration tests
npm run test:watch      # Watch mode
npm run test:coverage   # With coverage report
```

### Database
```bash
npm run migrate up      # Apply migrations
npm run migrate down    # Rollback
npm run seed            # Seed test data
```

---

**Document Owner**: DevOps / Backend Team
**Last Updated**: 2026-03-15
**Version**: 1.0
