#!/bin/bash
APP_ID=$1
[ -z "$APP_ID" ] && echo "Usage: $0 <APP_ID>" && exit 1
export API_URL="http://localhost:8000"
curl -X POST "$API_URL/applications/$APP_ID/fraud" \
  -H "Idempotency-Key: fraud-$APP_ID" \
  -H "Content-Type: application/json" \
  -d '{"risk_score": 10}' | jq
