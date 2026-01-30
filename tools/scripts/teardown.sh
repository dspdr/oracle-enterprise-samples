#!/bin/bash
# teardown.sh - Full teardown of the environment

set -e
source "$(dirname "$0")/env.sh"

echo "Tearing down environment..."
cd "$PROJECT_ROOT/infra"

echo "Container engine: $CONTAINER_ENGINE"

# Remove any standalone container created outside compose
if $CONTAINER_ENGINE ps -a --format '{{.Names}}' | grep -q '^infra-loan-api-1$'; then
    echo "Removing existing standalone container: infra-loan-api-1"
    $CONTAINER_ENGINE rm -f infra-loan-api-1
fi

echo "Stopping and removing compose resources..."
$COMPOSE_CMD down -v

# Remove locally built image for the loan API (best-effort)
if $CONTAINER_ENGINE image inspect infra-loan-api >/dev/null 2>&1; then
    echo "Removing image: infra-loan-api"
    $CONTAINER_ENGINE image rm -f infra-loan-api >/dev/null 2>&1 || true
fi

# Remove DB image (best-effort)
if [ -n "$DB_IMAGE" ] && $CONTAINER_ENGINE image inspect "$DB_IMAGE" >/dev/null 2>&1; then
    echo "Removing image: $DB_IMAGE"
    $CONTAINER_ENGINE image rm -f "$DB_IMAGE" >/dev/null 2>&1 || true
fi

# Remove ADB wallet volume if present (best-effort)
if $CONTAINER_ENGINE volume ls --format '{{.Name}}' | grep -q '^infra_adb_wallets$'; then
    echo "Removing volume: infra_adb_wallets"
    $CONTAINER_ENGINE volume rm -f infra_adb_wallets >/dev/null 2>&1 || true
fi

# Remove compose network if it still exists (best-effort)
if $CONTAINER_ENGINE network ls --format '{{.Name}}' | grep -q '^infra_default$'; then
    echo "Removing network: infra_default"
    $CONTAINER_ENGINE network rm infra_default >/dev/null 2>&1 || true
fi

echo "Teardown complete."
