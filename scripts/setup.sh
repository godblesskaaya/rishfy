#!/usr/bin/env bash
# =============================================================================
# RISHFY — One-command development environment setup
# =============================================================================
# Usage:
#   ./scripts/setup.sh          # Full setup
#   ./scripts/setup.sh --reset  # Wipe everything and start fresh
#
# Prerequisites (installed before running):
#   - Docker Desktop 24+ (or Docker Engine + Compose v2)
#   - Node.js 20 LTS + npm
#   - Flutter 3.x (for mobile app; optional for backend-only work)
#   - openssl (for JWT key generation)
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Config & Colors
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'  # No Color

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------
RESET_MODE=false
SKIP_DOCKER=false

for arg in "$@"; do
    case $arg in
        --reset)      RESET_MODE=true ;;
        --skip-docker) SKIP_DOCKER=true ;;
        --help)
            cat <<EOF
Usage: ./scripts/setup.sh [OPTIONS]

Options:
  --reset         Wipe Docker volumes and reinstall all dependencies
  --skip-docker   Skip docker compose up (only install deps, generate secrets)
  --help          Show this help

EOF
            exit 0
            ;;
    esac
done

# -----------------------------------------------------------------------------
# Step 1: Prerequisite checks
# -----------------------------------------------------------------------------
log_info "Checking prerequisites..."

check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "$1 is required but not installed. See README.md for installation instructions."
        exit 1
    fi
}

check_command docker
check_command node
check_command npm
check_command openssl

# Check Docker Compose v2
if ! docker compose version &> /dev/null; then
    log_error "Docker Compose v2 is required. Update Docker Desktop or install compose-plugin."
    exit 1
fi

# Check Node version (need 20+)
NODE_MAJOR=$(node -v | sed 's/v//' | cut -d. -f1)
if [ "$NODE_MAJOR" -lt 20 ]; then
    log_error "Node.js 20+ required. Current: $(node -v)"
    exit 1
fi

log_ok "All prerequisites present"

