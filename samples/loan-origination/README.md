# Loan Origination and Credit Decisioning Sample

This sample demonstrates an enterprise-grade loan origination process using Oracle Database, Python 3.11, and Wayflow.

## Core Features

*   **Deterministic Workflow**: Logic execution is reproducible and verifiable.
*   **Planning & Simulation**: Generate decision plans with AI-enriched commentary and synthetic scenarios.
*   **Strong Idempotency**: Requests are de-duplicated using `Idempotency-Key` backed by Oracle Database.
*   **Dry-Run Capability**: Execute decisions in a safe mode with zero side effects.
*   **True Cache Integration**: Optional read-only caching tier for high performance.
*   **Auditability**: All actions and decisions are recorded.

## Getting Started

1.  Start the infrastructure:
    ```bash
    ./reset.sh
    ```

2.  Run the demo script:
    ```bash
    ./demo.sh
    ```

3.  Tear down everything:
    ```bash
    ./teardown.sh
    ```

### Optional Overrides

* Override API URL:
  ```bash
  API_URL=http://localhost:18000 ./demo.sh
  ```
* Override DB image/service:
  ```bash
  DB_IMAGE=container-registry.oracle.com/database/free:latest DB_SERVICE=FREEPDB1 ./reset.sh
  ```

## Documentation

Detailed documentation is available in the `docs/` directory:

*   [Runbook](docs/runbook.md) - Operational guide for Enterprise Architects.
*   [Architecture](docs/runbook.md#deployment-architecture) - System diagrams.
*   [Data Model](../../infra/db/oracle/init/01_schema.sql) - Database schema.
*   [Agent Specification](../../services/decision_agent/agent_spec/manifest.yaml) - Decision logic definition.

## Decision Flow Diagram

End-to-end workflow (embedded):

```mermaid
flowchart TB
  A[Create Application] --> K[Collect KYC Result]
  K --> F[Collect Fraud Result]
  F --> C[Collect Credit Score]
  C --> DR[Dry-Run Decision Optional]
  DR --> P[Planning]
  P --> AI[Oracle AI / Synthetic Data]
  AI --> P
  P --> Plan[Decision Plan Artifact]
  Plan --> E[Execute]
  E --> D[LoanDecisionAgent]
  D --> Dec{Decision}
  Dec -->|APPROVE| G[Pricing]
  Dec -->|REJECT| H[Reason Codes]
  Dec -->|REFER| H
```

Sequence view (also embedded; source lives in `docs/workflow.mmd`):

```mermaid
sequenceDiagram
    participant Client
    participant API
    participant DB
    participant AI

    Client->>API: POST /applications
    API->>DB: Persist Application
    API-->>Client: Application Created

    Client->>API: POST /applications/{id}/kyc
    API->>DB: Persist KYC Result
    Client->>API: POST /applications/{id}/fraud
    API->>DB: Persist Fraud Result
    Client->>API: POST /applications/{id}/credit-score
    API->>DB: Persist Credit Score

    Client->>API: POST /applications/{id}/decision/dry-run
    API->>DB: Fetch Application Snapshot
    API->>API: Run Deterministic Decision (No Side Effects)
    API-->>Client: Dry-Run Decision

    Client->>API: POST /applications/{id}/decision/plan
    API->>DB: Fetch Application Snapshot
    API->>AI: Generate Synthetic Scenarios (via DB)
    AI-->>API: Scenarios List
    loop For Each Scenario
        API->>API: Run Deterministic Decision
    end
    API->>AI: Generate Commentary
    API->>DB: Persist Plan
    API-->>Client: Decision Plan

    Client->>API: POST /applications/{id}/decision/execute (Plan)
    API->>DB: Validate Inputs Hash
    alt Hash Match
        API->>API: Execute Decision (Idempotent)
        API->>DB: Write Offers & Audit
        API-->>Client: Success
    else Mismatch
        API-->>Client: 409 Conflict
    end
```

## Database Entity Diagram

```mermaid
erDiagram
    APPLICATIONS {
        VARCHAR2 id PK
        VARCHAR2 status
        CLOB applicant_data
        CLOB decision_data
        TIMESTAMP created_at
        TIMESTAMP updated_at
    }
    AUDIT_LOGS {
        NUMBER id PK
        VARCHAR2 application_id
        VARCHAR2 action
        CLOB details
        TIMESTAMP created_at
    }
    DECISION_PLANS {
        VARCHAR2 plan_id PK
        VARCHAR2 workspace_id
        VARCHAR2 application_id
        VARCHAR2 idempotency_key
        VARCHAR2 inputs_hash
        CLOB plan_json
        VARCHAR2 status
        TIMESTAMP created_at
        TIMESTAMP executed_at
    }
    IDEMPOTENCY_KEYS {
        VARCHAR2 idempotency_key PK
        VARCHAR2 route_path PK
        VARCHAR2 payload_hash
        VARCHAR2 request_mode
        VARCHAR2 execution_mode
        VARCHAR2 status
        NUMBER response_code
        CLOB response_body
        TIMESTAMP created_at
        TIMESTAMP updated_at
    }

    APPLICATIONS ||--o{ AUDIT_LOGS : "application_id"
    APPLICATIONS ||--o{ DECISION_PLANS : "application_id"
```

## Directory Structure

*   `payloads/`: JSON payload examples.
*   `curl/`: Individual scripts for stepping through the API.
*   `docs/`: Runbook and operational notes.
*   `demo.sh`, `reset.sh`, `teardown.sh`: Sample-local wrappers for shared scripts.
