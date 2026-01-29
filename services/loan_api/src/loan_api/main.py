from fastapi import FastAPI, Header, HTTPException, Depends, Request, Body, Path
from contextlib import asynccontextmanager
from typing import Any, Dict, List, Optional
import uuid
import json
import logging
import datetime

from .db import init_db, get_connection, close_db, release_connection
from .models import ApplicationCreate, ApplicationResponse, DecisionResponse, KYCResult, FraudResult, CreditScore, BookingCreate
from .idempotency import IdempotencyManager

from workflows.loan_origination_wayflow import create_loan_workflow
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
    conn = get_connection()
    try:
        yield conn
    finally:
        release_connection(conn)

def get_idempotency_key(idempotency_key: str = Header(..., alias="Idempotency-Key")):
    return idempotency_key

# Helpers
def derive_id(key: str) -> str:
    # Deterministic ID based on idempotency key
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
        # We don't raise here to avoid blocking main flow if audit fails?
        # "Full auditability" -> We should probably raise.
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
    
    # Parse CLOBs
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

# Routes

@app.post("/applications", response_model=ApplicationResponse)
def create_application(
    app_data: ApplicationCreate,
    request: Request,
    idempotency_key: str = Depends(get_idempotency_key),
    conn = Depends(get_db_conn)
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
def get_application(id: str, conn = Depends(get_db_conn)):
    return fetch_application(conn, id)

@app.post("/applications/{id}/kyc")
def add_kyc_result(
    id: str,
    result: KYCResult,
    request: Request,
    idempotency_key: str = Depends(get_idempotency_key),
    conn = Depends(get_db_conn)
):
    idem = IdempotencyManager(conn)
    route = request.url.path
    cached = idem.check_and_lock(idempotency_key, route, result.model_dump(), "POST", "EXECUTE")
    if cached: return cached
    
    try:
        update_app_data(conn, id, "kyc_result", result.model_dump())
        log_audit(conn, id, "KYC_UPDATED", result.model_dump())
        conn.commit() # Ensure log committed
        
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
    conn = Depends(get_db_conn)
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
    conn = Depends(get_db_conn)
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

@app.post("/applications/{id}/decision/dry-run")
def decision_dry_run(
    id: str,
    request: Request,
    idempotency_key: str = Depends(get_idempotency_key),
    conn = Depends(get_db_conn)
):
    return run_decision(id, request, idempotency_key, conn, mode="DRY_RUN")

@app.post("/applications/{id}/decision/execute")
def decision_execute(
    id: str,
    request: Request,
    idempotency_key: str = Depends(get_idempotency_key),
    conn = Depends(get_db_conn)
):
    return run_decision(id, request, idempotency_key, conn, mode="EXECUTE")

def run_decision(app_id: str, request: Request, idempotency_key: str, conn, mode: str):
    idem = IdempotencyManager(conn)
    route = request.url.path
    body_dict = {} 
    
    cached = idem.check_and_lock(idempotency_key, route, body_dict, "POST", mode)
    if cached: return cached
    
    try:
        # Fetch Data
        app_data = fetch_application(conn, app_id)
        applicant = app_data["applicant_data"]
        decision_data = app_data["decision_data"]
        
        # Construct Inputs
        inputs = {
            "application": {"id": app_id, **applicant},
            "kyc_result": decision_data.get("kyc_result", {}),
            "fraud_result": decision_data.get("fraud_result", {}),
            "credit_score": decision_data.get("credit_score", 0)
        }
        
        # Prepare Workflow
        wf = create_loan_workflow()
        
        # Run ID
        run_id = f"run_{derive_id(idempotency_key)}"
        
        ctx = WorkflowContext(
            run_id=run_id,
            mode=mode,
            payload={**inputs, "db_conn": conn},
            state={}
        )
        
        result = wf.run(ctx)
        
        agent_res = result["results"].get("agent_decision", {})
        
        response = {
            "run_id": run_id,
            "decision": agent_res.get("decision", "UNKNOWN"),
            "reason_codes": agent_res.get("reason_codes", []),
            "pricing": agent_res.get("pricing"),
            "mode": mode
        }
        
        if mode == "EXECUTE":
            log_audit(conn, app_id, "DECISION_EXECUTED", {"run_id": run_id, "decision": response["decision"]})
            conn.commit()
        
        idem.complete(idempotency_key, route, response)
        return response
        
    except Exception as e:
        logger.error(f"Decision failed: {e}")
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/offers/{id}/accept")
def accept_offer(
    id: str,
    request: Request,
    idempotency_key: str = Depends(get_idempotency_key),
    conn = Depends(get_db_conn)
):
    idem = IdempotencyManager(conn)
    route = request.url.path
    # Empty body
    cached = idem.check_and_lock(idempotency_key, route, {}, "POST", "EXECUTE")
    if cached: return cached
    
    try:
        # Verify app exists
        app_data = fetch_application(conn, id)
        # Verify status? Maybe only allow if status is 'DECISION_MADE' or similar?
        # For sample, we assume if we have a decision, we can accept.
        
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
    conn = Depends(get_db_conn)
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
def get_audit(id: str, conn = Depends(get_db_conn)):
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
