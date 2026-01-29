#!/bin/bash
# reset.sh - Wrapper for shared reset script

set -e
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)

exec "$REPO_ROOT/tools/scripts/reset.sh"
