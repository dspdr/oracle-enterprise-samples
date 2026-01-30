#!/bin/bash
# Generate a decision plan
# Usage: ./05_decision_plan.sh <app_id>

APP_ID=${1:-"APP-123"}
API_URL=${API_URL:-http://localhost:8000}

curl -X POST "$API_URL/applications/$APP_ID/decision/plan" \
  -H "Idempotency-Key: plan-$(date +%s)" \
  -H "Content-Type: application/json" \
  -d @../payloads/05_decision_plan.json
