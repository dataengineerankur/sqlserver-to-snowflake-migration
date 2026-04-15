-- ============================================================
-- SILVER layer: SnowConvertStressDB
-- ============================================================
-- ⚠  SCD Type-2 tables (CUSTOMERS, PRODUCTS, ORDERS) are created
--    and maintained exclusively by dbt snapshots (dbt run snapshots).
--    DO NOT create or alter those tables manually — dbt owns the schema.
--
-- dbt snapshot columns added automatically:
--   dbt_scd_id    VARCHAR  — hash of unique_key + check_cols
--   dbt_valid_from TIMESTAMP_NTZ — when this version became active
--   dbt_valid_to   TIMESTAMP_NTZ — when this version expired (NULL = current)
--   dbt_updated_at TIMESTAMP_NTZ — last time dbt processed this row
--
-- Non-snapshot tables (CATEGORIES, ORDER_ITEMS) are created here
-- as reference DDL only; Snowpipe / dbt stg models write to them.
-- ============================================================

USE DATABASE MSSQL_MIGRATION_LAB;
CREATE SCHEMA IF NOT EXISTS SILVER;

-- ── CATEGORIES (reference / static — no SCD2) ────────────────────────────
-- Small lookup table, no history needed. dbt stg model writes directly.
CREATE TABLE IF NOT EXISTS SILVER.CATEGORIES (
    CATEGORY_ID     NUMBER          NOT NULL PRIMARY KEY,
    CATEGORY_NAME   VARCHAR(100)    NOT NULL,
    DESCRIPTION     VARCHAR(500),
    _LOADED_AT      TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    _SOURCE_DB      VARCHAR(128)    NOT NULL DEFAULT 'SnowConvertStressDB'
);

-- ── CUSTOMERS (SCD Type-2 — managed by dbt snapshot snp_customers) ───────
-- dbt will CREATE OR REPLACE this table on first run.
-- Reference DDL below shows the full column set after dbt runs.
CREATE TABLE IF NOT EXISTS SILVER.CUSTOMERS (
    CUSTOMER_ID     NUMBER          NOT NULL,
    CUSTOMER_CODE   VARCHAR(20)     NOT NULL,
    FULL_NAME       VARCHAR(200)    NOT NULL,
    EMAIL           VARCHAR(320),
    COUNTRY         VARCHAR(100)    NOT NULL,
    CREATED_AT      TIMESTAMP_NTZ(3),
    _SOURCE_DB      VARCHAR(128)    NOT NULL,
    -- dbt snapshot columns (auto-managed):
    dbt_scd_id      VARCHAR         NOT NULL,
    dbt_valid_from  TIMESTAMP_NTZ   NOT NULL,
    dbt_valid_to    TIMESTAMP_NTZ,              -- NULL = current record
    dbt_updated_at  TIMESTAMP_NTZ   NOT NULL
);

-- ── PRODUCTS (SCD Type-2 — managed by dbt snapshot snp_products) ─────────
-- Replaces tr_Products_ListPriceAudit trigger — full price history in Silver.
CREATE TABLE IF NOT EXISTS SILVER.PRODUCTS (
    PRODUCT_ID      NUMBER          NOT NULL,
    CATEGORY_ID     NUMBER          NOT NULL,
    SKU             VARCHAR(50)     NOT NULL,
    PRODUCT_NAME    VARCHAR(200)    NOT NULL,
    LIST_PRICE      NUMBER(18,4)    NOT NULL,
    IS_ACTIVE       BOOLEAN         NOT NULL,
    _SOURCE_DB      VARCHAR(128)    NOT NULL,
    -- dbt snapshot columns (auto-managed):
    dbt_scd_id      VARCHAR         NOT NULL,
    dbt_valid_from  TIMESTAMP_NTZ   NOT NULL,
    dbt_valid_to    TIMESTAMP_NTZ,
    dbt_updated_at  TIMESTAMP_NTZ   NOT NULL
);

-- ── ORDERS (SCD Type-2 — managed by dbt snapshot snp_orders) ─────────────
-- Tracks STATUS and TOTAL_AMOUNT changes over the order lifecycle.
CREATE TABLE IF NOT EXISTS SILVER.ORDERS (
    ORDER_ID        NUMBER          NOT NULL,
    CUSTOMER_ID     NUMBER          NOT NULL,
    ORDER_DATE      DATE            NOT NULL,
    STATUS          VARCHAR(30)     NOT NULL,
    TOTAL_AMOUNT    NUMBER(18,4)    NOT NULL,
    NOTES           VARCHAR(500),
    _SOURCE_DB      VARCHAR(128)    NOT NULL,
    -- dbt snapshot columns (auto-managed):
    dbt_scd_id      VARCHAR         NOT NULL,
    dbt_valid_from  TIMESTAMP_NTZ   NOT NULL,
    dbt_valid_to    TIMESTAMP_NTZ,
    dbt_updated_at  TIMESTAMP_NTZ   NOT NULL
);

-- ── ORDER_ITEMS (append-only — no SCD2) ──────────────────────────────────
-- Immutable journal: once an order item is written it never changes.
-- dbt int_order_items writes to this via incremental append.
CREATE TABLE IF NOT EXISTS SILVER.ORDER_ITEMS (
    ORDER_ITEM_ID   NUMBER          NOT NULL PRIMARY KEY,
    ORDER_ID        NUMBER          NOT NULL,
    PRODUCT_ID      NUMBER          NOT NULL,
    QUANTITY        NUMBER          NOT NULL,
    UNIT_PRICE      NUMBER(18,4)    NOT NULL,
    LINE_TOTAL      NUMBER(18,4)    NOT NULL,   -- resolved computed col
    _LOADED_AT      TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    _SOURCE_DB      VARCHAR(128)    NOT NULL DEFAULT 'SnowConvertStressDB'
);
