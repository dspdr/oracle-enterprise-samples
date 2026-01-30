import os
import oracledb
import logging

logger = logging.getLogger("loan_api.db")

_pool = None

def init_db():
    global _pool
    if _pool is None:
        user = os.environ.get("DB_USER", "loan_user")
        password = os.environ.get("DB_PASSWORD", "Welcome12345!")
        dsn = os.environ.get("DB_DSN", "localhost:1521/FREEPDB1")
        protocol = os.environ.get("DB_PROTOCOL")
        host = os.environ.get("DB_HOST")
        port = os.environ.get("DB_PORT")
        service_name = os.environ.get("DB_SERVICE")
        wallet_location = os.environ.get("DB_WALLET_LOCATION") or os.environ.get("TNS_ADMIN")
        wallet_password = os.environ.get("WALLET_PASSWORD")
        
        target = dsn
        if protocol and host and port and service_name:
            target = f"{protocol}://{host}:{port}/{service_name}"
        logger.info(f"Initializing DB pool for {user}@{target}")
        try:
            # disable_oob avoids SSL EOF issues seen with ADB Free + wallets on some hosts
            if protocol and host and port and service_name:
                _pool = oracledb.create_pool(
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
                _pool = oracledb.create_pool(
                    user=user,
                    password=password,
                    dsn=dsn,
                    min=1,
                    max=10,
                    increment=1,
                    disable_oob=True
                )
        except Exception as e:
            logger.error(f"Failed to create DB pool: {e}")
            raise

def get_connection():
    if _pool is None:
        init_db()
    return _pool.acquire()

def close_db():
    global _pool
    if _pool:
        _pool.close()
        _pool = None

def release_connection(conn):
    if not conn:
        return
    try:
        conn.close()
    except Exception as e:
        logger.warning(f"Failed to release connection: {e}")
