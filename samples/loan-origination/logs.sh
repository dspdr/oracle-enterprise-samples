#!/bin/bash
# logs.sh - Wrapper for shared logs script

set -e
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)

exec "$REPO_ROOT/tools/scripts/logs.sh"
