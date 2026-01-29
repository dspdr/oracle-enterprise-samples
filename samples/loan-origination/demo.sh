#!/bin/bash
# demo.sh - Wrapper for shared demo script

set -e
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)

# Allow overriding API_URL; default to compose port
export API_URL="${API_URL:-http://localhost:8000}"

exec "$REPO_ROOT/tools/scripts/demo.sh"
