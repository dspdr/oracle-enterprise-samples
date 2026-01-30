#!/bin/bash
# Execute a decision plan
# Usage: ./06_decision_execute.sh <app_id>

APP_ID=${1:-"APP-123"}
API_URL=${API_URL:-http://localhost:8000}

# Note: You must update payloads/06_decision_execute.json with a valid plan from step 05
curl -X POST "$API_URL/applications/$APP_ID/decision/execute" \
  -H "Idempotency-Key: exec-$(date +%s)" \
  -H "Content-Type: application/json" \
  -d @../payloads/06_decision_execute.json
