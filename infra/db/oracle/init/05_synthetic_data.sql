-- 05_synthetic_data.sql
-- Utilities for Synthetic Data Generation

ALTER SESSION SET CURRENT_SCHEMA = loan_user;

-- Create types for scenario output
CREATE OR REPLACE TYPE scenario_rec AS OBJECT (
    scenario_name VARCHAR2(100),
    income_adj_pct NUMBER,     -- Percentage adjustment (e.g., -0.15 for -15%)
    credit_score_adj NUMBER,   -- Absolute adjustment (e.g., -40)
    fraud_risk_adj NUMBER,     -- Absolute adjustment
    dti_adj_pct NUMBER         -- DTI adjustment percentage
);
/

CREATE OR REPLACE TYPE scenario_tab AS TABLE OF scenario_rec;
/

-- Package for generation
CREATE OR REPLACE PACKAGE synthetic_util AS
    -- Pipelined function to return scenarios
    FUNCTION generate_scenarios(
        p_workspace_id IN VARCHAR2,
        p_application_id IN VARCHAR2, 
        p_seed IN VARCHAR2
    ) RETURN scenario_tab PIPELINED;
END synthetic_util;
/

CREATE OR REPLACE PACKAGE BODY synthetic_util AS
    FUNCTION generate_scenarios(
        p_workspace_id IN VARCHAR2,
        p_application_id IN VARCHAR2, 
        p_seed IN VARCHAR2
    ) RETURN scenario_tab PIPELINED IS
    BEGIN
        -- This is a stub implementation.
        -- In a real setup with Select AI, this would leverage generative AI
        -- to produce varied scenarios based on the seed.
        
        -- Example of what it might return if implemented in PL/SQL:
        -- PIPE ROW(scenario_rec('income_down_15pct', -0.15, 0, 0, 0));
        -- PIPE ROW(scenario_rec('credit_score_down_40', 0, -40, 0, 0));
        
        -- Returning nothing signals the application to use its internal fallback.
        RETURN;
    END;
END synthetic_util;
/
