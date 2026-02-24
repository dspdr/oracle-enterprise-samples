# Shared Context Console (APEX Build Guide)

## App
- Name: `Shared Context Console`
- Parsing Schema: `SHARED_CTX_USER`
- Authentication: APEX default for local demo

## Shared Page Items
- `P0_WORKSPACE_ID` (default `WS1`)
- `P0_ORDS_BASE_URL` (default `http://localhost:8080/ords/shared-context/context`)

## Page 1: Case Search
- Type: Interactive Report
- Source SQL:
```sql
SELECT case_id,
       workspace_id,
       status,
       region,
       study_id,
       experiment_count,
       sample_count,
       report_count,
       evidence_chunk_count,
       created_at,
       updated_at
  FROM v_sc_cases
 WHERE workspace_id = :P0_WORKSPACE_ID
 ORDER BY updated_at DESC
```
- Link `CASE_ID` column to Page 2 with `P2_CASE_ID=&CASE_ID.`

## Page 2: Case Detail
- Items: `P2_CASE_ID`
- Region A (Case Header), SQL:
```sql
SELECT c.case_id,
       c.workspace_id,
       c.status,
       c.region,
       c.study_id,
       c.created_at,
       c.updated_at
  FROM cases c
 WHERE c.workspace_id = :P0_WORKSPACE_ID
   AND c.case_id = :P2_CASE_ID
```
- Region B (Experiments), SQL:
```sql
SELECT experiment_id, type, status, started_at
  FROM experiments
 WHERE case_id = :P2_CASE_ID
 ORDER BY started_at DESC
```
- Region C (Samples), SQL:
```sql
SELECT s.sample_id,
       s.experiment_id,
       s.patient_id,
       s.status,
       s.collected_at
  FROM samples s
  JOIN experiments e ON e.experiment_id = s.experiment_id
 WHERE e.case_id = :P2_CASE_ID
 ORDER BY s.collected_at DESC
```
- Region D (Reports), SQL:
```sql
SELECT report_id, title, body, created_at
  FROM reports
 WHERE case_id = :P2_CASE_ID
 ORDER BY created_at DESC
```

## Page 3: Evidence Search
- Items: `P3_CASE_ID`, `P3_QUERY`, `P3_LIMIT` (default 10), `P3_STATUS`, `P3_REGION`, `P3_STUDY_ID`
- Region SQL:
```sql
SELECT q.chunk_id,
       q.case_id,
       q.report_id,
       q.score,
       q.snippet,
       q.created_at
  FROM JSON_TABLE(
         sc_context_api.evidence_json(
           p_workspace_id => :P0_WORKSPACE_ID,
           p_case_id      => :P3_CASE_ID,
           p_query        => :P3_QUERY,
           p_limit        => :P3_LIMIT,
           p_status       => :P3_STATUS,
           p_region       => :P3_REGION,
           p_study_id     => :P3_STUDY_ID
         ),
         '$.results[*]'
         COLUMNS (
           chunk_id    VARCHAR2(40)   PATH '$.chunkId',
           case_id     VARCHAR2(40)   PATH '$.caseId',
           report_id   VARCHAR2(40)   PATH '$.reportId',
           score       NUMBER         PATH '$.score',
           snippet     VARCHAR2(4000) PATH '$.snippet',
           created_at  VARCHAR2(30)   PATH '$.createdAt'
         )
       ) q
```

## Page 4: Context Bundle Preview
- Items: `P4_CASE_ID`, `P4_QUERY`, `P4_LIMIT` (default 5)
- Region type: PL/SQL Dynamic Content
- PL/SQL:
```plsql
DECLARE
  l_json CLOB;
BEGIN
  l_json := sc_context_api.context_bundle_json(
    p_workspace_id => :P0_WORKSPACE_ID,
    p_case_id      => :P4_CASE_ID,
    p_query        => :P4_QUERY,
    p_limit        => :P4_LIMIT
  );

  HTP.P('<pre>' || APEX_ESCAPE.HTML(l_json) || '</pre>');
END;
```

## Page 5: Audit Timeline
- Items: `P5_CASE_ID`, `P5_LIMIT` (default 20)
- SQL:
```sql
SELECT a.event_id,
       a.case_id,
       a.actor,
       a.action,
       a.policy_version,
       a.created_at,
       a.details_json
  FROM audit_events a
  JOIN cases c ON c.case_id = a.case_id
 WHERE c.workspace_id = :P0_WORKSPACE_ID
   AND (:P5_CASE_ID IS NULL OR a.case_id = :P5_CASE_ID)
 ORDER BY a.created_at DESC
 FETCH FIRST NVL(:P5_LIMIT, 20) ROWS ONLY
```

## Optional REST Data Source Wiring
- Create Web Source module for `&P0_ORDS_BASE_URL./cases/&P2_CASE_ID.`
- Use it for the Context Bundle Preview page if you want UI parity with agent endpoint calls.

