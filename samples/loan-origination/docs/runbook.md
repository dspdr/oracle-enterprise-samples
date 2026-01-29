# Loan Origination Runbook

## System Overview

The Loan Origination system is a microservice-style application built with Python 3.11 and FastAPI, utilizing Oracle Database 23c/Free for persistence and concurrency control. It employs the "Wayflow" pattern for deterministic workflow execution.

## Deployment Architecture

The solution runs as a set of containerized services:

1.  **Loan API**: The main entry point, hosting the workflow engine and decision agent.
2.  **Oracle Database**: System of Record, Idempotency Store, and Audit Log.

Default Runtime: **Podman Desktop** (Rootless).

## Operational Procedures

### Start-Up
Run `podman compose up -d` in the `infra/` directory.
Wait for the database health check to pass.

### Reset
Run `tools/scripts/reset.sh` to wipe data and restart containers.

## Core Mechanisms

### Idempotency
All POST endpoints enforce idempotency via the `Idempotency-Key` header.
*   **Key Storage**: `idempotency_keys` table in Oracle.
*   **Uniqueness**: `(idempotency_key, route_path)`.
*   **Payload Verification**: SHA-256 hash of `canonical(body) + request_mode + execution_mode`.
*   **Behavior**:
    *   **New Key**: Process and store result.
    *   **Retry (Same Payload)**: Return cached result.
    *   **Retry (Diff Payload)**: Return HTTP 409 Conflict.
    *   **In-Progress**: Return HTTP 409 Conflict.

### Dry-Run Execution
The `/applications/{id}/decision/dry-run` endpoint executes the decision logic without committing changes to the System of Record.
*   **Workflow Mode**: `DRY_RUN`.
*   **Side Effects**: Disabled (Persistence steps are skipped).
*   **Output**: Full decision structure (Decision, Reason Codes, Pricing).

### Execute Execution
The `/applications/{id}/decision/execute` endpoint commits the decision.
*   **Workflow Mode**: `EXECUTE`.
*   **Side Effects**: Database updates, Audit logs.

## Troubleshooting

### Database Connectivity
Check `infra/compose.yaml` healthcheck.
Ensure `ORACLE_PWD` matches `DB_PASSWORD` in `loan-api`.

### Application Logs
View logs via `podman compose logs -f loan-api`.
structured JSON logging is recommended for production (simplified text logging used in sample).
