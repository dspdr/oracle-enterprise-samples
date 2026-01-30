from workflows.loan_origination_wayflow import create_loan_workflow
from workflows.wayflow import WorkflowContext
import logging

logger = logging.getLogger("loan_api.decision")

def execute_decision_workflow(inputs: dict, mode: str, run_id_base: str):
    """
    Executes the Loan Origination Workflow.
    
    Args:
        inputs: Dictionary containing workflow inputs (application, kyc, fraud, credit, db_conn).
        mode: Execution mode ('EXECUTE', 'DRY_RUN', 'PLAN').
        run_id_base: Base string for the Run ID.
        
    Returns:
        Dictionary with decision results.
    """
    # Prepare Workflow
    wf = create_loan_workflow()
    
    # Run ID
    run_id = f"run_{run_id_base}"
    
    ctx = WorkflowContext(
        run_id=run_id,
        mode=mode,
        payload=inputs,
        state={}
    )
    
    try:
        result = wf.run(ctx)
        agent_res = result["results"].get("agent_decision", {})
        
        return {
            "run_id": run_id,
            "decision": agent_res.get("decision", "UNKNOWN"),
            "reason_codes": agent_res.get("reason_codes", []),
            "pricing": agent_res.get("pricing"),
            "mode": mode
        }
    except Exception as e:
        logger.error(f"Workflow execution failed: {e}")
        # In a real system, we might return an error state or re-raise
        raise e
