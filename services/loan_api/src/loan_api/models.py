from pydantic import BaseModel, Field
from typing import Optional, Dict, Any, List

class ApplicationCreate(BaseModel):
    applicant_id: str
    applicant_name: str
    amount: float
    income: float
    debt: float
    email: Optional[str] = None

class ApplicationResponse(BaseModel):
    id: str
    status: str
    applicant_data: Dict[str, Any]
    decision_data: Optional[Dict[str, Any]] = None
    created_at: str

class KYCResult(BaseModel):
    status: str = Field(..., description="PASS or FAIL")

class FraudResult(BaseModel):
    risk_score: int = Field(..., ge=0, le=100)

class CreditScore(BaseModel):
    score: int = Field(..., ge=300, le=850)

class DecisionResponse(BaseModel):
    run_id: str
    decision: str
    reason_codes: List[str]
    pricing: Optional[Dict[str, Any]] = None

class BookingCreate(BaseModel):
    application_id: str
    activation_date: Optional[str] = None
