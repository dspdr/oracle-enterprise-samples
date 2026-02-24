-- 02_seed.sql
-- Deterministic synthetic seed data for Shared Context sample.

ALTER SESSION SET CURRENT_SCHEMA = shared_ctx_user;

CREATE OR REPLACE PROCEDURE sc_generate_synthetic(
  p_seed       IN NUMBER DEFAULT 4242,
  p_case_count IN NUMBER DEFAULT 6,
  p_workspace  IN VARCHAR2 DEFAULT 'WS1'
) AS
  v_case_id      VARCHAR2(40);
  v_exp_id       VARCHAR2(40);
  v_sample_id    VARCHAR2(40);
  v_report_id    VARCHAR2(40);
  v_status       VARCHAR2(30);
  v_region       VARCHAR2(30);
  v_study        VARCHAR2(30);
  v_embed_txt    VARCHAR2(500);
  v_chunk_text   CLOB;
BEGIN
  DBMS_RANDOM.SEED(p_seed);

  DELETE FROM evidence_chunks;
  DELETE FROM audit_events;
  DELETE FROM samples;
  DELETE FROM experiments;
  DELETE FROM reports;
  DELETE FROM cases;

  FOR i IN 1 .. p_case_count LOOP
    v_case_id := 'CASE-' || LPAD(i, 4, '0');

    v_status := CASE MOD(i, 3)
      WHEN 0 THEN 'OPEN'
      WHEN 1 THEN 'IN_REVIEW'
      ELSE 'CLOSED'
    END;

    v_region := CASE MOD(i, 4)
      WHEN 0 THEN 'NA'
      WHEN 1 THEN 'EMEA'
      WHEN 2 THEN 'APAC'
      ELSE 'LATAM'
    END;

    v_study := 'STUDY-' || LPAD(MOD(i, 3) + 1, 2, '0');

    INSERT INTO cases(case_id, workspace_id, status, region, study_id, created_at, updated_at)
    VALUES (
      v_case_id,
      p_workspace,
      v_status,
      v_region,
      v_study,
      SYSTIMESTAMP - NUMTODSINTERVAL(30 - i, 'DAY'),
      SYSTIMESTAMP - NUMTODSINTERVAL(i, 'HOUR')
    );

    FOR e IN 1 .. 2 LOOP
      v_exp_id := 'EXP-' || LPAD(i, 4, '0') || '-' || e;
      INSERT INTO experiments(experiment_id, case_id, type, status, started_at)
      VALUES (
        v_exp_id,
        v_case_id,
        CASE e WHEN 1 THEN 'GENOMIC' ELSE 'PROTEOMIC' END,
        CASE MOD(i + e, 2) WHEN 0 THEN 'RUNNING' ELSE 'COMPLETE' END,
        SYSTIMESTAMP - NUMTODSINTERVAL(i * e + 1, 'DAY')
      );

      FOR s IN 1 .. 2 LOOP
        v_sample_id := 'SMP-' || LPAD(i, 4, '0') || '-' || e || '-' || s;
        INSERT INTO samples(sample_id, experiment_id, patient_id, status, collected_at)
        VALUES (
          v_sample_id,
          v_exp_id,
          'PT-' || LPAD(i * 10 + e * 2 + s, 5, '0'),
          CASE MOD(s + e + i, 3)
            WHEN 0 THEN 'COLLECTED'
            WHEN 1 THEN 'PROCESSING'
            ELSE 'QC_FAILED'
          END,
          SYSTIMESTAMP - NUMTODSINTERVAL(i + s, 'DAY')
        );
      END LOOP;
    END LOOP;

    v_report_id := 'RPT-' || LPAD(i, 4, '0');
    INSERT INTO reports(report_id, case_id, title, body, created_at)
    VALUES (
      v_report_id,
      v_case_id,
      'Case ' || v_case_id || ' interim findings',
      'Synthetic report for ' || v_case_id || ' in ' || v_region || ' with status ' || v_status,
      SYSTIMESTAMP - NUMTODSINTERVAL(i, 'DAY')
    );

    INSERT INTO audit_events(case_id, actor, action, policy_version, created_at, details_json)
    VALUES (
      v_case_id,
      'coordinator_' || MOD(i, 3),
      'CASE_CREATED',
      'v1.0',
      SYSTIMESTAMP - NUMTODSINTERVAL(i, 'DAY'),
      JSON_OBJECT('note' VALUE 'Case created', 'workspace' VALUE p_workspace RETURNING CLOB)
    );

    INSERT INTO audit_events(case_id, actor, action, policy_version, created_at, details_json)
    VALUES (
      v_case_id,
      'qa_' || MOD(i, 4),
      'EVIDENCE_VALIDATED',
      'v1.1',
      SYSTIMESTAMP - NUMTODSINTERVAL(i, 'HOUR'),
      JSON_OBJECT('note' VALUE 'Validation completed', 'severity' VALUE 'LOW' RETURNING CLOB)
    );

    FOR c IN 1 .. 3 LOOP
      v_chunk_text := 'Evidence chunk ' || c || ' for ' || v_case_id ||
                     ': biomarker trend and protocol adherence mention study ' || v_study;

      v_embed_txt := '[' ||
        TO_CHAR(ROUND((i + c) / 10, 4), 'FM0.0000') || ',' ||
        TO_CHAR(ROUND((i * c) / 15, 4), 'FM0.0000') || ',' ||
        TO_CHAR(ROUND((MOD(i + 2 * c, 7) + 1) / 10, 4), 'FM0.0000') || ',' ||
        TO_CHAR(ROUND((MOD(i + c, 9) + 1) / 10, 4), 'FM0.0000') || ',' ||
        TO_CHAR(ROUND((MOD(i, 5) + c) / 10, 4), 'FM0.0000') || ',' ||
        TO_CHAR(ROUND((c + 1) / 10, 4), 'FM0.0000') || ',' ||
        TO_CHAR(ROUND((MOD(i + c, 4) + 1) / 10, 4), 'FM0.0000') || ',' ||
        TO_CHAR(ROUND((MOD(i * c, 6) + 1) / 10, 4), 'FM0.0000') ||
      ']';

      INSERT INTO evidence_chunks(chunk_id, report_id, case_id, chunk_text, embedding, created_at)
      VALUES (
        'CHK-' || LPAD(i, 4, '0') || '-' || c,
        v_report_id,
        v_case_id,
        v_chunk_text,
        TO_VECTOR(v_embed_txt, 8, FLOAT32),
        SYSTIMESTAMP - NUMTODSINTERVAL(i * c, 'HOUR')
      );
    END LOOP;
  END LOOP;

  COMMIT;
END;
/

BEGIN
  sc_generate_synthetic(p_seed => 4242, p_case_count => 8, p_workspace => 'WS1');
  sc_generate_synthetic(p_seed => 5252, p_case_count => 3, p_workspace => 'WS2');
END;
/

EXIT;
