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
    if ! $CONTAINER_ENGINE exec -i infra-db-1 bash -lc "echo \"select username from dba_users where username='LOAN_USER';\" | sqlplus -s / as sysdba" | grep -q "LOAN_USER"; then
        echo "Initializing DB schema and seed data..."
        $CONTAINER_ENGINE exec -i infra-db-1 bash -lc "sqlplus -s / as sysdba @/opt/oracle/scripts/setup/01_schema.sql"
        $CONTAINER_ENGINE exec -i infra-db-1 bash -lc "sqlplus -s / as sysdba @/opt/oracle/scripts/setup/02_seed.sql"
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

RESPONSE=$(curl -s -X POST "$API_URL/applications" \
  -H "Idempotency-Key: $IDEM_KEY" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

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
curl -s -X POST "$API_URL/applications/$APP_ID/kyc" \
  -H "Idempotency-Key: kyc-$APP_ID" \
  -H "Content-Type: application/json" \
  -d '{"status": "PASS"}' | jq .

echo "Adding Fraud Result (Risk: 10)..."
curl -s -X POST "$API_URL/applications/$APP_ID/fraud" \
  -H "Idempotency-Key: fraud-$APP_ID" \
  -H "Content-Type: application/json" \
  -d '{"risk_score": 10}' | jq .

echo "Adding Credit Score (750)..."
curl -s -X POST "$API_URL/applications/$APP_ID/credit-score" \
  -H "Idempotency-Key: credit-$APP_ID" \
  -H "Content-Type: application/json" \
  -d '{"score": 750}' | jq .

# 3. Dry Run Decision
echo -e "\n--- 3. Decision Dry-Run ---"
echo "Calling Agent in Dry-Run mode. No side effects should persist."
curl -s -X POST "$API_URL/applications/$APP_ID/decision/dry-run" \
  -H "Idempotency-Key: dry-run-$APP_ID" \
  -H "Content-Length: 0" | jq .

# 4. Execute Decision
echo -e "\n--- 4. Decision Execute ---"
echo "Calling Agent in Execute mode."
EXEC_KEY="exec-$APP_ID"
curl -s -X POST "$API_URL/applications/$APP_ID/decision/execute" \
  -H "Idempotency-Key: $EXEC_KEY" \
  -H "Content-Length: 0" | jq .

# 5. Idempotency Verification
echo -e "\n--- 5. Idempotency Check ---"
echo "Replaying Execute request with same key. Should return cached response."
curl -s -X POST "$API_URL/applications/$APP_ID/decision/execute" \
  -H "Idempotency-Key: $EXEC_KEY" \
  -H "Content-Length: 0" | jq .

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
