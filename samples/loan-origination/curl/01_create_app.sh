#!/bin/bash
export API_URL="http://localhost:8000"
curl -X POST "$API_URL/applications" \
  -H "Idempotency-Key: create-$(date +%s)" \
  -H "Content-Type: application/json" \
  -d @../payloads/application.json | jq
