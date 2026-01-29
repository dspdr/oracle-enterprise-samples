#!/bin/bash
# run.sh - Run the agent factory profile

source "$(dirname "$0")/env.sh"

echo "Starting Agent Factory..."
cd "$AGENT_FACTORY_HOME/../../infra"

if [ -z "$COMPOSE_CMD" ]; then
    # Fallback if env.sh didn't set it (shouldn't happen)
    export COMPOSE_CMD="podman compose"
fi

$COMPOSE_CMD --profile agent_factory up -d

echo "Agent Factory started. Access at https://localhost:8080/studio/"
