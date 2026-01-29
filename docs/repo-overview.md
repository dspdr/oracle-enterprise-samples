# Repository Overview

This monorepo contains enterprise-grade samples built on Oracle technology.

## Structure

*   `infra/`: Infrastructure as Code (Compose files, DB init).
*   `services/`: Microservices source code.
    *   `loan_api`: REST API for Loan Origination.
    *   `decision_agent`: Deterministic Decision Agent.
    *   `workflows`: Wayflow workflow definitions.
*   `samples/`: Documentation and client examples for specific business domains.
    *   `loan-origination/`: The primary sample.
*   `tools/`: Utility scripts.
*   `third_party/`: Integrations with external/optional tools (e.g., Agent Factory).
