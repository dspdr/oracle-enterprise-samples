from fastapi import FastAPI, Header, HTTPException, Depends, Request, Body, Path
from contextlib import asynccontextmanager
from typing import Any, Dict, List, Optional
import uuid
import json
import logging
import datetime

from .db import init_db, get_connection, get_write_connection, get_read_connection, close_db, release_connection
from .models import ApplicationCreate, ApplicationResponse, DecisionResponse, KYCResult, FraudResult, CreditScore, BookingCreate, DecisionPlan, DecisionPlanRequest
from .idempotency import IdempotencyManager
from .planning import create_plan, calculate_inputs_hash
from .decision import execute_decision_workflow

from workflows.wayflow import WorkflowContext

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("loan_api")

@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    yield
    close_db()

app = FastAPI(lifespan=lifespan, title="Loan Origination API")

# Dependencies
def get_db_conn():
    # Default to write for backward compat
    conn = get_write_connection()
    try:
        yield conn
    finally:
        release_connection(conn)

def get_write_db_conn():
    conn = get_write_connection()
    try:
        yield conn
    finally:
        release_connection(conn)

def get_read_db_conn():
    conn = get_read_connection()
    try:
        yield conn
    finally:
        release_connection(conn)

def get_idempotency_key(idempotency_key: str = Header(..., alias="Idempotency-Key")):
    return idempotency_key

# Helpers
def derive_id(key: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_OID, key))

def log_audit(conn, app_id: str, action: str, details: Dict):
    cursor = conn.cursor()
    try:
        cursor.execute(
            "INSERT INTO audit_logs (application_id, action, details) VALUES (:1, :2, :3)",
            [app_id, action, json.dumps(details)]
        )
    except Exception as e:
        logger.error(f"Failed to write audit log: {e}")
        raise e
    finally:
        cursor.close()

def fetch_application(conn, app_id: str) -> Dict:
    cursor = conn.cursor()
    cursor.execute("SELECT id, status, applicant_data, decision_data, created_at FROM applications WHERE id = :1", [app_id])
    row = cursor.fetchone()
    cursor.close()
    if not row:
        raise HTTPException(status_code=404, detail="Application not found")
    
    app_data = json.loads(row[2].read()) if row[2] else {}
    dec_data = json.loads(row[3].read()) if row[3] else {}
    
    return {
        "id": row[0],
        "status": row[1],
        "applicant_data": app_data,
        "decision_data": dec_data,
        "created_at": str(row[4])
    }

def update_app_data(conn, app_id: str, field: str, value: Dict):
    current = fetch_application(conn, app_id)
    dec_data = current["decision_data"]
    dec_data[field] = value
    
    cursor = conn.cursor()
    cursor.execute(
        "UPDATE applications SET decision_data = :1, updated_at = CURRENT_TIMESTAMP WHERE id = :2",
        [json.dumps(dec_data), app_id]
    )
    conn.commit()
    cursor.close()
    return dec_data

def update_app_status(conn, app_id: str, status: str):
    cursor = conn.cursor()
    cursor.execute(
        "UPDATE applications SET status = :1, updated_at = CURRENT_TIMESTAMP WHERE id = :2",
        [status, app_id]
    )
    conn.commit()
    cursor.close()

def mark_plan_executed(conn, plan_id: str):
    cursor = conn.cursor()
    cursor.execute(
        "UPDATE decision_plans SET status = 'EXECUTED', executed_at = CURRENT_TIMESTAMP WHERE plan_id = :1",
        [plan_id]
    )
    conn.commit()
    cursor.close()

# Routes

@app.post("/applications", response_model=ApplicationResponse)
def create_application(
    app_data: ApplicationCreate,
    request: Request,
    idempotency_key: str = Depends(get_idempotency_key),
    conn = Depends(get_write_db_conn)
):
    idem = IdempotencyManager(conn)
    route = request.url.path
    
    cached = idem.check_and_lock(idempotency_key, route, app_data.model_dump(), "POST", "EXECUTE")
    if cached: return cached

    try:
        app_id = derive_id(idempotency_key)
        
        cursor = conn.cursor()
        cursor.execute(
            "INSERT INTO applications (id, status, applicant_data, decision_data) VALUES (:1, 'NEW', :2, '{}')",
            [app_id, json.dumps(app_data.model_dump())]
        )
        cursor.close()
        
        log_audit(conn, app_id, "APPLICATION_CREATED", {"source": "API"})
        conn.commit()
        
        response = {
            "id": app_id,
            "status": "NEW",
            "applicant_data": app_data.model_dump(),
            "decision_data": {},
            "created_at": str(datetime.datetime.now())
        }
        
        idem.complete(idempotency_key, route, response)
        return response
    except Exception as e:
        logger.error(f"Error creating app: {e}")
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/applications/{id}", response_model=ApplicationResponse)
def get_application(id: str, conn = Depends(get_read_db_conn)):
    return fetch_application(conn, id)

