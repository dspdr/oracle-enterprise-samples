#!/bin/bash
# env.sh - Detect environment

if command -v podman &> /dev/null; then
    if podman info &> /dev/null; then
        export CONTAINER_ENGINE=podman
        export COMPOSE_CMD="podman compose"
    elif command -v docker &> /dev/null; then
        export CONTAINER_ENGINE=docker
        export COMPOSE_CMD="docker compose"
    else
        echo "Error: Podman is installed but not running; Docker not found."
        exit 1
    fi
elif command -v docker &> /dev/null; then
    export CONTAINER_ENGINE=docker
    export COMPOSE_CMD="docker compose"
else
    echo "Error: No container engine (podman/docker) found."
    exit 1
fi

export API_URL="${API_URL:-http://localhost:8000}"
export PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)
