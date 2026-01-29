import yaml
import logging
from typing import Dict, Any, Callable, Union

logger = logging.getLogger("agent_runner")

class AgentRunner:
    def __init__(self, spec_path: str, tools_path: str, agent_impl: Any):
        self.spec = self._load_yaml(spec_path)
        self.tools_def = self._load_yaml(tools_path)
        self.agent_impl = agent_impl
        self._validate_spec()

    def _load_yaml(self, path: str) -> Dict:
        try:
            with open(path, 'r') as f:
                return yaml.safe_load(f)
        except Exception as e:
            logger.error(f"Failed to load spec from {path}: {e}")
            raise

    def _validate_spec(self):
        # Minimal validation of the Agent Spec
        if not self.spec.get('name'):
            raise ValueError("Agent Spec missing 'name'")
        if 'inputs' not in self.spec:
            raise ValueError("Agent Spec missing 'inputs'")
        if 'outputs' not in self.spec:
            raise ValueError("Agent Spec missing 'outputs'")
        logger.info(f"Loaded Agent Spec: {self.spec['name']}")

    def run(self, inputs: Dict[str, Any], tools_map: Dict[str, Callable]) -> Dict[str, Any]:
        logger.info("AgentRunner: Starting execution")
        
        # 1. Validate Inputs
        spec_inputs = self.spec.get('inputs', {})
        for key in spec_inputs:
            if key not in inputs:
                # We log warning but don't strictly fail if optional? 
                # Spec doesn't define optional yet. Assume required.
                logger.warning(f"Missing expected input: {key}")

        # 2. Validate Tools Availability
        spec_tools = self.spec.get('tools', [])
        for tool_name in spec_tools:
            if tool_name not in tools_map:
                raise ValueError(f"Tool '{tool_name}' defined in spec but not provided in tools_map")

        # 3. Invoke Agent Implementation
        # Supports class with run() or callable
        result = {}
        try:
            if hasattr(self.agent_impl, 'run'):
                result = self.agent_impl.run(inputs, tools_map)
            elif callable(self.agent_impl):
                result = self.agent_impl(inputs, tools_map)
            else:
                raise ValueError("agent_impl is not callable or missing run() method")
        except Exception as e:
            logger.error(f"Agent execution failed: {e}")
            raise e

        # 4. Validate Outputs (Minimal)
        spec_outputs = self.spec.get('outputs', {})
        for key in spec_outputs:
            if key not in result:
                logger.warning(f"Agent did not return expected output: {key}")

        logger.info("AgentRunner: Execution completed")
        return result
