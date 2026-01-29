#!/bin/bash
# reset.sh - Reset the environment

set -e
source "$(dirname "$0")/env.sh"

echo "Resetting environment..."
cd "$PROJECT_ROOT/infra"

echo "Container engine: $CONTAINER_ENGINE"
if $CONTAINER_ENGINE ps -a --format '{{.Names}}' | grep -q '^infra-loan-api-1$'; then
    echo "Removing existing standalone container: infra-loan-api-1"
    $CONTAINER_ENGINE rm -f infra-loan-api-1
fi
echo "Stopping containers..."
$COMPOSE_CMD down -v

echo "Starting containers..."
$COMPOSE_CMD up -d --build

echo "Waiting for DB healthcheck..."
for i in {1..30}; do
    db_status=$($CONTAINER_ENGINE inspect --format '{{.State.Health.Status}}' infra-db-1 2>/dev/null || echo "missing")
    if [ "$db_status" = "healthy" ]; then
        echo "DB is healthy."
        break
    fi
    echo "DB status: $db_status (waiting...)"
    sleep 5
done

if [ "$db_status" != "healthy" ]; then
    echo "DB did not become healthy in time."
    exit 1
fi

echo "Initializing DB schema and seed data..."
$CONTAINER_ENGINE exec -i infra-db-1 bash -lc "sqlplus -s / as sysdba @/opt/oracle/scripts/setup/01_schema.sql"
$CONTAINER_ENGINE exec -i infra-db-1 bash -lc "sqlplus -s / as sysdba @/opt/oracle/scripts/setup/02_seed.sql"

echo "Environment reset complete."
