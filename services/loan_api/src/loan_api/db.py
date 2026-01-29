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
        
        logger.info(f"Initializing DB pool for {user}@{dsn}")
        try:
            _pool = oracledb.create_pool(
                user=user,
                password=password,
                dsn=dsn,
                min=1,
                max=10,
                increment=1
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
