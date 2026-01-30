from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional
import logging

logger = logging.getLogger("wayflow")

@dataclass
class WorkflowContext:
    run_id: str
    mode: str = "EXECUTE"
    payload: Dict[str, Any] = field(default_factory=dict)
    state: Dict[str, Any] = field(default_factory=dict)
    
    def is_dry_run(self) -> bool:
        return self.mode in ["DRY_RUN", "PLAN"]

class Step:
    def __init__(self, name: str, func: Callable[['WorkflowContext'], Any]):
        self.name = name
        self.func = func

class Wayflow:
    def __init__(self, name: str):
        self.name = name
        self.steps: List[Step] = []
    
    def add_step(self, name: str, func: Callable[['WorkflowContext'], Any]):
        self.steps.append(Step(name, func))
        
    def run(self, context: WorkflowContext) -> Dict[str, Any]:
        logger.info(f"Starting workflow {self.name} run_id={context.run_id} mode={context.mode}")
        results = {}
        
        for step in self.steps:
            logger.debug(f"Executing step {step.name}")
            try:
                # Steps are executed sequentially.
                # Steps can read/write to context.state for passing data.
                output = step.func(context)
                results[step.name] = output
                
                # If a step returns explicit status indicating failure, we might stop?
                # For this minimal engine, we proceed unless exception.
                
            except Exception as e:
                logger.error(f"Step {step.name} failed: {e}")
                results[step.name] = {"error": str(e)}
                # We stop on error for safety
                raise e
        
        return {
            "workflow": self.name,
            "run_id": context.run_id,
            "status": "COMPLETED",
            "results": results,
            "final_state": context.state
        }