# -----------------------------------------------------------------------------
# Step 2: Reset (if requested)
# -----------------------------------------------------------------------------
if [ "$RESET_MODE" = true ]; then
    log_warn "Resetting environment — this will wipe all data!"
    read -p "Are you sure? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Reset cancelled"
        exit 0
    fi

    cd "$PROJECT_ROOT"
    docker compose down -v --remove-orphans 2>/dev/null || true
    rm -rf node_modules services/*/node_modules
    rm -f .env infrastructure/secrets/*.pem infrastructure/secrets/*.json
    log_ok "Environment reset complete"
fi

# -----------------------------------------------------------------------------
# Step 3: Environment file
# -----------------------------------------------------------------------------
log_info "Setting up environment variables..."

cd "$PROJECT_ROOT"

if [ ! -f .env ]; then
    cat > .env <<'EOF'
# =============================================================================
# RISHFY — Local Development Environment
# =============================================================================
# WARNING: These are DEV-ONLY values. Never use in production.
# =============================================================================

# Database passwords (per-service isolation)
POSTGRES_ROOT_PASSWORD=dev_root_password
AUTH_DB_PASSWORD=dev_auth_password
USER_DB_PASSWORD=dev_user_password
ROUTE_DB_PASSWORD=dev_route_password
BOOKING_DB_PASSWORD=dev_booking_password
PAYMENT_DB_PASSWORD=dev_payment_password
LOCATION_DB_PASSWORD=dev_location_password
NOTIFICATION_DB_PASSWORD=dev_notification_password

# Google Maps API Key (required for route service)
# Get from: https://console.cloud.google.com/apis/credentials
GOOGLE_MAPS_API_KEY=

# Mobile Money Sandbox Credentials
# M-Pesa sandbox: https://developer.vodacom.co.tz
MPESA_API_KEY=sandbox_key_replace_me
MPESA_API_SECRET=sandbox_secret_replace_me

# TigoPesa sandbox: https://developers.tigo.com
TIGOPESA_API_KEY=sandbox_key_replace_me

# Airtel Money sandbox: https://developers.airtel.africa
AIRTEL_API_KEY=sandbox_key_replace_me

# Webhook signing (auto-generated below)
WEBHOOK_SIGNATURE_SECRET=

# Admin dashboard — NextAuth session encryption (auto-generated below)
NEXTAUTH_SECRET=

# Admin service token for server-to-server backend calls
RISHFY_ADMIN_SERVICE_TOKEN=

# SMS (AfricasTalking sandbox)
AFRICASTALKING_API_KEY=sandbox_key_replace_me
AFRICASTALKING_USERNAME=sandbox

# Email (optional for dev)
SENDGRID_API_KEY=
EOF

    # Generate webhook secret
    WEBHOOK_SECRET=$(openssl rand -hex 32)
    sed -i.bak "s/WEBHOOK_SIGNATURE_SECRET=/WEBHOOK_SIGNATURE_SECRET=${WEBHOOK_SECRET}/" .env && rm .env.bak

    # Generate NextAuth secret
    NEXTAUTH_SECRET=$(openssl rand -hex 32)
    sed -i.bak "s/NEXTAUTH_SECRET=/NEXTAUTH_SECRET=${NEXTAUTH_SECRET}/" .env && rm .env.bak

    log_ok "Created .env file — REMEMBER to fill in GOOGLE_MAPS_API_KEY"
else
    log_info ".env already exists, skipping"
fi

# -----------------------------------------------------------------------------
# Step 4: Generate JWT keypair for auth-service
# -----------------------------------------------------------------------------
log_info "Generating JWT RSA keypair..."

mkdir -p infrastructure/secrets
cd infrastructure/secrets

if [ ! -f jwt_private_key.pem ]; then
    openssl genrsa -out jwt_private_key.pem 2048 2>/dev/null
    openssl rsa -in jwt_private_key.pem -pubout -out jwt_public_key.pem 2>/dev/null
    chmod 600 jwt_private_key.pem
    chmod 644 jwt_public_key.pem
    log_ok "Generated JWT keypair at infrastructure/secrets/"
else
    log_info "JWT keypair already exists, skipping"
fi

# Placeholder FCM service account (dev only — replace with real one for push)
if [ ! -f fcm_service_account.json ]; then
    cat > fcm_service_account.json <<'EOF'
{
  "_comment": "PLACEHOLDER — Replace with real FCM service account JSON for push notifications to work",
  "type": "service_account",
  "project_id": "rishfy-dev"
}
EOF
    log_warn "Created placeholder fcm_service_account.json — replace with real credentials for push to work"
fi

cd "$PROJECT_ROOT"

# -----------------------------------------------------------------------------
# Step 5: Install Node dependencies per service
# -----------------------------------------------------------------------------
log_info "Installing Node dependencies..."

# Root monorepo install
if [ -f package.json ]; then
    npm install --silent
fi

# Per-service install
for service in auth user route booking payment location notification; do
    if [ -f "services/${service}/package.json" ]; then
        log_info "  Installing ${service}-service dependencies..."
        (cd "services/${service}" && npm install --silent)
    fi
done

log_ok "Node dependencies installed"

# -----------------------------------------------------------------------------
# Step 6: Generate TypeScript code from .proto files
# -----------------------------------------------------------------------------
log_info "Generating TypeScript from protobuf definitions..."

if [ -f package.json ] && grep -q "proto:generate" package.json; then
    npm run proto:generate
    log_ok "Proto types generated"
else
    log_warn "No proto:generate script found — skipping (add it to root package.json)"
fi

# -----------------------------------------------------------------------------
# Step 7: Docker compose up
# -----------------------------------------------------------------------------
if [ "$SKIP_DOCKER" = false ]; then
    log_info "Starting Docker stack (this may take a few minutes on first run)..."

    docker compose pull --quiet 2>/dev/null || true
    docker compose up -d --build

    # Wait for critical services to be healthy
    log_info "Waiting for services to become healthy..."
    TIMEOUT=180
    ELAPSED=0
    while [ $ELAPSED -lt $TIMEOUT ]; do
        if docker compose ps postgres | grep -q "healthy" && \
           docker compose ps redis | grep -q "healthy" && \
           docker compose ps kafka | grep -q "healthy"; then
            log_ok "Core infrastructure is healthy"
            break
        fi
        sleep 3
        ELAPSED=$((ELAPSED + 3))
        echo -n "."
    done
    echo

    if [ $ELAPSED -ge $TIMEOUT ]; then
        log_error "Services failed to become healthy in ${TIMEOUT}s"
        docker compose ps
        exit 1
    fi
fi

# -----------------------------------------------------------------------------
# Step 8: Run migrations & seed data
# -----------------------------------------------------------------------------
if [ "$SKIP_DOCKER" = false ]; then
    log_info "Running database migrations..."

    for service in auth user route booking payment location notification; do
        if [ -d "services/${service}/migrations" ]; then
            log_info "  Migrating ${service}-service..."
            docker compose exec -T "${service}-service" npm run migrate:up 2>/dev/null || \
                log_warn "  ${service} migration skipped (no migrate:up script yet)"
        fi
    done

    log_ok "Migrations complete"

    log_info "Seeding auth development data..."
    bash scripts/seed.sh auth
    log_ok "Seed data loaded"
fi

# -----------------------------------------------------------------------------
# Done!
# -----------------------------------------------------------------------------
cat <<EOF

${GREEN}╔════════════════════════════════════════════════════════════╗
║               RISHFY DEV ENVIRONMENT READY                 ║
╚════════════════════════════════════════════════════════════╝${NC}

  🌐 API Gateway:     http://localhost
  🖥  Admin Dashboard: http://localhost:3000
  📖 API Docs:        http://localhost/docs
  📊 Kafka UI:        http://localhost:8090
  📈 Grafana:         http://localhost:3001   (admin/admin)
  🔍 Jaeger:          http://localhost:16686
  🗄  pgAdmin:         http://localhost:5050   (run with --profile dev-tools)

  Quick health check:
    curl http://localhost/health

  View logs:
    docker compose logs -f auth-service

  Stop everything:
    docker compose down

  Reset everything:
    ./scripts/setup.sh --reset

${YELLOW}  ⚠️  Don't forget to set GOOGLE_MAPS_API_KEY in .env${NC}

EOF
