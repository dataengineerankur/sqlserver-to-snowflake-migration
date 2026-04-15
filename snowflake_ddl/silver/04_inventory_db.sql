-- ============================================================
-- SILVER layer: LabInventory_DB
-- ============================================================
-- ⚠  INV_SKU is created and maintained by dbt snapshot snp_inv_sku.
--    DO NOT create or alter it manually.
--
-- INV_WAREHOUSES and INV_STOCK_MOVEMENTS are NOT snapshot-managed:
--   - INV_WAREHOUSES is a small reference table (no SCD2 needed)
--   - INV_STOCK_MOVEMENTS is an append-only movement journal
--
-- INV_STOCK_BALANCE is REMOVED — replaced by GOLD.FCT_INVENTORY_POSITION
-- (dbt model fct_inventory_position), which computes SUM(QTY_CHANGE)
-- per WH_CODE + SKU_CODE on every incremental run.
-- ============================================================

USE DATABASE MSSQL_MIGRATION_LAB;

-- ── INV_WAREHOUSES (reference / static — no SCD2) ────────────────────────
CREATE TABLE IF NOT EXISTS SILVER.INV_WAREHOUSES (
    WH_ID           NUMBER          NOT NULL PRIMARY KEY,
    WH_CODE         VARCHAR(20)     NOT NULL,
    LOCATION        VARCHAR(200)    NOT NULL,
    _LOADED_AT      TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    _SOURCE_DB      VARCHAR(128)    NOT NULL DEFAULT 'LabInventory_DB'
);

-- ── INV_SKU (SCD Type-2 — managed by dbt snapshot snp_inv_sku) ───────────
-- Tracks DESCR and UNIT_COST changes — cost history is critical for
-- accurately valuing historical stock movements at period cost.
CREATE TABLE IF NOT EXISTS SILVER.INV_SKU (
    SKU_ID          NUMBER          NOT NULL,
    SKU_CODE        VARCHAR(40)     NOT NULL,
    DESCR           VARCHAR(200)    NOT NULL,
    UNIT_COST       NUMBER(18,4)    NOT NULL,
    _SOURCE_DB      VARCHAR(128)    NOT NULL,
    -- dbt snapshot columns (auto-managed):
    dbt_scd_id      VARCHAR         NOT NULL,
    dbt_valid_from  TIMESTAMP_NTZ   NOT NULL,
    dbt_valid_to    TIMESTAMP_NTZ,              -- NULL = current / active price
    dbt_updated_at  TIMESTAMP_NTZ   NOT NULL
);

-- ── INV_STOCK_MOVEMENTS (append-only — no SCD2) ──────────────────────────
-- Immutable movement journal. dbt int_inv_stock_movements writes via
-- incremental append. Current stock is derived in GOLD by SUM(QTY_CHANGE).
CREATE TABLE IF NOT EXISTS SILVER.INV_STOCK_MOVEMENTS (
    MOV_ID          NUMBER          NOT NULL PRIMARY KEY,
    WH_ID           NUMBER          NOT NULL,
    SKU_ID          NUMBER          NOT NULL,
    QTY_CHANGE      NUMBER          NOT NULL,
    REASON          VARCHAR(80)     NOT NULL,
    MOV_DATE        TIMESTAMP_NTZ(3),
    _LOADED_AT      TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    _SOURCE_DB      VARCHAR(128)    NOT NULL DEFAULT 'LabInventory_DB'
);
