-- 03_views.sql
-- Shared Context SQL views + API package used by ORDS and APEX.

ALTER SESSION SET CURRENT_SCHEMA = shared_ctx_user;

CREATE OR REPLACE VIEW v_sc_cases AS
SELECT c.case_id,
       c.workspace_id,
       c.status,
       c.region,
       c.study_id,
       c.created_at,
       c.updated_at,
       (SELECT COUNT(*) FROM experiments e WHERE e.case_id = c.case_id) AS experiment_count,
       (SELECT COUNT(*)
          FROM samples s
          JOIN experiments e ON e.experiment_id = s.experiment_id
         WHERE e.case_id = c.case_id) AS sample_count,
       (SELECT COUNT(*) FROM reports r WHERE r.case_id = c.case_id) AS report_count,
       (SELECT COUNT(*) FROM evidence_chunks ec WHERE ec.case_id = c.case_id) AS evidence_chunk_count
  FROM cases c;
/

CREATE OR REPLACE VIEW v_sc_evidence_detail AS
SELECT ec.chunk_id,
       ec.case_id,
       ec.report_id,
       r.title AS report_title,
       c.workspace_id,
       c.status,
       c.region,
       c.study_id,
       ec.chunk_text,
       ec.embedding,
       ec.created_at
  FROM evidence_chunks ec
  JOIN reports r ON r.report_id = ec.report_id
  JOIN cases c   ON c.case_id = ec.case_id;
/

CREATE OR REPLACE FUNCTION sc_embedding_literal(p_text IN VARCHAR2)
  RETURN VARCHAR2 DETERMINISTIC
AS
  l_hash NUMBER := DBMS_UTILITY.GET_HASH_VALUE(LOWER(NVL(p_text, '')), 1, 1000000);
  l_out  VARCHAR2(500);

  FUNCTION dim(p_shift IN NUMBER) RETURN VARCHAR2 IS
    l_num NUMBER;
  BEGIN
    l_num := MOD(l_hash + p_shift * 7919, 1000) / 1000;
    RETURN TO_CHAR(l_num, 'FM0D0000', 'NLS_NUMERIC_CHARACTERS=.,');
  END;
BEGIN
  l_out := '[' ||
    dim(1) || ',' || dim(2) || ',' || dim(3) || ',' || dim(4) || ',' ||
    dim(5) || ',' || dim(6) || ',' || dim(7) || ',' || dim(8) || ']';
  RETURN l_out;
END;
/

CREATE OR REPLACE PACKAGE sc_context_api AS
  FUNCTION evidence_json(
    p_workspace_id IN VARCHAR2,
    p_case_id      IN VARCHAR2,
    p_query        IN VARCHAR2 DEFAULT NULL,
    p_limit        IN NUMBER   DEFAULT 5,
    p_status       IN VARCHAR2 DEFAULT NULL,
    p_region       IN VARCHAR2 DEFAULT NULL,
    p_study_id     IN VARCHAR2 DEFAULT NULL,
    p_from_ts      IN TIMESTAMP DEFAULT NULL,
    p_to_ts        IN TIMESTAMP DEFAULT NULL
  ) RETURN CLOB;

  FUNCTION audit_json(
    p_workspace_id IN VARCHAR2,
    p_case_id      IN VARCHAR2,
    p_limit        IN NUMBER DEFAULT 20
  ) RETURN CLOB;

  FUNCTION context_bundle_json(
    p_workspace_id IN VARCHAR2,
    p_case_id      IN VARCHAR2,
    p_query        IN VARCHAR2 DEFAULT NULL,
    p_limit        IN NUMBER DEFAULT 5
  ) RETURN CLOB;

  FUNCTION search_json(
    p_workspace_id IN VARCHAR2,
    p_body         IN CLOB
  ) RETURN CLOB;

  FUNCTION health_json RETURN CLOB;
END sc_context_api;
/

