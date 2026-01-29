# Oracle AI Database Private Agent Factory

This directory supports the optional integration of Oracle AI Database Private Agent Factory (25.3) on macOS Apple Silicon.

## Requirements

*   **Hardware**: Apple Silicon (M1/M2/M3)
*   **Software**: Podman Desktop (Rootless). Docker is not supported for this integration.
*   **Kit**: `applied_ai_arm64.tar.gz` (Must be obtained from Oracle)

## Installation Instructions

1.  **Download & Extract**
    Obtain the `applied_ai_arm64.tar.gz` distribution and extract it to a temporary location.
    ```bash
    tar -xzvf applied_ai_arm64.tar.gz
    cd applied_ai_arm64
    ```

2.  **Install Images**
    Run the interactive installer to load the necessary container images into Podman.
    ```bash
    bash interactive_install.sh
    ```
    Ensure the installation completes successfully.

## Usage

To run the Agent Factory UI alongside the Loan Origination sample:

1.  Ensure the Loan Sample infrastructure is configured (or just run the start script below).
2.  Execute the run script:
    ```bash
    ./scripts/run.sh
    ```
    This will start the `agent-factory` service defined in `infra/compose.yaml`.

3.  **Access the UI**
    Open your browser to: [https://localhost:8080/studio/](https://localhost:8080/studio/)

## Constraints

*   This integration is strictly for local development on macOS/ARM64.
*   Do not commit the `applied_ai_arm64.tar.gz` or extracted binaries to this repository.
