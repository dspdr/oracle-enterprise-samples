#!/bin/bash
# teardown.sh - Wrapper for shared teardown script

set -e
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)

exec "$REPO_ROOT/tools/scripts/teardown.sh"
