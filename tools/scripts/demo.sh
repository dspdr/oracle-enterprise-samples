#!/bin/bash
# demo.sh - Run full end-to-end flow

set -e
source "$(dirname "$0")/env.sh"

if ! command -v jq &> /dev/null; then
    echo "Error: jq is required for this script."
    exit 1
fi

echo "=== Oracle Enterprise Sample: Loan Origination Demo ==="
echo "Container Engine: $CONTAINER_ENGINE"
echo "API URL: $API_URL"

# Ensure DB schema is initialized (best-effort)
if $CONTAINER_ENGINE ps --format '{{.Names}}' | grep -q '^infra-db-1$'; then
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
    if ! $CONTAINER_ENGINE exec -i infra-db-1 bash -lc "$SQLPLUS_ENV sqlplus -s /nolog" <<SQL | grep -q "LOAN_USER"
whenever sqlerror exit 1;
$SQLPLUS_CONNECT
set heading off feedback off;
select username from dba_users where username='LOAN_USER';
exit;
SQL
    then
        echo "Initializing DB schema and seed data..."
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
        $CONTAINER_ENGINE exec -i infra-db-1 bash -lc "$SQLPLUS_ENV sqlplus -s /nolog" <<SQL
whenever sqlerror exit 1;
$SQLPLUS_CONNECT
@/opt/oracle/scripts/setup/03_plans.sql
exit;
SQL
        $CONTAINER_ENGINE exec -i infra-db-1 bash -lc "$SQLPLUS_ENV sqlplus -s /nolog" <<SQL
whenever sqlerror exit 1;
$SQLPLUS_CONNECT
@/opt/oracle/scripts/setup/04_ai_setup.sql
exit;
SQL
        $CONTAINER_ENGINE exec -i infra-db-1 bash -lc "$SQLPLUS_ENV sqlplus -s /nolog" <<SQL
whenever sqlerror exit 1;
$SQLPLUS_CONNECT
@/opt/oracle/scripts/setup/05_synthetic_data.sql
exit;
SQL
    fi
fi

# Wait for API to be ready
echo "Waiting for API..."
MAX_RETRIES=30
COUNT=0
while ! curl -s "$API_URL/docs" > /dev/null; do
    sleep 2
    COUNT=$((COUNT+1))
    if [ $COUNT -ge $MAX_RETRIES ]; then
        echo "Timeout waiting for API."
        exit 1
    fi
    echo -n "."
done
echo " Ready."

# Basic POST helper with one retry for transient DB readiness
post_json() {
    local url="$1"
    local payload="$2"
    local idem_key="$3"
    local response status
    response=$(curl -s -w "\n%{http_code}" -X POST "$url" \
        -H "Idempotency-Key: $idem_key" \
        -H "Content-Type: application/json" \
        -d "$payload")
    status=$(echo "$response" | tail -n 1)
    body=$(echo "$response" | sed '$d')
    if [ "$status" != "200" ] && [ "$status" != "201" ]; then
        echo "Request failed (HTTP $status). Retrying once..." >&2
        sleep 3
        response=$(curl -s -w "\n%{http_code}" -X POST "$url" \
            -H "Idempotency-Key: $idem_key" \
            -H "Content-Type: application/json" \
            -d "$payload")
        status=$(echo "$response" | tail -n 1)
        body=$(echo "$response" | sed '$d')
    fi
    echo "$body"
    return 0
}

post_json_no_body() {
    local url="$1"
    local idem_key="$2"
    local response status body
    response=$(curl -s -w "\n%{http_code}" -X POST "$url" \
        -H "Idempotency-Key: $idem_key" \
        -H "Content-Length: 0")
    status=$(echo "$response" | tail -n 1)
    body=$(echo "$response" | sed '$d')
    if [ "$status" != "200" ] && [ "$status" != "201" ] && [ "$status" != "409" ]; then
        echo "Request failed (HTTP $status). Retrying once..." >&2
        sleep 3
        response=$(curl -s -w "\n%{http_code}" -X POST "$url" \
            -H "Idempotency-Key: $idem_key" \
            -H "Content-Length: 0")
        body=$(echo "$response" | sed '$d')
    fi
    echo "$body"
    return 0
}

