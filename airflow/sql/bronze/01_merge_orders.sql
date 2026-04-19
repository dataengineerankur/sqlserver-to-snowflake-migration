-- =============================================================================
-- 01_merge_orders.sql
-- Domain: Orders / StressTest  (SnowConvertStressDB)
-- Tables: CATEGORIES → PRODUCTS → CUSTOMERS → ORDERS → ORDER_ITEMS
--
-- Pattern: incremental MERGE using _DMS_COMMIT_TS as the watermark.
--   1. QUALIFY picks the most-recent CDC event per primary key.
--   2. WHEN MATCHED AND _DMS_OPERATION = 'D' → delete the row.
--   3. WHEN MATCHED → update all payload columns.
--   4. WHEN NOT MATCHED (new key) → insert.
--
-- Execute order matters: parent tables before child tables.
-- Called from: dag_01_ingest_bronze.py → task group 'orders_domain'
-- =============================================================================


-- ── CATEGORIES ───────────────────────────────────────────────────────────────
MERGE INTO MSSQL_MIGRATION_LAB.BRONZE.CATEGORIES tgt
USING (
    SELECT
        v:CategoryId::NUMBER        AS CATEGORY_ID,
        v:CategoryName::VARCHAR     AS CATEGORY_NAME,
        v:Description::VARCHAR      AS DESCRIPTION,
        _DMS_OPERATION,
        _DMS_COMMIT_TS
    FROM MSSQL_MIGRATION_LAB.RAW_MSSQL.RAW_DMS_VARIANT
    WHERE v:CategoryId     IS NOT NULL
      AND v:CategoryName   IS NOT NULL
      AND _DMS_COMMIT_TS   > COALESCE(
            (SELECT MAX(_DMS_COMMIT_TS) FROM MSSQL_MIGRATION_LAB.BRONZE.CATEGORIES
             WHERE _DMS_COMMIT_TS IS NOT NULL),
            '1970-01-01'::TIMESTAMP_NTZ
          )
    QUALIFY ROW_NUMBER() OVER (PARTITION BY v:CategoryId ORDER BY _DMS_COMMIT_TS DESC) = 1
) src
ON tgt.CATEGORY_ID = src.CATEGORY_ID
WHEN MATCHED AND src._DMS_OPERATION = 'D' THEN DELETE
WHEN MATCHED THEN UPDATE SET
    CATEGORY_NAME  = src.CATEGORY_NAME,
    DESCRIPTION    = src.DESCRIPTION,
    _DMS_OPERATION = src._DMS_OPERATION,
    _DMS_COMMIT_TS = src._DMS_COMMIT_TS,
    _LOADED_AT     = CURRENT_TIMESTAMP()
WHEN NOT MATCHED AND src._DMS_OPERATION <> 'D' THEN INSERT
    (CATEGORY_ID, CATEGORY_NAME, DESCRIPTION, _DMS_OPERATION, _DMS_COMMIT_TS)
VALUES
    (src.CATEGORY_ID, src.CATEGORY_NAME, src.DESCRIPTION, src._DMS_OPERATION, src._DMS_COMMIT_TS);


-- ── CUSTOMERS ────────────────────────────────────────────────────────────────
MERGE INTO MSSQL_MIGRATION_LAB.BRONZE.CUSTOMERS tgt
USING (
    SELECT
        v:CustomerId::NUMBER        AS CUSTOMER_ID,
        v:CustomerCode::VARCHAR     AS CUSTOMER_CODE,
        v:FullName::VARCHAR         AS FULL_NAME,
        v:Email::VARCHAR            AS EMAIL,
        v:Country::VARCHAR          AS COUNTRY,
        v:CreatedAt::TIMESTAMP_NTZ  AS CREATED_AT,
        _DMS_OPERATION,
        _DMS_COMMIT_TS
    FROM MSSQL_MIGRATION_LAB.RAW_MSSQL.RAW_DMS_VARIANT
    WHERE v:CustomerId IS NOT NULL
      AND v:Email      IS NOT NULL
      AND _DMS_COMMIT_TS > COALESCE(
            (SELECT MAX(_DMS_COMMIT_TS) FROM MSSQL_MIGRATION_LAB.BRONZE.CUSTOMERS
             WHERE _DMS_COMMIT_TS IS NOT NULL),
            '1970-01-01'::TIMESTAMP_NTZ
          )
    QUALIFY ROW_NUMBER() OVER (PARTITION BY v:CustomerId ORDER BY _DMS_COMMIT_TS DESC) = 1
) src
ON tgt.CUSTOMER_ID = src.CUSTOMER_ID
WHEN MATCHED AND src._DMS_OPERATION = 'D' THEN DELETE
WHEN MATCHED THEN UPDATE SET
    CUSTOMER_CODE  = src.CUSTOMER_CODE,
    FULL_NAME      = src.FULL_NAME,
    EMAIL          = src.EMAIL,
    COUNTRY        = src.COUNTRY,
    CREATED_AT     = src.CREATED_AT,
    _DMS_OPERATION = src._DMS_OPERATION,
    _DMS_COMMIT_TS = src._DMS_COMMIT_TS,
    _LOADED_AT     = CURRENT_TIMESTAMP()
