-- ============================================================
-- SILVER layer: LabCRM_DB
-- ============================================================
-- ⚠  CRM_ACCOUNTS and CRM_OPPORTUNITIES are created and
--    maintained by dbt snapshots (snp_crm_accounts,
--    snp_crm_opportunities). DO NOT create or alter them manually.
--
-- CRM_CONTACTS is NOT snapshot-managed (append-only reference).
-- ============================================================

USE DATABASE MSSQL_MIGRATION_LAB;

-- ── CRM_ACCOUNTS (SCD Type-2 — managed by dbt snapshot snp_crm_accounts) ─
-- Tracks NAME and REGION changes.
CREATE TABLE IF NOT EXISTS SILVER.CRM_ACCOUNTS (
    ACCOUNT_ID      NUMBER          NOT NULL,
    ACCOUNT_CODE    VARCHAR(30)     NOT NULL,
    NAME            VARCHAR(200)    NOT NULL,
    REGION          VARCHAR(50)     NOT NULL,
    CREATED_AT      TIMESTAMP_NTZ(3),
    _SOURCE_DB      VARCHAR(128)    NOT NULL,
    -- dbt snapshot columns (auto-managed):
    dbt_scd_id      VARCHAR         NOT NULL,
    dbt_valid_from  TIMESTAMP_NTZ   NOT NULL,
    dbt_valid_to    TIMESTAMP_NTZ,              -- NULL = current record
    dbt_updated_at  TIMESTAMP_NTZ   NOT NULL
);

-- ── CRM_CONTACTS (append-only reference — no SCD2) ───────────────────────
CREATE TABLE IF NOT EXISTS SILVER.CRM_CONTACTS (
    CONTACT_ID      NUMBER          NOT NULL PRIMARY KEY,
    ACCOUNT_ID      NUMBER          NOT NULL,
    EMAIL           VARCHAR(320)    NOT NULL,
    FULL_NAME       VARCHAR(200)    NOT NULL,
    IS_PRIMARY      BOOLEAN         NOT NULL,
    _LOADED_AT      TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    _SOURCE_DB      VARCHAR(128)    NOT NULL DEFAULT 'LabCRM_DB'
);

-- ── CRM_OPPORTUNITIES (SCD Type-2 — managed by snp_crm_opportunities) ────
-- Tracks STAGE, AMOUNT_USD, CLOSE_DATE changes.
-- invalidate_hard_deletes=false — closed/lost opps are never expired.
CREATE TABLE IF NOT EXISTS SILVER.CRM_OPPORTUNITIES (
    OPP_ID          NUMBER          NOT NULL,
    ACCOUNT_ID      NUMBER          NOT NULL,
    TITLE           VARCHAR(200)    NOT NULL,
    STAGE           VARCHAR(40)     NOT NULL,
    AMOUNT_USD      NUMBER(18,2)    NOT NULL,
    CLOSE_DATE      DATE,
    _SOURCE_DB      VARCHAR(128)    NOT NULL,
    -- dbt snapshot columns (auto-managed):
    dbt_scd_id      VARCHAR         NOT NULL,
    dbt_valid_from  TIMESTAMP_NTZ   NOT NULL,
    dbt_valid_to    TIMESTAMP_NTZ,
    dbt_updated_at  TIMESTAMP_NTZ   NOT NULL
);
