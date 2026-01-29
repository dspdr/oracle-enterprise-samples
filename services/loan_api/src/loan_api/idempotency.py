import hashlib
import json
import logging
from typing import Any, Dict, Optional, Union
import oracledb
from fastapi import HTTPException, status

logger = logging.getLogger("loan_api.idempotency")

class IdempotencyManager:
    def __init__(self, conn):
        self.conn = conn

    def _hash_payload(self, body: Dict, request_mode: str, execution_mode: str) -> str:
        # Canonicalize body: Sort keys to ensure consistent hash
        try:
            canonical = json.dumps(body, sort_keys=True)
        except TypeError:
             # Fallback for non-serializable (should not happen with Pydantic models dict)
             canonical = str(body)
             
        raw = f"{canonical}|{request_mode}|{execution_mode}"
        return hashlib.sha256(raw.encode('utf-8')).hexdigest()

    def check_and_lock(self, key: str, route: str, body: Dict, request_mode: str, execution_mode: str) -> Optional[Dict]:
        """
        Checks idempotency.
        Returns cached response (Dict) if exists.
        Returns None if we should proceed (locks the key).
        Raises HTTPException if conflict.
        """
        phash = self._hash_payload(body, request_mode, execution_mode)
        
        cursor = self.conn.cursor()
        try:
            # Enforce key uniqueness across routes
            cursor.execute(
                """
                SELECT route_path, payload_hash, status, response_code, response_body
                FROM idempotency_keys
                WHERE idempotency_key = :1
                """,
                [key]
            )
            any_row = cursor.fetchone()
            if any_row:
                any_route, any_hash, any_status, any_code, any_body = any_row
                if any_route != route or any_hash != phash:
                    logger.warning(f"Idempotency conflict: Key {key} reused across routes or with different payload.")
                    raise HTTPException(
                        status_code=status.HTTP_409_CONFLICT,
                        detail=f"Idempotency key already used for route {any_route}"
                    )

            cursor.execute(
                """
                SELECT payload_hash, status, response_code, response_body 
                FROM idempotency_keys 
                WHERE idempotency_key = :1 AND route_path = :2
                """,
                [key, route]
            )
            row = cursor.fetchone()
            
            if row:
                stored_hash, stored_status, stored_code, stored_body_clob = row
                
                # Enforce payload match
                if stored_hash != phash:
                    logger.warning(f"Idempotency conflict: Key {key} reused with different payload hash.")
                    raise HTTPException(
                        status_code=status.HTTP_409_CONFLICT,
                        detail="Idempotency key reused with different payload or mode"
                    )
                
                if stored_status == 'COMPLETED':
                    # Return cached response
                    if stored_body_clob:
                        return json.loads(stored_body_clob.read())
                    return {}
                elif stored_status == 'IN_PROGRESS':
                    # Concurrent request
                    raise HTTPException(
                        status_code=status.HTTP_409_CONFLICT,
                        detail="Request is currently in progress"
                    )
                # If FAILED or other, we treat as retryable and update to IN_PROGRESS below
            
            # Lock the key
            if row:
                cursor.execute(
                    "UPDATE idempotency_keys SET status = 'IN_PROGRESS', updated_at = CURRENT_TIMESTAMP WHERE idempotency_key = :1 AND route_path = :2",
                    [key, route]
                )
            else:
                cursor.execute(
                    """
                    INSERT INTO idempotency_keys (idempotency_key, route_path, payload_hash, request_mode, execution_mode, status)
                    VALUES (:1, :2, :3, :4, :5, 'IN_PROGRESS')
                    """,
                    [key, route, phash, request_mode, execution_mode]
                )
            
            self.conn.commit()
            return None # Proceed with execution
            
        except oracledb.IntegrityError:
            self.conn.rollback()
            raise HTTPException(status_code=409, detail="Concurrent request detected")
        except HTTPException:
            self.conn.rollback()
            raise
        except Exception as e:
            logger.error(f"Idempotency check failed: {e}")
            self.conn.rollback()
            raise HTTPException(status_code=500, detail="Internal idempotency check error")
        finally:
            cursor.close()

    def complete(self, key: str, route: str, response_body: Any, status_code: int = 200):
        """
        Marks the request as completed and stores the response.
        """
        cursor = self.conn.cursor()
        try:
            body_json = json.dumps(response_body)
            cursor.execute(
                """
                UPDATE idempotency_keys 
                SET status = 'COMPLETED', 
                    response_code = :1, 
                    response_body = :2, 
                    updated_at = CURRENT_TIMESTAMP
                WHERE idempotency_key = :3 AND route_path = :4
                """,
                [status_code, body_json, key, route]
            )
            self.conn.commit()
        except Exception as e:
            logger.error(f"Failed to complete idempotency for {key}: {e}")
            self.conn.rollback()
        finally:
            cursor.close()