WHEN NOT MATCHED AND src._DMS_OPERATION <> 'D' THEN INSERT
    (CUSTOMER_ID, CUSTOMER_CODE, FULL_NAME, EMAIL, COUNTRY, CREATED_AT,
     _DMS_OPERATION, _DMS_COMMIT_TS)
VALUES
    (src.CUSTOMER_ID, src.CUSTOMER_CODE, src.FULL_NAME, src.EMAIL, src.COUNTRY,
     src.CREATED_AT, src._DMS_OPERATION, src._DMS_COMMIT_TS);


-- ── PRODUCTS ─────────────────────────────────────────────────────────────────
MERGE INTO MSSQL_MIGRATION_LAB.BRONZE.PRODUCTS tgt
USING (
    SELECT
        v:ProductId::NUMBER         AS PRODUCT_ID,
        v:CategoryId::NUMBER        AS CATEGORY_ID,
        v:SKU::VARCHAR              AS SKU,
        v:ProductName::VARCHAR      AS PRODUCT_NAME,
        v:ListPrice::NUMBER(18,4)   AS LIST_PRICE,
        v:IsActive::BOOLEAN         AS IS_ACTIVE,
        _DMS_OPERATION,
        _DMS_COMMIT_TS
    FROM MSSQL_MIGRATION_LAB.RAW_MSSQL.RAW_DMS_VARIANT
    WHERE v:ProductId IS NOT NULL
      AND v:SKU       IS NOT NULL
      AND _DMS_COMMIT_TS > COALESCE(
            (SELECT MAX(_DMS_COMMIT_TS) FROM MSSQL_MIGRATION_LAB.BRONZE.PRODUCTS
             WHERE _DMS_COMMIT_TS IS NOT NULL),
            '1970-01-01'::TIMESTAMP_NTZ
          )
    QUALIFY ROW_NUMBER() OVER (PARTITION BY v:ProductId ORDER BY _DMS_COMMIT_TS DESC) = 1
) src
ON tgt.PRODUCT_ID = src.PRODUCT_ID
WHEN MATCHED AND src._DMS_OPERATION = 'D' THEN DELETE
WHEN MATCHED THEN UPDATE SET
    CATEGORY_ID    = src.CATEGORY_ID,
    SKU            = src.SKU,
    PRODUCT_NAME   = src.PRODUCT_NAME,
    LIST_PRICE     = src.LIST_PRICE,
    IS_ACTIVE      = src.IS_ACTIVE,
    _DMS_OPERATION = src._DMS_OPERATION,
    _DMS_COMMIT_TS = src._DMS_COMMIT_TS,
    _LOADED_AT     = CURRENT_TIMESTAMP()
WHEN NOT MATCHED AND src._DMS_OPERATION <> 'D' THEN INSERT
    (PRODUCT_ID, CATEGORY_ID, SKU, PRODUCT_NAME, LIST_PRICE, IS_ACTIVE,
     _DMS_OPERATION, _DMS_COMMIT_TS)
VALUES
    (src.PRODUCT_ID, src.CATEGORY_ID, src.SKU, src.PRODUCT_NAME, src.LIST_PRICE,
     src.IS_ACTIVE, src._DMS_OPERATION, src._DMS_COMMIT_TS);


