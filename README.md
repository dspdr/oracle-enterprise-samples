# Oracle Enterprise Samples

Enterprise-grade reference implementations built on Oracle Database, FastAPI, and deterministic workflows.

## Quick Start

1. Go to the sample:
   ```bash
   cd samples/loan-origination
   ```
2. Reset and start services:
   ```bash
   ./reset.sh
   ```
3. Run the demo:
   ```bash
   ./demo.sh
   ```

## What's Inside

* `samples/loan-origination/`: End-to-end loan origination workflow and API.
* `services/`: Application services (loan API, decision agent, workflows).
* `infra/`: Oracle DB containers and initialization SQL.
* `tools/scripts/`: Shared utility scripts (reset, demo, teardown).
* `docs/`: Repository overview and local development guidance.
* `third_party/agent_factory/`: Optional Oracle Agent Factory integration.

## Documentation

* Repository overview: `docs/repo-overview.md`
* Local development: `docs/local-dev.md`
* Loan sample docs: `samples/loan-origination/README.md`

## Requirements

* Docker Desktop or Podman Desktop
* Bash, curl, jq
