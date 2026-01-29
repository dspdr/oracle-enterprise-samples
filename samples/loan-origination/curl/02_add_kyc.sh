#!/bin/bash
APP_ID=$1
[ -z "$APP_ID" ] && echo "Usage: $0 <APP_ID>" && exit 1
export API_URL="http://localhost:8000"
curl -X POST "$API_URL/applications/$APP_ID/kyc" \
  -H "Idempotency-Key: kyc-$APP_ID" \
  -H "Content-Type: application/json" \
  -d '{"status": "PASS"}' | jq
