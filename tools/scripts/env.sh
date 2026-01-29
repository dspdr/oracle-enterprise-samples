#!/bin/bash
# env.sh - Detect environment

if command -v podman &> /dev/null; then
    if podman info &> /dev/null; then
        export CONTAINER_ENGINE=podman
        export COMPOSE_CMD="podman compose"
    elif command -v docker &> /dev/null; then
        export CONTAINER_ENGINE=docker
        export COMPOSE_CMD="docker compose"
    else
        echo "Error: Podman is installed but not running; Docker not found."
        exit 1
    fi
elif command -v docker &> /dev/null; then
    export CONTAINER_ENGINE=docker
    export COMPOSE_CMD="docker compose"
else
    echo "Error: No container engine (podman/docker) found."
    exit 1
fi

export API_URL="${API_URL:-http://localhost:8000}"
export PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)

# Select DB image based on engine architecture (adb-free supports arm64; database/free is amd64-only)
ARCH_RAW=""
if [ "$CONTAINER_ENGINE" = "podman" ]; then
    ARCH_RAW=$($CONTAINER_ENGINE info --format '{{.Host.Arch}}' 2>/dev/null || true)
elif [ "$CONTAINER_ENGINE" = "docker" ]; then
    ARCH_RAW=$($CONTAINER_ENGINE info --format '{{.Architecture}}' 2>/dev/null || true)
fi
if [ -z "$ARCH_RAW" ]; then
    ARCH_RAW=$(uname -m 2>/dev/null || echo unknown)
fi

case "$ARCH_RAW" in
    arm64|aarch64)
        export DB_IMAGE="${DB_IMAGE:-container-registry.oracle.com/database/adb-free:latest-23ai}"
        export DB_SERVICE="${DB_SERVICE:-myatp_low}"
        export DB_DSN="${DB_DSN:-myatp_low}"
        export DB_TNS_ADMIN="${DB_TNS_ADMIN:-/u01/app/oracle/wallets/tls_wallet}"
        ;;
    amd64|x86_64)
        export DB_IMAGE="${DB_IMAGE:-container-registry.oracle.com/database/free:latest}"
        ;;
    *)
        export DB_IMAGE="${DB_IMAGE:-container-registry.oracle.com/database/free:latest}"
        ;;
esac

export DB_SERVICE="${DB_SERVICE:-FREEPDB1}"
