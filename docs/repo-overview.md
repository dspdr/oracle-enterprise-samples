# Repository Overview

This monorepo contains enterprise-grade samples built on Oracle Database, FastAPI, and deterministic workflow tooling.

## Structure

* `infra/`: Compose stack and Oracle DB init scripts.
* `services/`: Service implementations.
  * `loan_api`: REST API for loan origination.
  * `decision_agent`: Deterministic decision agent.
  * `workflows`: Wayflow workflow definitions.
* `samples/`: Sample-specific docs and client scripts.
  * `loan-origination/`: Primary end-to-end sample.
* `tools/`: Shared CLI scripts (reset, demo, teardown).
* `third_party/`: Optional integrations (Agent Factory).

## Navigation

* Root quick start: `README.md`
* Local dev guide: `docs/local-dev.md`
* Loan sample: `samples/loan-origination/README.md`
