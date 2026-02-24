-- 04_ords_modules.sql
-- ORDS REST modules for Shared Context sample.

ALTER SESSION SET CURRENT_SCHEMA = shared_ctx_user;

BEGIN
  ORDS.ENABLE_SCHEMA(
    p_enabled             => TRUE,
    p_schema              => 'SHARED_CTX_USER',
    p_url_mapping_type    => 'BASE_PATH',
    p_url_mapping_pattern => 'shared-context',
    p_auto_rest_auth      => FALSE
  );
  COMMIT;
END;
/

BEGIN
  ORDS.DELETE_MODULE(p_module_name => 'shared_context');
  COMMIT;
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END;
/

BEGIN
  ORDS.DEFINE_MODULE(
    p_module_name    => 'shared_context',
    p_base_path      => '/context/',
    p_items_per_page => 25,
    p_status         => 'PUBLISHED'
  );

  ORDS.DEFINE_TEMPLATE(
    p_module_name => 'shared_context',
    p_pattern     => 'cases/:caseId'
  );

  ORDS.DEFINE_HANDLER(
    p_module_name => 'shared_context',
    p_pattern     => 'cases/:caseId',
    p_method      => 'GET',
    p_source_type => ORDS.SOURCE_TYPE_PLSQL,
    p_source      => q'[
DECLARE
  l_workspace_id VARCHAR2(64) := NVL(:workspaceId, 'WS1');
  l_limit        NUMBER := COALESCE(TO_NUMBER(:limit), 5);
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', FALSE);
  HTP.P('Cache-Control: no-store');
  OWA_UTIL.HTTP_HEADER_CLOSE;

  HTP.P(sc_context_api.context_bundle_json(
    p_workspace_id => l_workspace_id,
    p_case_id      => :caseId,
    p_query        => :query,
    p_limit        => l_limit
  ));
END;]'
  );

  ORDS.DEFINE_TEMPLATE(
    p_module_name => 'shared_context',
    p_pattern     => 'search'
  );

  ORDS.DEFINE_HANDLER(
    p_module_name => 'shared_context',
    p_pattern     => 'search',
    p_method      => 'POST',
    p_source_type => ORDS.SOURCE_TYPE_PLSQL,
    p_source      => q'[
DECLARE
  l_workspace_id VARCHAR2(64) := NVL(:workspaceId, 'WS1');
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', FALSE);
  HTP.P('Cache-Control: no-store');
  OWA_UTIL.HTTP_HEADER_CLOSE;

  HTP.P(sc_context_api.search_json(
    p_workspace_id => l_workspace_id,
    p_body         => :body
  ));
END;]'
  );

  ORDS.DEFINE_TEMPLATE(
    p_module_name => 'shared_context',
    p_pattern     => 'cases/:caseId/evidence'
  );

  ORDS.DEFINE_HANDLER(
    p_module_name => 'shared_context',
    p_pattern     => 'cases/:caseId/evidence',
    p_method      => 'GET',
    p_source_type => ORDS.SOURCE_TYPE_PLSQL,
    p_source      => q'[
DECLARE
  l_workspace_id VARCHAR2(64) := NVL(:workspaceId, 'WS1');
  l_limit        NUMBER := COALESCE(TO_NUMBER(:limit), 10);
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', FALSE);
  HTP.P('Cache-Control: no-store');
  OWA_UTIL.HTTP_HEADER_CLOSE;

  HTP.P(sc_context_api.evidence_json(
    p_workspace_id => l_workspace_id,
    p_case_id      => :caseId,
    p_query        => :query,
    p_limit        => l_limit,
    p_status       => :status,
    p_region       => :region,
    p_study_id     => :studyId,
    p_from_ts      => CASE WHEN :fromTs IS NULL THEN NULL ELSE CAST(TO_TIMESTAMP_TZ(:fromTs, 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS TIMESTAMP) END,
    p_to_ts        => CASE WHEN :toTs   IS NULL THEN NULL ELSE CAST(TO_TIMESTAMP_TZ(:toTs,   'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS TIMESTAMP) END
  ));
END;]'
  );

  ORDS.DEFINE_TEMPLATE(
    p_module_name => 'shared_context',
    p_pattern     => 'cases/:caseId/audit'
  );

  ORDS.DEFINE_HANDLER(
    p_module_name => 'shared_context',
    p_pattern     => 'cases/:caseId/audit',
    p_method      => 'GET',
    p_source_type => ORDS.SOURCE_TYPE_PLSQL,
    p_source      => q'[
DECLARE
  l_workspace_id VARCHAR2(64) := NVL(:workspaceId, 'WS1');
  l_limit        NUMBER := COALESCE(TO_NUMBER(:limit), 20);
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', FALSE);
  HTP.P('Cache-Control: no-store');
  OWA_UTIL.HTTP_HEADER_CLOSE;

  HTP.P(sc_context_api.audit_json(
    p_workspace_id => l_workspace_id,
    p_case_id      => :caseId,
    p_limit        => l_limit
  ));
END;]'
  );

  ORDS.DEFINE_TEMPLATE(
    p_module_name => 'shared_context',
    p_pattern     => 'health'
  );

  ORDS.DEFINE_HANDLER(
    p_module_name => 'shared_context',
    p_pattern     => 'health',
    p_method      => 'GET',
    p_source_type => ORDS.SOURCE_TYPE_PLSQL,
    p_source      => q'[
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', FALSE);
  OWA_UTIL.HTTP_HEADER_CLOSE;
  HTP.P(sc_context_api.health_json);
END;]'
  );

  COMMIT;
END;
/

EXIT;
