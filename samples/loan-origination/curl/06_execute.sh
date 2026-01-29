#!/bin/bash
# Usage: ./06_execute.sh <APP_ID>
APP_ID=$1
if [ -z "$APP_ID" ]; then echo "Usage: $0 <APP_ID>"; exit 1; fi
export API_URL="http://localhost:8000"
curl -X POST "$API_URL/applications/$APP_ID/decision/execute" \
  -H "Idempotency-Key: exec-$APP_ID" \
  -H "Content-Length: 0" | jq
