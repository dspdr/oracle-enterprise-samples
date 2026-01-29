import os
import logging
from typing import Any, Dict, List
from services.workflows.wayflow import Wayflow, WorkflowContext, Step
from services.decision_agent import AgentRunner, LoanDecisionAgent

# Define Tools (Mock or Real Logic)
def tool_get_application_snapshot(application_id: str):
    # In this design, the snapshot is passed in inputs, so this tool might just return it 
    # or be a placeholder if the agent used it to fetch.
    # The agent spec has 'get_application_snapshot'. 
    # If the agent calls it, we should provide it.
    pass

def tool_evaluate_policy(policy_name: str, data: Dict):
    # Simple mock policy evaluation
    return {"status": "PASS", "details": "Policy met"}

def tool_price_offer(credit_score: int, amount: float):
    # Deterministic pricing logic
    base_rate = 5.0
    if credit_score > 750:
        base_rate = 4.5
    elif credit_score < 650:
        base_rate = 6.0
    
    return {"rate": base_rate, "term": 36, "monthly_payment": amount * (1 + base_rate/100) / 36} # Simplified

# Steps

def step_initialize(ctx: WorkflowContext):
    # Validate inputs
    required = ["application", "kyc_result", "fraud_result", "credit_score"]
    for r in required:
        if r not in ctx.payload:
            raise ValueError(f"Missing input: {r}")
    return {"status": "Initialized"}

def step_decision_agent(ctx: WorkflowContext):
    # Setup Runner
    base_dir = os.path.dirname(os.path.dirname(os.path.dirname(__file__))) # services/
    spec_path = os.path.join(base_dir, "decision_agent/agent_spec/manifest.yaml")
    tools_path = os.path.join(base_dir, "decision_agent/agent_spec/tools.yaml")
    
    # Initialize Agent
    agent = LoanDecisionAgent()
    runner = AgentRunner(spec_path, tools_path, agent)
    
    # Prepare Inputs
    agent_inputs = {
        "application": ctx.payload["application"],
        "kyc_result": ctx.payload["kyc_result"],
        "fraud_result": ctx.payload["fraud_result"],
        "credit_score": ctx.payload["credit_score"]
    }
    
    # Prepare Tools
    tools_map = {
        "get_application_snapshot": lambda **kwargs: ctx.payload["application"],
        "evaluate_policy": tool_evaluate_policy,
        "price_offer": tool_price_offer
    }
    
    # Run Agent
    result = runner.run(agent_inputs, tools_map)
    
    # Store in state
    ctx.state["decision_result"] = result
    return result

def step_persist(ctx: WorkflowContext):
    if ctx.is_dry_run():
        return {"status": "Skipped (Dry Run)"}
    
    # Check if we have a DB callback or connection
    # For this sample, we assume the caller handles persistence based on the returned result?
    # OR we do it here.
    # "No database writes [in dry run]".
    # "System of Record... Oracle Database".
    # If the workflow is responsible for updating the Application status, we should do it here.
    
    db_conn = ctx.payload.get("db_conn")
    if not db_conn:
        # If no DB connection provided, maybe we return instruction to persist?
        # But requirements say "System of Record... Used for... decisions".
        # So we should write.
        return {"status": "No DB Connection provided"}
        
    decision = ctx.state["decision_result"]["decision"]
    app_id = ctx.payload["application"]["id"]
    
    # Update DB
    # We use raw sql or similar
    cursor = db_conn.cursor()
    cursor.execute(
        "UPDATE applications SET status = :1, decision_data = :2, updated_at = CURRENT_TIMESTAMP WHERE id = :3",
        [decision, str(ctx.state["decision_result"]), app_id]
    )
    # Commit handled by caller or here? 
    # Usually transaction management is outside.
    # We won't commit here to allow atomic transaction with idempotency.
    
    return {"status": "Persisted", "decision": decision}

# Workflow Construction

def create_loan_workflow() -> Wayflow:
    wf = Wayflow("LoanOrigination")
    wf.add_step("initialize", step_initialize)
    wf.add_step("agent_decision", step_decision_agent)
    wf.add_step("persist_result", step_persist)
    return wf
