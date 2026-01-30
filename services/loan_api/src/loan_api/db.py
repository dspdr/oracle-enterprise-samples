import os
import oracledb
import logging

logger = logging.getLogger("loan_api.db")

_write_pool = None
_read_pool = None

def init_db():
    global _write_pool, _read_pool
    if _write_pool is not None:
        return

    # --- Primary / Write Pool ---
    user = os.environ.get("DB_USER", "loan_user")
    password = os.environ.get("DB_PASSWORD", "Welcome12345!")
    dsn = os.environ.get("DB_DSN", "localhost:1521/FREEPDB1")
    
    # Wallet / TLS support for Primary
    protocol = os.environ.get("DB_PROTOCOL")
    host = os.environ.get("DB_HOST")
    port = os.environ.get("DB_PORT")
    service_name = os.environ.get("DB_SERVICE")
    wallet_location = os.environ.get("DB_WALLET_LOCATION") or os.environ.get("TNS_ADMIN")
    wallet_password = os.environ.get("WALLET_PASSWORD")
    
    logger.info(f"Initializing Write Pool...")
    try:
        if protocol and host and port and service_name:
             _write_pool = oracledb.create_pool(
                user=user,
                password=password,
                protocol=protocol,
                host=host,
                port=int(port),
                service_name=service_name,
                wallet_location=wallet_location,
                wallet_password=wallet_password,
                ssl_server_dn_match=False,
                min=1,
                max=10,
                increment=1,
                disable_oob=True
            )
        else:
            _write_pool = oracledb.create_pool(
                user=user,
                password=password,
                dsn=dsn,
                min=1,
                max=10,
                increment=1,
                disable_oob=True
            )
    except Exception as e:
        logger.error(f"Failed to create Write Pool: {e}")
        raise

    # --- True Cache / Read Pool ---
    true_cache_enabled = os.environ.get("TRUE_CACHE_ENABLED", "false").lower() == "true"
    
    if true_cache_enabled:
        tc_dsn = os.environ.get("TRUE_CACHE_DSN")
        if not tc_dsn:
            raise ValueError("TRUE_CACHE_ENABLED is True but TRUE_CACHE_DSN is not set.")
        
        logger.info(f"Initializing Read Pool (True Cache) at {tc_dsn}...")
        try:
             # Assuming True Cache uses same user/pass/wallet as primary or simple DSN
             # We reuse the user/password from primary.
             _read_pool = oracledb.create_pool(
                user=user,
                password=password,
                dsn=tc_dsn,
                min=1,
                max=10,
                increment=1,
                disable_oob=True
            )
        except Exception as e:
            logger.error(f"Failed to create Read Pool: {e}")
            raise
    else:
        logger.info("True Cache disabled, Read Pool aliases Write Pool.")
        _read_pool = _write_pool # Alias

def get_connection():
    # Backward compatibility, defaults to write for safety unless explicit
    return get_write_connection()

def get_write_connection():
    if _write_pool is None:
        init_db()
    return _write_pool.acquire()

def get_read_connection():
    if _read_pool is None:
        init_db()
    return _read_pool.acquire()

def close_db():
    global _write_pool, _read_pool
    if _read_pool and _read_pool != _write_pool:
        _read_pool.close()
    if _write_pool:
        _write_pool.close()
    _write_pool = None
    _read_pool = None

def release_connection(conn):
    if not conn:
        return
    try:
        conn.close()
    except Exception as e:
        logger.warning(f"Failed to release connection: {e}")
