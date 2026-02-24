# Shared Context Layer Notes

## Scope

The implementation under `samples/shared-context/` provides a read-only shared context foundation for:
- Frontier-style agent tool calls via ORDS,
- human validation via APEX pages,
- consistent context JSON responses from the same Oracle schema and package.

## Core Design

- Relational truth: `cases`, `experiments`, `samples`, `reports`, `audit_events`
- Semantic evidence: `evidence_chunks.embedding VECTOR(8, FLOAT32)`
- Unified API package: `sc_context_api`
- ORDS module: `shared_context` mapped at `/context/*`

## Canonical Bundle

`sc_context_api.context_bundle_json(workspace, case, query, limit)` returns:
- case metadata,
- entity arrays,
- evidence object,
- governance flags,
- recent audit,
- freshness metadata.

## Instrumentation Hooks

Current hooks are minimal and demo-friendly:
- `/context/health` returns DB responsiveness and generated timestamp.
- Endpoint responses include freshness metadata for staleness checks.
- `Cache-Control: no-store` is set in ORDS handlers to avoid accidental stale caching during development.

## Optional Next Hardening Steps

- Add authenticated workspace mapping (JWT claims -> workspace_id).
- Add endpoint-level policy checks with ORDS privilege roles.
- Add vector index and tuned distance strategy for larger evidence volumes.
- Add request tracing IDs and DB module/action tagging for observability.
