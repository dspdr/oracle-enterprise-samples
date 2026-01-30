#!/bin/bash
# logs.sh - Tail DB and API logs

set -e
source "$(dirname "$0")/env.sh"

echo "Tailing logs for db and loan-api..."
cd "$PROJECT_ROOT/infra"
$COMPOSE_CMD logs -f db loan-api
