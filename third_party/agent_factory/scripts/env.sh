#!/bin/bash

if [[ $(uname -m) != "arm64" ]]; then
    echo "Error: Oracle Agent Factory requires Apple Silicon (arm64) on macOS."
    exit 1
fi

if ! command -v podman &> /dev/null; then
    echo "Error: Podman is required."
    exit 1
fi

if [[ $EUID -eq 0 ]]; then
   echo "Error: This script must not be run as root."
   exit 1
fi

export AGENT_FACTORY_HOME=$(cd "$(dirname "${BASH_SOURCE[0]}")/../" && pwd)
