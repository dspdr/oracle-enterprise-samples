-- 04_ai_setup.sql
-- Setup for DBMS_CLOUD_AI (Template)

-- This script is a placeholder/template.
-- In a real environment, you would configure the credential and profile here.
-- Uncomment and fill in details to enable AI capabilities.

/*
BEGIN
  -- Create Credential (replace with real API keys)
  DBMS_CLOUD.CREATE_CREDENTIAL(
    credential_name => 'OPENAI_CRED',
    username => 'OPENAI', -- specific for some providers
    password => 'sk-...'
  );

  -- Create AI Profile
  DBMS_CLOUD_AI.CREATE_PROFILE(
    profile_name => 'LOAN_AI_PROFILE',
    attributes => '{"provider": "openai", "credential_name": "OPENAI_CRED", "object_list": [{"owner": "LOAN_USER", "name": "APPLICATIONS"}]}'
  );
END;
/
*/
