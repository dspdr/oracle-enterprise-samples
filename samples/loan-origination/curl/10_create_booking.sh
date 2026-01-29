#!/bin/bash
APP_ID=$1
[ -z "$APP_ID" ] && echo "Usage: $0 <APP_ID>" && exit 1
export API_URL="http://localhost:8000"
curl -X POST "$API_URL/bookings" \
  -H "Idempotency-Key: booking-$APP_ID" \
  -H "Content-Type: application/json" \
  -d "{\"application_id\": \"$APP_ID\", \"activation_date\": \"2023-10-01\"}" | jq
