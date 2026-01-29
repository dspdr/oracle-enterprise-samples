#!/bin/bash
# reset.sh - Reset the environment

set -e
source "$(dirname "$0")/env.sh"

echo "Resetting environment..."
cd "$PROJECT_ROOT/infra"

echo "Stopping containers..."
$COMPOSE_CMD down -v

echo "Starting containers..."
$COMPOSE_CMD up -d --build

echo "Waiting for DB initialization..."
# We rely on the healthcheck or just wait
echo "Waiting 30s..."
sleep 30
echo "Environment reset complete."
