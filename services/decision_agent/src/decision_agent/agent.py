from typing import Dict, Any, Callable

class LoanDecisionAgent:
    """
    A deterministic implementation of the Loan Decision Agent.
    """
    
    def run(self, inputs: Dict[str, Any], tools: Dict[str, Callable]) -> Dict[str, Any]:
        # Extract inputs
        app = inputs.get("application", {})
        kyc = inputs.get("kyc_result", {})
        fraud = inputs.get("fraud_result", {})
        credit_score = inputs.get("credit_score", 0)
        
        decision = "APPROVE"
        reason_codes = []
        pricing = {}
        
        # 1. Check KYC
        # Assume kyc_result has 'status': 'PASS' or 'FAIL'
        if kyc.get("status") != "PASS":
            decision = "REJECT"
            reason_codes.append("KYC_FAILURE")
            
        # 2. Check Fraud
        # Assume fraud_result has 'risk_score' (0-100), high is bad
        risk_score = fraud.get("risk_score", 0)
        if risk_score >= 80:
            decision = "REJECT"
            reason_codes.append("FRAUD_RISK_HIGH")
        elif risk_score >= 50:
            # Maybe flag for manual review? For now, let's say strict.
            pass

        # 3. Check Credit Score
        # Simple policy
        if credit_score < 600:
            decision = "REJECT"
            reason_codes.append("CREDIT_SCORE_LOW")
        elif credit_score < 650:
             # Marginal
             if decision == "APPROVE":
                 # Maybe stricter pricing
                 pass
        
        # 4. Pricing (Only if Approved)
        if decision == "APPROVE":
            # Use the 'price_offer' tool if available to encapsulate pricing logic
            if "price_offer" in tools:
                amount = app.get("amount", 10000)
                pricing = tools["price_offer"](credit_score=credit_score, amount=amount)
            else:
                # Fallback internal logic (should not happen if tools enforced)
                pricing = {"rate": 5.0, "term": 36}

        return {
            "decision": decision,
            "reason_codes": reason_codes,
            "pricing": pricing
        }
