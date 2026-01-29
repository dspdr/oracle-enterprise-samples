-- 02_seed.sql
-- Seed data (optional)
DECLARE
  v_pdb VARCHAR2(128);
BEGIN
  SELECT name
    INTO v_pdb
    FROM v$pdbs
   WHERE name NOT IN ('PDB$SEED')
   ORDER BY name
   FETCH FIRST 1 ROWS ONLY;
  EXECUTE IMMEDIATE 'ALTER SESSION SET CONTAINER = ' || v_pdb;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    NULL;
END;
/

-- No initial seed data required for this sample as applications are created via API.

EXIT;
