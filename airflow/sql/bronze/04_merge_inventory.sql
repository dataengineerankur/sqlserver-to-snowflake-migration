-- =============================================================================
-- 04_merge_inventory.sql
-- Domain: Inventory  (LabInventory_DB)
-- Tables: INV_WAREHOUSES → INV_SKU → INV_STOCK_MOVEMENTS
--
-- Note: INV_STOCK_MOVEMENTS is an immutable append-only journal.
-- The MERGE still handles D records for DMS compatibility, but in practice
-- stock movements are never deleted — they are reversed with a new row.
--
-- Called from: dag_01_ingest_bronze.py → task group 'inventory_domain'
-- =============================================================================


-- ── INV_WAREHOUSES ───────────────────────────────────────────────────────────
MERGE INTO MSSQL_MIGRATION_LAB.BRONZE.INV_WAREHOUSES tgt
USING (
    SELECT
        v:WhId::NUMBER              AS WH_ID,
        v:WhCode::VARCHAR           AS WH_CODE,
        v:Location::VARCHAR         AS LOCATION,
        _DMS_OPERATION,
        _DMS_COMMIT_TS
    FROM MSSQL_MIGRATION_LAB.RAW_MSSQL.RAW_DMS_VARIANT
    WHERE v:WhId   IS NOT NULL
      AND v:WhCode IS NOT NULL
      AND _DMS_COMMIT_TS > COALESCE(
            (SELECT MAX(_DMS_COMMIT_TS) FROM MSSQL_MIGRATION_LAB.BRONZE.INV_WAREHOUSES
             WHERE _DMS_COMMIT_TS IS NOT NULL),
            '1970-01-01'::TIMESTAMP_NTZ
          )
    QUALIFY ROW_NUMBER() OVER (PARTITION BY v:WhId ORDER BY _DMS_COMMIT_TS DESC) = 1
) src
ON tgt.WH_ID = src.WH_ID
WHEN MATCHED AND src._DMS_OPERATION = 'D' THEN DELETE
WHEN MATCHED THEN UPDATE SET
    WH_CODE        = src.WH_CODE,
    LOCATION       = src.LOCATION,
    _DMS_OPERATION = src._DMS_OPERATION,
    _DMS_COMMIT_TS = src._DMS_COMMIT_TS,
    _LOADED_AT     = CURRENT_TIMESTAMP()
WHEN NOT MATCHED AND src._DMS_OPERATION <> 'D' THEN INSERT
    (WH_ID, WH_CODE, LOCATION, _DMS_OPERATION, _DMS_COMMIT_TS)
VALUES
    (src.WH_ID, src.WH_CODE, src.LOCATION, src._DMS_OPERATION, src._DMS_COMMIT_TS);


-- ── INV_SKU ──────────────────────────────────────────────────────────────────
MERGE INTO MSSQL_MIGRATION_LAB.BRONZE.INV_SKU tgt
USING (
    SELECT
        v:SkuId::NUMBER             AS SKU_ID,
        v:SkuCode::VARCHAR          AS SKU_CODE,
        v:Descr::VARCHAR            AS DESCR,
        v:UnitCost::NUMBER(18,4)    AS UNIT_COST,
        _DMS_OPERATION,
        _DMS_COMMIT_TS
    FROM MSSQL_MIGRATION_LAB.RAW_MSSQL.RAW_DMS_VARIANT
    WHERE v:SkuId   IS NOT NULL
      AND v:SkuCode IS NOT NULL
      AND _DMS_COMMIT_TS > COALESCE(
            (SELECT MAX(_DMS_COMMIT_TS) FROM MSSQL_MIGRATION_LAB.BRONZE.INV_SKU
             WHERE _DMS_COMMIT_TS IS NOT NULL),
            '1970-01-01'::TIMESTAMP_NTZ
          )
    QUALIFY ROW_NUMBER() OVER (PARTITION BY v:SkuId ORDER BY _DMS_COMMIT_TS DESC) = 1
) src
ON tgt.SKU_ID = src.SKU_ID
WHEN MATCHED AND src._DMS_OPERATION = 'D' THEN DELETE
WHEN MATCHED THEN UPDATE SET
    SKU_CODE       = src.SKU_CODE,
    DESCR          = src.DESCR,
    UNIT_COST      = src.UNIT_COST,
    _DMS_OPERATION = src._DMS_OPERATION,
    _DMS_COMMIT_TS = src._DMS_COMMIT_TS,
    _LOADED_AT     = CURRENT_TIMESTAMP()
WHEN NOT MATCHED AND src._DMS_OPERATION <> 'D' THEN INSERT
    (SKU_ID, SKU_CODE, DESCR, UNIT_COST, _DMS_OPERATION, _DMS_COMMIT_TS)
VALUES
    (src.SKU_ID, src.SKU_CODE, src.DESCR, src.UNIT_COST,
     src._DMS_OPERATION, src._DMS_COMMIT_TS);


-- ── INV_STOCK_MOVEMENTS (append-only journal) ─────────────────────────────────
MERGE INTO MSSQL_MIGRATION_LAB.BRONZE.INV_STOCK_MOVEMENTS tgt
USING (
    SELECT
        v:MovId::NUMBER             AS MOV_ID,
        v:WhId::NUMBER              AS WH_ID,
        v:SkuId::NUMBER             AS SKU_ID,
        v:QtyChange::NUMBER         AS QTY_CHANGE,
        v:Reason::VARCHAR           AS REASON,
        v:MovDate::TIMESTAMP_NTZ    AS MOV_DATE,
        _DMS_OPERATION,
        _DMS_COMMIT_TS
    FROM MSSQL_MIGRATION_LAB.RAW_MSSQL.RAW_DMS_VARIANT
    WHERE v:MovId IS NOT NULL
      AND v:WhId  IS NOT NULL
      AND _DMS_COMMIT_TS > COALESCE(
            (SELECT MAX(_DMS_COMMIT_TS) FROM MSSQL_MIGRATION_LAB.BRONZE.INV_STOCK_MOVEMENTS
             WHERE _DMS_COMMIT_TS IS NOT NULL),
            '1970-01-01'::TIMESTAMP_NTZ
          )
    QUALIFY ROW_NUMBER() OVER (PARTITION BY v:MovId ORDER BY _DMS_COMMIT_TS DESC) = 1
) src
ON tgt.MOV_ID = src.MOV_ID
WHEN MATCHED AND src._DMS_OPERATION = 'D' THEN DELETE
WHEN MATCHED THEN UPDATE SET
    WH_ID          = src.WH_ID,
    SKU_ID         = src.SKU_ID,
    QTY_CHANGE     = src.QTY_CHANGE,
    REASON         = src.REASON,
    MOV_DATE       = src.MOV_DATE,
    _DMS_OPERATION = src._DMS_OPERATION,
    _DMS_COMMIT_TS = src._DMS_COMMIT_TS,
    _LOADED_AT     = CURRENT_TIMESTAMP()
WHEN NOT MATCHED AND src._DMS_OPERATION <> 'D' THEN INSERT
    (MOV_ID, WH_ID, SKU_ID, QTY_CHANGE, REASON, MOV_DATE, _DMS_OPERATION, _DMS_COMMIT_TS)
VALUES
    (src.MOV_ID, src.WH_ID, src.SKU_ID, src.QTY_CHANGE, src.REASON, src.MOV_DATE,
     src._DMS_OPERATION, src._DMS_COMMIT_TS);
