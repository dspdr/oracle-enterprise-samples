#!/bin/bash
APP_ID=$1
[ -z "$APP_ID" ] && echo "Usage: $0 <APP_ID>" && exit 1
export API_URL="http://localhost:8000"
curl -X POST "$API_URL/applications/$APP_ID/decision/dry-run" \
  -H "Idempotency-Key: dry-$APP_ID" \
  -H "Content-Length: 0" | jq
