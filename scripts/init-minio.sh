#!/usr/bin/env bash
# Initialize MinIO buckets for local development.
# Idempotent — safe to run multiple times.
set -euo pipefail

MINIO_ENDPOINT="${MINIO_ENDPOINT:-http://localhost:9000}"
MINIO_USER="${MINIO_ROOT_USER:-minioadmin}"
MINIO_PASSWORD="${MINIO_ROOT_PASSWORD:-minioadmin}"

BUCKETS=(
  "rishfy-user-uploads"
  "rishfy-vehicle-docs"
  "rishfy-driver-licenses"
)

# Wait for MinIO to be ready
echo "Waiting for MinIO at $MINIO_ENDPOINT..."
until curl -sf "$MINIO_ENDPOINT/minio/health/live" >/dev/null 2>&1; do
  sleep 1
done
echo "✓ MinIO is up"

# Use the official mc client via docker
docker run --rm --network rishfy_rishfy_net \
  --entrypoint sh minio/mc:latest -c "
    mc alias set local http://minio:9000 $MINIO_USER $MINIO_PASSWORD &&
    $(for b in "${BUCKETS[@]}"; do echo "mc mb -p local/$b 2>/dev/null || true; mc anonymous set download local/$b 2>/dev/null || true;"; done)
  "

echo "✓ MinIO buckets initialized: ${BUCKETS[*]}"
