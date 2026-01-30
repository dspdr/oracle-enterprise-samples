-- 03_plans.sql
-- Create table for Decision Plans

-- Switch to writable PDB if needed (handled by container usually, but good practice to be explicit if running manually)
-- However, in init scripts, we rely on the environment.

ALTER SESSION SET CURRENT_SCHEMA = loan_user;

CREATE TABLE decision_plans (
    plan_id VARCHAR2(50) PRIMARY KEY,
    workspace_id VARCHAR2(50) NOT NULL,
    application_id VARCHAR2(50) NOT NULL,
    idempotency_key VARCHAR2(100) NOT NULL,
    inputs_hash VARCHAR2(64) NOT NULL,
    plan_json CLOB,
    status VARCHAR2(20) DEFAULT 'CREATED', -- CREATED, EXECUTED, SUPERSEDED
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    executed_at TIMESTAMP
);

CREATE INDEX idx_plans_app_id ON decision_plans(application_id);
