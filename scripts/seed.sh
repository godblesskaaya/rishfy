#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$PROJECT_ROOT"

TARGET="${1:-auth}"

case "$TARGET" in
  auth)
    docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U auth_user -d auth_db < scripts/seeds/01_admin_user.sql
    ;;
  *)
    echo "Unknown seed target: $TARGET" >&2
    echo "Available seed targets: auth" >&2
    exit 1
    ;;
esac