# 1. Create Application
echo -e "\n--- 1. Create Application ---"
IDEM_KEY="create-$(date +%s)"
PAYLOAD='{
    "applicant_id": "user123",
    "applicant_name": "Jane Doe",
    "amount": 50000,
    "income": 120000,
    "debt": 5000,
    "email": "jane@example.com"
}'

RESPONSE=$(post_json "$API_URL/applications" "$PAYLOAD" "$IDEM_KEY")

echo "$RESPONSE" | jq .
APP_ID=$(echo "$RESPONSE" | jq -r '.id')

if [ "$APP_ID" == "null" ]; then
    echo "Failed to create application."
    exit 1
fi

echo "Created Application ID: $APP_ID"

# 2. Add Details (KYC, Fraud, Credit)
echo -e "\n--- 2. Add Check Results ---"

echo "Adding KYC Result (PASS)..."
post_json "$API_URL/applications/$APP_ID/kyc" '{"status": "PASS"}' "kyc-$APP_ID" | jq .

echo "Adding Fraud Result (Risk: 10)..."
post_json "$API_URL/applications/$APP_ID/fraud" '{"risk_score": 10}' "fraud-$APP_ID" | jq .

echo "Adding Credit Score (750)..."
post_json "$API_URL/applications/$APP_ID/credit-score" '{"score": 750}' "credit-$APP_ID" | jq .

# 3. Dry Run Decision
echo -e "\n--- 3. Decision Dry-Run ---"
echo "Calling Agent in Dry-Run mode. No side effects should persist."
post_json_no_body "$API_URL/applications/$APP_ID/decision/dry-run" "dry-run-$APP_ID" | jq .

# 3b. Generate Plan
echo -e "\n--- 3b. Generate Decision Plan ---"
echo "Calling Planner (AI + Synthetic Scenarios)."
PLAN_KEY="plan-$APP_ID"
PLAN_PAYLOAD='{"workspace_id": "demo_ws", "scenarios_count": 3}'

PLAN_RESPONSE=$(post_json "$API_URL/applications/$APP_ID/decision/plan" "$PLAN_PAYLOAD" "$PLAN_KEY")
echo "$PLAN_RESPONSE" | jq .

DECISION_PLAN=$(echo "$PLAN_RESPONSE" | jq -c .)

# 4. Execute Decision
echo -e "\n--- 4. Decision Execute ---"
echo "Executing the approved plan."
EXEC_KEY="exec-$APP_ID"
post_json "$API_URL/applications/$APP_ID/decision/execute" "$DECISION_PLAN" "$EXEC_KEY" | jq .

# 5. Idempotency Verification
echo -e "\n--- 5. Idempotency Check ---"
echo "Replaying Execute request with same key. Should return cached response."
post_json "$API_URL/applications/$APP_ID/decision/execute" "$DECISION_PLAN" "$EXEC_KEY" | jq .

# 6. Idempotency Conflict Check
echo -e "\n--- 6. Idempotency Conflict Check ---"
echo "Replaying Execute request with DIFFERENT payload/mode (simulated by different key or same key diff payload)."
# Note: Since execute body is empty, we can't easily change payload unless we add dummy param.
# But we can try to reuse key for a different route or mode.
echo "Trying to reuse key for Dry-Run:"
curl -s -v -X POST "$API_URL/applications/$APP_ID/decision/dry-run" \
  -H "Idempotency-Key: $EXEC_KEY" \
  -H "Content-Length: 0" 2>&1 | grep "HTTP"

echo -e "\nDemo Completed Successfully."
