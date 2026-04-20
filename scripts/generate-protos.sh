#!/usr/bin/env bash
# =============================================================================
# Generate TypeScript client & server stubs from .proto files
# =============================================================================
# Prereq: protoc installed locally, and ts-proto package in root node_modules.
#   brew install protobuf   # macOS
#   apt install protobuf-compiler   # Linux
#
# This script is idempotent — safe to run multiple times.
# =============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROTO_DIR="${ROOT}/shared/protos"
OUT_DIR="${ROOT}/shared/protos/generated"

# Verify protoc
if ! command -v protoc &> /dev/null; then
    echo "Error: protoc not installed."
    echo "  macOS:  brew install protobuf"
    echo "  Linux:  sudo apt-get install -y protobuf-compiler"
    exit 1
fi

# Verify ts-proto plugin
TS_PROTO_PLUGIN="${ROOT}/node_modules/.bin/protoc-gen-ts_proto"
if [ ! -f "$TS_PROTO_PLUGIN" ]; then
    echo "Installing ts-proto..."
    (cd "$ROOT" && npm install --save-dev ts-proto)
fi

mkdir -p "$OUT_DIR"
rm -rf "${OUT_DIR:?}"/*

echo "Generating TypeScript from .proto files..."

protoc \
    --plugin=protoc-gen-ts_proto="${TS_PROTO_PLUGIN}" \
    --ts_proto_out="${OUT_DIR}" \
    --ts_proto_opt=outputServices=grpc-js,env=node,useOptionals=messages,esModuleInterop=true,exportCommonSymbols=false \
    --proto_path="${PROTO_DIR}" \
    "${PROTO_DIR}"/*.proto

echo "✓ Generated files in ${OUT_DIR}"

# Copy to each service that consumes protos
for service in auth user route booking payment location notification; do
    SVC_PROTO_DIR="${ROOT}/services/${service}/src/generated"
    mkdir -p "$SVC_PROTO_DIR"
    cp "${OUT_DIR}"/*.ts "$SVC_PROTO_DIR/"
done

echo "✓ Distributed to all service directories"
