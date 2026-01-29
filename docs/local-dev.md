# Local Development Guide

## Prerequisites

* **Python 3.11+**
* **Docker Desktop or Podman Desktop**
* **Oracle Instant Client** (Optional; only if running locally outside containers with thick mode)
* **Tools**: `bash`, `curl`, `jq`

## Setup

1. Clone the repository.
2. Start the sample from its directory:
   ```bash
   cd samples/loan-origination
   ./reset.sh
   ```
3. Run the demo:
   ```bash
   ./demo.sh
   ```

4. Tear down:
   ```bash
   ./teardown.sh
   ```

## Development

* Services are located in `services/`.
* Each service (e.g., `loan_api`) has a `Containerfile` for building.
* To rebuild after changes:
  ```bash
  cd infra
  docker compose build
  docker compose up -d
  ```

## Ports

* Loan API: `http://localhost:8000`
* Oracle DB: `localhost:1521`

## Using Podman Instead of Docker

If Podman is running, the scripts use it automatically; otherwise they fall back to Docker.
