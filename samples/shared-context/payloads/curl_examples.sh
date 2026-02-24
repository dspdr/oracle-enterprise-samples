#!/usr/bin/env bash
set -euo pipefail

ORDS_BASE_URL="${ORDS_BASE_URL:-http://localhost:8080/ords/shared-context/context}"
WORKSPACE_ID="${WORKSPACE_ID:-WS1}"
CASE_ID="${CASE_ID:-CASE-0001}"

pretty() {
  if command -v jq >/dev/null 2>&1; then
    jq .
  else
    cat
  fi
}

echo "== Health =="
curl -s "${ORDS_BASE_URL}/health" | pretty

echo "== Case Context Bundle =="
curl -s "${ORDS_BASE_URL}/cases/${CASE_ID}?workspaceId=${WORKSPACE_ID}&limit=5" | pretty

echo "== Case Evidence (semantic + relational filters) =="
curl -s "${ORDS_BASE_URL}/cases/${CASE_ID}/evidence?workspaceId=${WORKSPACE_ID}&query=biomarker+trend&status=IN_REVIEW&region=EMEA&studyId=STUDY-02&limit=5" | pretty

echo "== Case Audit =="
curl -s "${ORDS_BASE_URL}/cases/${CASE_ID}/audit?workspaceId=${WORKSPACE_ID}&limit=10" | pretty

echo "== Search =="
curl -s -X POST "${ORDS_BASE_URL}/search?workspaceId=${WORKSPACE_ID}" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": "protocol deviation and biomarker trend",
    "filters": {
      "status": "IN_REVIEW",
      "region": "EMEA",
      "studyId": "STUDY-02"
    },
    "limit": 10
  }' | pretty