CREATE OR REPLACE PACKAGE BODY sc_context_api AS

  FUNCTION evidence_json(
    p_workspace_id IN VARCHAR2,
    p_case_id      IN VARCHAR2,
    p_query        IN VARCHAR2 DEFAULT NULL,
    p_limit        IN NUMBER   DEFAULT 5,
    p_status       IN VARCHAR2 DEFAULT NULL,
    p_region       IN VARCHAR2 DEFAULT NULL,
    p_study_id     IN VARCHAR2 DEFAULT NULL,
    p_from_ts      IN TIMESTAMP DEFAULT NULL,
    p_to_ts        IN TIMESTAMP DEFAULT NULL
  ) RETURN CLOB
  AS
    l_json CLOB;
  BEGIN
    SELECT JSON_OBJECT(
             'query' VALUE p_query,
             'results' VALUE COALESCE(
               (
                 SELECT JSON_ARRAYAGG(
                          JSON_OBJECT(
                            'chunkId'  VALUE q.chunk_id,
                            'score'    VALUE q.score,
                            'snippet'  VALUE DBMS_LOB.SUBSTR(q.chunk_text, 400, 1),
                            'reportId' VALUE q.report_id,
                            'caseId'   VALUE q.case_id,
                            'createdAt' VALUE TO_CHAR(q.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
                            'links'    VALUE JSON_OBJECT(
                                           'apexUrl' VALUE '/ords/r/shared-context-console/case-detail?case_id=' || q.case_id
                                         )
                          ) RETURNING CLOB
                        )
                   FROM (
                     SELECT ec.chunk_id,
                            ec.chunk_text,
                            ec.report_id,
                            ec.case_id,
                            CASE
                              WHEN p_query IS NULL OR TRIM(p_query) IS NULL THEN 0
                              ELSE VECTOR_DISTANCE(
                                     ec.embedding,
                                     TO_VECTOR(sc_embedding_literal(p_query), 8, FLOAT32),
                                     COSINE
                                   )
                            END AS score,
                            ec.created_at
                       FROM v_sc_evidence_detail ec
                      WHERE ec.workspace_id = p_workspace_id
                        AND ec.case_id = p_case_id
                        AND (p_status IS NULL OR ec.status = p_status)
                        AND (p_region IS NULL OR ec.region = p_region)
                        AND (p_study_id IS NULL OR ec.study_id = p_study_id)
                        AND (p_from_ts IS NULL OR ec.created_at >= p_from_ts)
                        AND (p_to_ts   IS NULL OR ec.created_at <= p_to_ts)
                      ORDER BY
                        CASE
                          WHEN p_query IS NULL OR TRIM(p_query) IS NULL THEN 0
                          ELSE VECTOR_DISTANCE(
                                 ec.embedding,
                                 TO_VECTOR(sc_embedding_literal(p_query), 8, FLOAT32),
                                 COSINE
                               )
                        END,
                        ec.created_at DESC
                      FETCH FIRST GREATEST(NVL(p_limit, 5), 1) ROWS ONLY
                   ) q
               ),
               JSON_ARRAY() RETURNING CLOB
             )
           RETURNING CLOB)
      INTO l_json
      FROM dual;

    RETURN l_json;
  END evidence_json;

  FUNCTION audit_json(
    p_workspace_id IN VARCHAR2,
    p_case_id      IN VARCHAR2,
    p_limit        IN NUMBER DEFAULT 20
  ) RETURN CLOB
  AS
    l_json CLOB;
  BEGIN
    SELECT JSON_OBJECT(
             'recent' VALUE COALESCE(
               (
                 SELECT JSON_ARRAYAGG(
                          JSON_OBJECT(
                            'eventId'        VALUE a.event_id,
                            'caseId'         VALUE a.case_id,
                            'actor'          VALUE a.actor,
                            'action'         VALUE a.action,
                            'policyVersion'  VALUE a.policy_version,
                            'createdAt'      VALUE TO_CHAR(a.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
                            'details'        VALUE a.details_json FORMAT JSON
                          ) RETURNING CLOB
                        )
                   FROM (
                     SELECT a.*
                       FROM audit_events a
                       JOIN cases c ON c.case_id = a.case_id
                      WHERE c.workspace_id = p_workspace_id
                        AND a.case_id = p_case_id
                      ORDER BY a.created_at DESC
                      FETCH FIRST GREATEST(NVL(p_limit, 20), 1) ROWS ONLY
                   ) a
               ),
               JSON_ARRAY() RETURNING CLOB
             )
           RETURNING CLOB)
      INTO l_json
      FROM dual;

    RETURN l_json;
  END audit_json;

  FUNCTION context_bundle_json(
    p_workspace_id IN VARCHAR2,
    p_case_id      IN VARCHAR2,
    p_query        IN VARCHAR2 DEFAULT NULL,
    p_limit        IN NUMBER DEFAULT 5
  ) RETURN CLOB
  AS
    l_case_count NUMBER;
    l_json       CLOB;
  BEGIN
    SELECT COUNT(*)
      INTO l_case_count
      FROM cases c
     WHERE c.workspace_id = p_workspace_id
       AND c.case_id = p_case_id;

    IF l_case_count = 0 THEN
      RETURN JSON_OBJECT(
               'error' VALUE 'CASE_NOT_FOUND',
               'caseId' VALUE p_case_id,
               'workspaceId' VALUE p_workspace_id,
               'freshness' VALUE JSON_OBJECT(
                 'generatedAt' VALUE TO_CHAR(SYSTIMESTAMP AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
                 'source' VALUE 'oracle-db'
               )
             RETURNING CLOB);
    END IF;

    SELECT JSON_OBJECT(
             'case' VALUE (
               SELECT JSON_OBJECT(
                        'caseId'      VALUE c.case_id,
                        'workspaceId' VALUE c.workspace_id,
                        'status'      VALUE c.status,
                        'region'      VALUE c.region,
                        'studyId'     VALUE c.study_id,
                        'createdAt'   VALUE TO_CHAR(c.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
                        'updatedAt'   VALUE TO_CHAR(c.updated_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
                      RETURNING CLOB)
                 FROM cases c
                WHERE c.workspace_id = p_workspace_id
                  AND c.case_id = p_case_id
             ) FORMAT JSON,
             'entities' VALUE JSON_OBJECT(
               'experiments' VALUE COALESCE(
                 (
                   SELECT JSON_ARRAYAGG(
                            JSON_OBJECT(
                              'experimentId' VALUE e.experiment_id,
                              'caseId'       VALUE e.case_id,
                              'type'         VALUE e.type,
                              'status'       VALUE e.status,
                              'startedAt'    VALUE TO_CHAR(e.started_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
                            ) RETURNING CLOB
                          )
                     FROM experiments e
                     JOIN cases c ON c.case_id = e.case_id
                    WHERE c.workspace_id = p_workspace_id
                      AND e.case_id = p_case_id
                 ),
                 JSON_ARRAY() RETURNING CLOB
               ),
               'samples' VALUE COALESCE(
                 (
                   SELECT JSON_ARRAYAGG(
                            JSON_OBJECT(
                              'sampleId'      VALUE s.sample_id,
                              'experimentId'  VALUE s.experiment_id,
                              'patientId'     VALUE s.patient_id,
                              'status'        VALUE s.status,
                              'collectedAt'   VALUE TO_CHAR(s.collected_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
                            ) RETURNING CLOB
                          )
                     FROM samples s
                     JOIN experiments e ON e.experiment_id = s.experiment_id
                     JOIN cases c ON c.case_id = e.case_id
                    WHERE c.workspace_id = p_workspace_id
                      AND e.case_id = p_case_id
                 ),
                 JSON_ARRAY() RETURNING CLOB
               ),
               'reports' VALUE COALESCE(
                 (
                   SELECT JSON_ARRAYAGG(
                            JSON_OBJECT(
                              'reportId'    VALUE r.report_id,
                              'caseId'      VALUE r.case_id,
                              'title'       VALUE r.title,
                              'body'        VALUE DBMS_LOB.SUBSTR(r.body, 1000, 1),
                              'createdAt'   VALUE TO_CHAR(r.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
                            ) RETURNING CLOB
                          )
                     FROM reports r
                     JOIN cases c ON c.case_id = r.case_id
                    WHERE c.workspace_id = p_workspace_id
                      AND r.case_id = p_case_id
                 ),
                 JSON_ARRAY() RETURNING CLOB
               )
             RETURNING CLOB),
             'evidence' VALUE evidence_json(
               p_workspace_id => p_workspace_id,
               p_case_id      => p_case_id,
               p_query        => p_query,
               p_limit        => p_limit
             ) FORMAT JSON,
             'governance' VALUE JSON_OBJECT(
               'policyFlags' VALUE JSON_OBJECT(
                 'workspaceScoped' VALUE 'true',
                 'readOnlyContext' VALUE 'true',
                 'mutationAllowed' VALUE 'false'
               ),
               'requiredApprovals' VALUE JSON_ARRAY('N/A: read-only endpoint')
             ),
             'audit' VALUE audit_json(
               p_workspace_id => p_workspace_id,
               p_case_id      => p_case_id,
               p_limit        => 20
             ) FORMAT JSON,
             'freshness' VALUE JSON_OBJECT(
               'generatedAt' VALUE TO_CHAR(SYSTIMESTAMP AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
               'source' VALUE 'oracle-db',
               'cache' VALUE JSON_OBJECT(
                 'enabled' VALUE 'false',
                 'note' VALUE 'Optional True Cache read-through can be added for hot case lookups.'
               )
             )
           RETURNING CLOB)
      INTO l_json
      FROM dual;

    RETURN l_json;
  END context_bundle_json;

  FUNCTION search_json(
    p_workspace_id IN VARCHAR2,
    p_body         IN CLOB
  ) RETURN CLOB
  AS
    l_json     CLOB;
    l_query    VARCHAR2(4000);
    l_status   VARCHAR2(30);
    l_region   VARCHAR2(30);
    l_study_id VARCHAR2(30);
    l_case_id  VARCHAR2(40);
    l_limit    NUMBER := 10;
  BEGIN
    l_query    := JSON_VALUE(p_body, '$.query' RETURNING VARCHAR2(4000));
    l_status   := JSON_VALUE(p_body, '$.filters.status' RETURNING VARCHAR2(30));
    l_region   := JSON_VALUE(p_body, '$.filters.region' RETURNING VARCHAR2(30));
    l_study_id := JSON_VALUE(p_body, '$.filters.studyId' RETURNING VARCHAR2(30));
    l_case_id  := JSON_VALUE(p_body, '$.filters.caseId' RETURNING VARCHAR2(40));
    l_limit    := NVL(JSON_VALUE(p_body, '$.limit' RETURNING NUMBER), 10);

    SELECT JSON_OBJECT(
             'results' VALUE COALESCE(
               (
                 SELECT JSON_ARRAYAGG(
                          JSON_OBJECT(
                            'caseId' VALUE q.case_id,
                            'title'  VALUE q.title,
                            'score'  VALUE q.score,
                            'status' VALUE q.status,
                            'region' VALUE q.region
                          ) RETURNING CLOB
                        )
                   FROM (
                     SELECT c.case_id,
                            c.status,
                            c.region,
                            MAX(r.title) KEEP (DENSE_RANK LAST ORDER BY r.created_at) AS title,
                            MIN(
                              CASE
                                WHEN l_query IS NULL OR TRIM(l_query) IS NULL THEN 0
                                ELSE VECTOR_DISTANCE(
                                       ec.embedding,
                                       TO_VECTOR(sc_embedding_literal(l_query), 8, FLOAT32),
                                       COSINE
                                     )
                              END
                            ) AS score,
                            MAX(c.updated_at) AS updated_at
                       FROM cases c
                       LEFT JOIN reports r ON r.case_id = c.case_id
                       LEFT JOIN evidence_chunks ec ON ec.case_id = c.case_id
                      WHERE c.workspace_id = p_workspace_id
                        AND (l_status IS NULL OR c.status = l_status)
                        AND (l_region IS NULL OR c.region = l_region)
                        AND (l_study_id IS NULL OR c.study_id = l_study_id)
                        AND (l_case_id IS NULL OR c.case_id = l_case_id)
                      GROUP BY c.case_id, c.status, c.region
                      ORDER BY score NULLS LAST, updated_at DESC
                      FETCH FIRST GREATEST(NVL(l_limit, 10), 1) ROWS ONLY
                   ) q
               ),
               JSON_ARRAY() RETURNING CLOB
             )
           RETURNING CLOB)
      INTO l_json
      FROM dual;

    RETURN l_json;
  END search_json;

  FUNCTION health_json RETURN CLOB
  AS
    l_start NUMBER := DBMS_UTILITY.GET_TIME;
    l_json  CLOB;
    l_ping  NUMBER;
  BEGIN
    SELECT 1 INTO l_ping FROM dual;

    SELECT JSON_OBJECT(
             'status' VALUE CASE WHEN l_ping = 1 THEN 'ok' ELSE 'degraded' END,
             'source' VALUE 'oracle-db',
             'generatedAt' VALUE TO_CHAR(SYSTIMESTAMP AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
             'elapsedMs' VALUE ROUND((DBMS_UTILITY.GET_TIME - l_start) * 10, 2)
           RETURNING CLOB)
      INTO l_json
      FROM dual;

    RETURN l_json;
  END health_json;

END sc_context_api;
/

EXIT;
