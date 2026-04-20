#!/usr/bin/env bash
# =============================================================================
# RISHFY — Development convenience script
# =============================================================================
# Usage:
#   ./scripts/dev.sh up              # Start all services
#   ./scripts/dev.sh down            # Stop all services
#   ./scripts/dev.sh restart <svc>   # Restart a specific service
#   ./scripts/dev.sh logs <svc>      # Tail logs
#   ./scripts/dev.sh shell <svc>     # Open shell inside container
#   ./scripts/dev.sh db <service>    # psql into a service's database
#   ./scripts/dev.sh migrate <svc>   # Run pending migrations
#   ./scripts/dev.sh test <svc>      # Run tests for a service
#   ./scripts/dev.sh status          # Show health of all services
#   ./scripts/dev.sh ps              # List running containers
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$PROJECT_ROOT"

COMMAND="${1:-help}"
SERVICE="${2:-}"

SERVICES="auth user route booking payment location notification"

# -----------------------------------------------------------------------------
case "$COMMAND" in
    up)
        echo "Starting Rishfy services..."
        docker compose up -d
        echo "Done. Run './scripts/dev.sh status' to check health."
        ;;

    down)
        echo "Stopping Rishfy services..."
        docker compose down
        ;;

    restart)
        if [ -z "$SERVICE" ]; then
            echo "Usage: $0 restart <service>"; exit 1
        fi
        docker compose restart "${SERVICE}-service"
        ;;

    logs)
        if [ -z "$SERVICE" ]; then
            docker compose logs -f --tail=100
        else
            docker compose logs -f --tail=100 "${SERVICE}-service"
        fi
        ;;

    shell)
        if [ -z "$SERVICE" ]; then
            echo "Usage: $0 shell <service>"; exit 1
        fi
        docker compose exec "${SERVICE}-service" sh
        ;;

    db)
        if [ -z "$SERVICE" ]; then
            echo "Usage: $0 db <service>"
            echo "Available: $SERVICES"
            exit 1
        fi
        docker compose exec postgres psql \
            -U "${SERVICE}_user" \
            -d "${SERVICE}_db"
        ;;

    migrate)
        if [ -z "$SERVICE" ]; then
            echo "Migrating all services..."
            for svc in $SERVICES; do
                echo "  → $svc"
                docker compose exec -T "${svc}-service" npm run migrate:up || true
            done
        else
            docker compose exec "${SERVICE}-service" npm run migrate:up
        fi
        ;;

    test)
        if [ -z "$SERVICE" ]; then
            echo "Running tests for all services..."
            for svc in $SERVICES; do
                echo "  → $svc"
                docker compose exec -T "${svc}-service" npm test || true
            done
        else
            docker compose exec "${SERVICE}-service" npm test
        fi
        ;;

    status)
        echo "Service Health Status:"
        docker compose ps --format "table {{.Service}}\t{{.Status}}\t{{.Ports}}"
        ;;

    ps)
        docker compose ps
        ;;

    help|--help|-h|*)
        cat <<EOF
Rishfy Development Helper

Usage: $0 <command> [service]

Commands:
  up                  Start all services
  down                Stop all services
  restart <service>   Restart a specific service
  logs [service]      Tail logs (all services if no arg)
  shell <service>     Open shell inside a service container
  db <service>        psql into a service's database
  migrate [service]   Run pending migrations
  test [service]      Run tests
  status              Show health status
  ps                  List running containers

Available services:
  $SERVICES

Examples:
  $0 logs booking             # Tail booking-service logs
  $0 db user                  # psql into user_db
  $0 restart payment          # Restart payment-service
  $0 shell auth               # Shell into auth-service container

EOF
        ;;
esac
