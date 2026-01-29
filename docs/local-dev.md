# Local Development Guide

## Prerequisites

*   **Python 3.11+**
*   **Podman Desktop** (or Docker Desktop)
*   **Oracle Instant Client** (Optional, if running locally outside container with thick mode)

## Setup

1.  Clone the repository.
2.  Navigate to `infra/` and start services:
    ```bash
    podman compose up -d
    ```
3.  Run the demo:
    ```bash
    ./tools/scripts/demo.sh
    ```

## Development

*   Services are located in `services/`.
*   Each service (e.g., `loan_api`) has a `Containerfile` for building.
*   To rebuild after changes:
    ```bash
    podman compose build
    podman compose up -d
    ```