-- ── ORDERS ───────────────────────────────────────────────────────────────────
MERGE INTO MSSQL_MIGRATION_LAB.BRONZE.ORDERS tgt
USING (
    SELECT
        v:OrderId::NUMBER           AS ORDER_ID,
        v:CustomerId::NUMBER        AS CUSTOMER_ID,
        v:OrderDate::DATE           AS ORDER_DATE,
        v:Status::VARCHAR           AS STATUS,
        v:TotalAmount::NUMBER(18,4) AS TOTAL_AMOUNT,
        v:Notes::VARCHAR            AS NOTES,
        _DMS_OPERATION,
        _DMS_COMMIT_TS
    FROM MSSQL_MIGRATION_LAB.RAW_MSSQL.RAW_DMS_VARIANT
    WHERE v:OrderId     IS NOT NULL
      AND v:TotalAmount IS NOT NULL
      AND _DMS_COMMIT_TS > COALESCE(
            (SELECT MAX(_DMS_COMMIT_TS) FROM MSSQL_MIGRATION_LAB.BRONZE.ORDERS
             WHERE _DMS_COMMIT_TS IS NOT NULL),
            '1970-01-01'::TIMESTAMP_NTZ
          )
    QUALIFY ROW_NUMBER() OVER (PARTITION BY v:OrderId ORDER BY _DMS_COMMIT_TS DESC) = 1
) src
ON tgt.ORDER_ID = src.ORDER_ID
WHEN MATCHED AND src._DMS_OPERATION = 'D' THEN DELETE
WHEN MATCHED THEN UPDATE SET
    CUSTOMER_ID    = src.CUSTOMER_ID,
    ORDER_DATE     = src.ORDER_DATE,
    STATUS         = src.STATUS,
    TOTAL_AMOUNT   = src.TOTAL_AMOUNT,
    NOTES          = src.NOTES,
    _DMS_OPERATION = src._DMS_OPERATION,
    _DMS_COMMIT_TS = src._DMS_COMMIT_TS,
    _LOADED_AT     = CURRENT_TIMESTAMP()
WHEN NOT MATCHED AND src._DMS_OPERATION <> 'D' THEN INSERT
    (ORDER_ID, CUSTOMER_ID, ORDER_DATE, STATUS, TOTAL_AMOUNT, NOTES,
     _DMS_OPERATION, _DMS_COMMIT_TS)
VALUES
    (src.ORDER_ID, src.CUSTOMER_ID, src.ORDER_DATE, src.STATUS, src.TOTAL_AMOUNT,
     src.NOTES, src._DMS_OPERATION, src._DMS_COMMIT_TS);


-- ── ORDER_ITEMS ───────────────────────────────────────────────────────────────
MERGE INTO MSSQL_MIGRATION_LAB.BRONZE.ORDER_ITEMS tgt
USING (
    SELECT
        v:OrderItemId::NUMBER       AS ORDER_ITEM_ID,
        v:OrderId::NUMBER           AS ORDER_ID,
        v:ProductId::NUMBER         AS PRODUCT_ID,
        v:Quantity::NUMBER          AS QUANTITY,
        v:UnitPrice::NUMBER(18,4)   AS UNIT_PRICE,
        v:LineTotal::NUMBER(18,4)   AS LINE_TOTAL,
        _DMS_OPERATION,
        _DMS_COMMIT_TS
    FROM MSSQL_MIGRATION_LAB.RAW_MSSQL.RAW_DMS_VARIANT
    WHERE v:OrderItemId IS NOT NULL
      AND _DMS_COMMIT_TS > COALESCE(
            (SELECT MAX(_DMS_COMMIT_TS) FROM MSSQL_MIGRATION_LAB.BRONZE.ORDER_ITEMS
             WHERE _DMS_COMMIT_TS IS NOT NULL),
            '1970-01-01'::TIMESTAMP_NTZ
          )
    QUALIFY ROW_NUMBER() OVER (PARTITION BY v:OrderItemId ORDER BY _DMS_COMMIT_TS DESC) = 1
) src
ON tgt.ORDER_ITEM_ID = src.ORDER_ITEM_ID
WHEN MATCHED AND src._DMS_OPERATION = 'D' THEN DELETE
WHEN MATCHED THEN UPDATE SET
    ORDER_ID       = src.ORDER_ID,
    PRODUCT_ID     = src.PRODUCT_ID,
    QUANTITY       = src.QUANTITY,
    UNIT_PRICE     = src.UNIT_PRICE,
    LINE_TOTAL     = src.LINE_TOTAL,
    _DMS_OPERATION = src._DMS_OPERATION,
    _DMS_COMMIT_TS = src._DMS_COMMIT_TS,
    _LOADED_AT     = CURRENT_TIMESTAMP()
WHEN NOT MATCHED AND src._DMS_OPERATION <> 'D' THEN INSERT
    (ORDER_ITEM_ID, ORDER_ID, PRODUCT_ID, QUANTITY, UNIT_PRICE, LINE_TOTAL,
     _DMS_OPERATION, _DMS_COMMIT_TS)
VALUES
    (src.ORDER_ITEM_ID, src.ORDER_ID, src.PRODUCT_ID, src.QUANTITY, src.UNIT_PRICE,
     src.LINE_TOTAL, src._DMS_OPERATION, src._DMS_COMMIT_TS);
