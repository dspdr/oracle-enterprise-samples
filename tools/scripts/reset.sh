#!/bin/bash
# reset.sh - Reset the environment

set -e
source "$(dirname "$0")/env.sh"

progress() {
    echo "[$1%] $2"
}

progress 0 "Resetting environment..."
cd "$PROJECT_ROOT/infra"

progress 5 "Container engine: $CONTAINER_ENGINE"
if $CONTAINER_ENGINE ps -a --format '{{.Names}}' | grep -q '^infra-loan-api-1$'; then
    echo "Removing existing standalone container: infra-loan-api-1"
    $CONTAINER_ENGINE rm -f infra-loan-api-1
fi
progress 10 "Stopping containers..."
$COMPOSE_CMD down -v

progress 20 "Starting containers..."
if [ "${FORCE_REBUILD:-0}" = "1" ]; then
    progress 22 "Forcing rebuild of loan-api image..."
    $COMPOSE_CMD build --no-cache loan-api
fi
$COMPOSE_CMD up -d --build

progress 30 "Waiting for DB healthcheck..."
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

progress 50 "Detecting DB connection mode..."
WALLET_DIR="/u01/app/oracle/wallets/tls_wallet"
USE_WALLET=$($CONTAINER_ENGINE exec -i infra-db-1 bash -lc "[ -f $WALLET_DIR/tnsnames.ora ] && echo yes || true" 2>/dev/null | tr -d '\r')
if [ "$USE_WALLET" = "yes" ]; then
    DB_ADMIN_USER="${DB_ADMIN_USER:-admin}"
    DB_ADMIN_PASSWORD="${DB_ADMIN_PASSWORD:-Welcome12345!}"
    DB_TNS="${DB_ADMIN_TNS:-myatp_low}"
    SQLPLUS_ENV="TNS_ADMIN=$WALLET_DIR"
    SQLPLUS_CONNECT="connect ${DB_ADMIN_USER}/\"${DB_ADMIN_PASSWORD}\"@${DB_TNS};"
else
    DB_SID=$($CONTAINER_ENGINE exec -i infra-db-1 bash -lc "ps -ef | awk '/pmon_/ {sub(/.*pmon_/,\"\",\\$8); print \\$8; exit}'" 2>/dev/null | tr -d '\r')
    if [ -z "$DB_SID" ]; then
        DB_SID="POD1"
    fi
    SQLPLUS_ENV="ORACLE_SID=$DB_SID"
    SQLPLUS_CONNECT="connect / as sysdba;"
fi

progress 60 "Waiting for DB instance to accept connections..."
for i in {1..90}; do
    if $CONTAINER_ENGINE exec -i infra-db-1 bash -lc "$SQLPLUS_ENV sqlplus -s /nolog" <<SQL >/dev/null
whenever sqlerror exit 1;
$SQLPLUS_CONNECT
set heading off feedback off;
select 1 from dual;
exit;
SQL
    then
        echo "DB instance is ready."
        break
    fi
    if $CONTAINER_ENGINE exec -i infra-db-1 bash -lc "pgrep -f '[d]ownload_my_container_pdb.py' >/dev/null 2>&1"; then
        echo "DB setup still downloading PDB (this can take several minutes)..."
    else
        echo "DB instance not ready yet (waiting...)"
    fi
    sleep 5
done

if ! $CONTAINER_ENGINE exec -i infra-db-1 bash -lc "$SQLPLUS_ENV sqlplus -s /nolog" <<SQL >/dev/null
whenever sqlerror exit 1;
$SQLPLUS_CONNECT
set heading off feedback off;
select 1 from dual;
exit;
SQL
then
    echo "DB instance did not become ready in time."
    exit 1
fi

if [ "$USE_WALLET" = "yes" ]; then
    progress 70 "Waiting for wallet tnsnames.ora..."
    echo "Waiting for wallet tnsnames.ora..."
    for i in {1..60}; do
        if $CONTAINER_ENGINE exec -i infra-db-1 bash -lc "grep -qi '^myatp_low_tls' $WALLET_DIR/tnsnames.ora 2>/dev/null"; then
            break
        fi
        sleep 2
    done
    progress 80 "Waiting for PDB download to finish..."
    echo "Waiting for PDB download to finish..."
    for i in {1..120}; do
        if ! $CONTAINER_ENGINE logs infra-db-1 2>/dev/null | tail -n 30 | grep -q "Downloading MY_ATP.pdb"; then
            break
        fi
        sleep 5
    done
    progress 85 "Updating wallet tnsnames for container networking..."
    echo "Updating wallet tnsnames host for container networking..."
    $CONTAINER_ENGINE exec -i infra-db-1 bash -lc "if [ -f $WALLET_DIR/tnsnames.ora ]; then sed -i 's/(host=localhost)/(host=db)/gI' $WALLET_DIR/tnsnames.ora; fi"
    $COMPOSE_CMD restart loan-api >/dev/null
fi

progress 90 "Initializing DB schema and seed data..."
$CONTAINER_ENGINE exec -i infra-db-1 bash -lc "$SQLPLUS_ENV sqlplus -s /nolog" <<SQL
whenever sqlerror exit 1;
$SQLPLUS_CONNECT
@/opt/oracle/scripts/setup/01_schema.sql
exit;
SQL
$CONTAINER_ENGINE exec -i infra-db-1 bash -lc "$SQLPLUS_ENV sqlplus -s /nolog" <<SQL
whenever sqlerror exit 1;
$SQLPLUS_CONNECT
@/opt/oracle/scripts/setup/02_seed.sql
exit;
SQL

progress 100 "Environment reset complete."