@app.post("/applications/{id}/kyc")
def add_kyc_result(
    id: str,
    result: KYCResult,
    request: Request,
    idempotency_key: str = Depends(get_idempotency_key),
    conn = Depends(get_write_db_conn)
):
    idem = IdempotencyManager(conn)
    route = request.url.path
    cached = idem.check_and_lock(idempotency_key, route, result.model_dump(), "POST", "EXECUTE")
    if cached: return cached
    
    try:
        update_app_data(conn, id, "kyc_result", result.model_dump())
        log_audit(conn, id, "KYC_UPDATED", result.model_dump())
        conn.commit() 
        
        resp = {"status": "Updated", "kyc_result": result.model_dump()}
        idem.complete(idempotency_key, route, resp)
        return resp
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/applications/{id}/fraud")
def add_fraud_result(
    id: str,
    result: FraudResult,
    request: Request,
    idempotency_key: str = Depends(get_idempotency_key),
    conn = Depends(get_write_db_conn)
):
    idem = IdempotencyManager(conn)
    route = request.url.path
    cached = idem.check_and_lock(idempotency_key, route, result.model_dump(), "POST", "EXECUTE")
    if cached: return cached
    
    try:
        update_app_data(conn, id, "fraud_result", result.model_dump())
        log_audit(conn, id, "FRAUD_CHECK_UPDATED", result.model_dump())
        conn.commit()
        
        resp = {"status": "Updated", "fraud_result": result.model_dump()}
        idem.complete(idempotency_key, route, resp)
        return resp
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/applications/{id}/credit-score")
def add_credit_score(
    id: str,
    result: CreditScore,
    request: Request,
    idempotency_key: str = Depends(get_idempotency_key),
    conn = Depends(get_write_db_conn)
):
    idem = IdempotencyManager(conn)
    route = request.url.path
    cached = idem.check_and_lock(idempotency_key, route, result.model_dump(), "POST", "EXECUTE")
    if cached: return cached
    
    try:
        update_app_data(conn, id, "credit_score", result.score)
        log_audit(conn, id, "CREDIT_SCORE_UPDATED", {"score": result.score})
        conn.commit()
        
        resp = {"status": "Updated", "credit_score": result.score}
        idem.complete(idempotency_key, route, resp)
        return resp
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/applications/{id}/decision/plan", response_model=DecisionPlan)
def decision_plan_endpoint(
    id: str,
    plan_request: DecisionPlanRequest,
    request: Request,
    idempotency_key: str = Depends(get_idempotency_key),
    conn = Depends(get_write_db_conn)
):
    idem = IdempotencyManager(conn)
    route = request.url.path
    
    # We cache based on request payload (options)
    cached = idem.check_and_lock(idempotency_key, route, plan_request.model_dump(), "POST", "PLAN")
    if cached: return cached
    
    try:
        app_data = fetch_application(conn, id)
        plan = create_plan(conn, id, app_data, plan_request, idempotency_key)
        
        idem.complete(idempotency_key, route, plan.model_dump())
        return plan
    except Exception as e:
        logger.error(f"Plan creation failed: {e}")
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/applications/{id}/decision/execute")
def decision_execute_endpoint(
    id: str,
    decision_plan: DecisionPlan,
    request: Request,
    idempotency_key: str = Depends(get_idempotency_key),
    conn = Depends(get_write_db_conn)
):
    idem = IdempotencyManager(conn)
    route = request.url.path
    
    # Check idempotency first
    # Payload for lock is the decision_plan (might be large, but ensures we execute specific plan)
    cached = idem.check_and_lock(idempotency_key, route, decision_plan.model_dump(), "POST", "EXECUTE")
    if cached: return cached
    
    try:
        # Validate Inputs Hash
        app_data = fetch_application(conn, id)
        applicant = app_data["applicant_data"]
        decision_data = app_data["decision_data"]
        kyc = decision_data.get("kyc_result", {})
        fraud = decision_data.get("fraud_result", {})
        credit = decision_data.get("credit_score", 0)
        
        # Reconstruct options from plan to verify hash
        # Assuming plan request used defaults if not visible, or derived from plan structure
        options = {
            "workspace_id": decision_plan.workspace_id,
            "scenarios_count": len(decision_plan.scenario_results)
        }
        
        current_hash = calculate_inputs_hash(
            {"id": id, **applicant}, 
            kyc, 
            fraud, 
            credit, 
            options
        )
        
        if current_hash != decision_plan.inputs_hash:
            raise HTTPException(status_code=409, detail="Application state has changed since plan was created. Inputs hash mismatch.")
            
        # Execute Decision
        # We reuse the deterministic logic. It should yield the same result as recommended_decision if state is same.
        inputs = {
            "application": {"id": id, **applicant},
            "kyc_result": kyc,
            "fraud_result": fraud,
            "credit_score": credit,
            "db_conn": conn
        }
        
        result = execute_decision_workflow(inputs, "EXECUTE", derive_id(idempotency_key))
        
        # Verify result matches plan? Not strictly required but good practice.
        if result["decision"] != decision_plan.recommended_decision:
             logger.warning(f"Execution result {result['decision']} differs from plan {decision_plan.recommended_decision}")
        
        # Persist
        log_audit(conn, id, "DECISION_EXECUTED", {"run_id": result["run_id"], "decision": result["decision"], "plan_id": decision_plan.plan_id})
        
        # Mark Plan Executed
        mark_plan_executed(conn, decision_plan.plan_id)
        
        conn.commit()
        
        response = {
            "run_id": result["run_id"],
            "decision": result["decision"],
            "reason_codes": result["reason_codes"],
            "pricing": result["pricing"],
            "mode": "EXECUTE"
        }
        
        idem.complete(idempotency_key, route, response)
        return response
        
    except HTTPException as he:
        conn.rollback()
        raise he
    except Exception as e:
        logger.error(f"Execution failed: {e}")
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/applications/{id}/decision/dry-run")
def decision_dry_run(
    id: str,
    request: Request,
    idempotency_key: str = Depends(get_idempotency_key),
    conn = Depends(get_write_db_conn)
):
    # POST endpoints use primary (write) connection per requirements,
    # ensuring IdempotencyManager can write locks even if business logic is read-only.
    return run_decision_legacy(id, request, idempotency_key, conn, mode="DRY_RUN")

def run_decision_legacy(app_id: str, request: Request, idempotency_key: str, conn, mode: str):
    # This is the old helper, now wrapping new logic for backward compat
    idem = IdempotencyManager(conn)
    route = request.url.path
    
    cached = idem.check_and_lock(idempotency_key, route, {}, "POST", mode)
    if cached: return cached
    
    try:
        app_data = fetch_application(conn, app_id)
        applicant = app_data["applicant_data"]
        decision_data = app_data["decision_data"]
        
        inputs = {
            "application": {"id": app_id, **applicant},
            "kyc_result": decision_data.get("kyc_result", {}),
            "fraud_result": decision_data.get("fraud_result", {}),
            "credit_score": decision_data.get("credit_score", 0),
            "db_conn": conn
        }
        
        result = execute_decision_workflow(inputs, mode, derive_id(idempotency_key))
        
        response = {
            "run_id": result["run_id"],
            "decision": result["decision"],
            "reason_codes": result["reason_codes"],
            "pricing": result["pricing"],
            "mode": mode
        }
        
        # Note: Execute persistence moved to endpoint logic, but dry run legacy might need it?
        # No, dry run doesn't persist.
        
        idem.complete(idempotency_key, route, response)
        return response
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/offers/{id}/accept")
def accept_offer(
    id: str,
    request: Request,
    idempotency_key: str = Depends(get_idempotency_key),
    conn = Depends(get_write_db_conn)
):
    idem = IdempotencyManager(conn)
    route = request.url.path
    # Empty body
    cached = idem.check_and_lock(idempotency_key, route, {}, "POST", "EXECUTE")
    if cached: return cached
    
    try:
        # Verify app exists
        app_data = fetch_application(conn, id)
        
        update_app_status(conn, id, "OFFER_ACCEPTED")
        log_audit(conn, id, "OFFER_ACCEPTED", {"timestamp": str(datetime.datetime.now())})
        conn.commit()
        
        resp = {"status": "OFFER_ACCEPTED", "application_id": id}
        idem.complete(idempotency_key, route, resp)
        return resp
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/bookings")
def create_booking(
    booking_data: BookingCreate,
    request: Request,
    idempotency_key: str = Depends(get_idempotency_key),
    conn = Depends(get_write_db_conn)
):
    idem = IdempotencyManager(conn)
    route = request.url.path
    
    cached = idem.check_and_lock(idempotency_key, route, booking_data.model_dump(), "POST", "EXECUTE")
    if cached: return cached
    
    try:
        app_id = booking_data.application_id
        # Verify app exists
        app_data = fetch_application(conn, app_id)
        
        # Update status
        update_app_status(conn, app_id, "BOOKED")
        
        # Create Booking Record? (Audit log is sufficient for this sample)
        booking_id = derive_id(idempotency_key)
        
        log_audit(conn, app_id, "BOOKING_CREATED", {"booking_id": booking_id, "activation_date": booking_data.activation_date})
        conn.commit()
        
        resp = {"booking_id": booking_id, "status": "BOOKED", "application_id": app_id}
        idem.complete(idempotency_key, route, resp)
        return resp
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/applications/{id}/audit")
def get_audit(id: str, conn = Depends(get_read_db_conn)):
    cursor = conn.cursor()
    cursor.execute("SELECT id, action, details, created_at FROM audit_logs WHERE application_id = :1 ORDER BY created_at", [id])
    rows = cursor.fetchall()
    cursor.close()
    
    return [
        {
            "id": r[0], 
            "action": r[1], 
            "details": json.loads(r[2].read()) if r[2] else {}, 
            "timestamp": str(r[3])
        }
        for r in rows
    ]
