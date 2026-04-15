-- ============================================================
-- SILVER layer: LabERP_DB
-- ============================================================
-- ⚠  ERP_EMPLOYEES is created and maintained by dbt snapshot
--    snp_erp_employees. DO NOT create or alter it manually.
--
-- ERP_DEPARTMENTS and ERP_PAYROLL_LINES are NOT snapshot-managed:
--   - ERP_DEPARTMENTS is a small reference table (no SCD2 needed)
--   - ERP_PAYROLL_LINES is append-only (immutable payroll journal)
-- ============================================================

USE DATABASE MSSQL_MIGRATION_LAB;

-- ── ERP_DEPARTMENTS (reference / static — no SCD2) ───────────────────────
CREATE TABLE IF NOT EXISTS SILVER.ERP_DEPARTMENTS (
    DEPT_ID         NUMBER          NOT NULL PRIMARY KEY,
    DEPT_CODE       VARCHAR(20)     NOT NULL,
    DEPT_NAME       VARCHAR(120)    NOT NULL,
    BUDGET_USD      NUMBER(18,2)    NOT NULL,
    _LOADED_AT      TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    _SOURCE_DB      VARCHAR(128)    NOT NULL DEFAULT 'LabERP_DB'
);

-- ── ERP_EMPLOYEES (SCD Type-2 — managed by dbt snapshot snp_erp_employees) ─
-- Replaces tr_Employees_Audit trigger — full salary / department history.
CREATE TABLE IF NOT EXISTS SILVER.ERP_EMPLOYEES (
    EMP_ID          NUMBER          NOT NULL,
    DEPT_ID         NUMBER          NOT NULL,
    EMP_CODE        VARCHAR(20)     NOT NULL,
    FULL_NAME       VARCHAR(200)    NOT NULL,
    HIRE_DATE       DATE            NOT NULL,
    SALARY          NUMBER(18,4)    NOT NULL,
    _SOURCE_DB      VARCHAR(128)    NOT NULL,
    -- dbt snapshot columns (auto-managed):
    dbt_scd_id      VARCHAR         NOT NULL,
    dbt_valid_from  TIMESTAMP_NTZ   NOT NULL,
    dbt_valid_to    TIMESTAMP_NTZ,              -- NULL = current record
    dbt_updated_at  TIMESTAMP_NTZ   NOT NULL
);

-- ── ERP_PAYROLL_LINES (append-only — no SCD2) ────────────────────────────
-- Immutable payroll journal. dbt int_erp_payroll_lines writes via
-- incremental append. RUN_MONTH is denormalised from PayrollRuns at staging.
CREATE TABLE IF NOT EXISTS SILVER.ERP_PAYROLL_LINES (
    LINE_ID         NUMBER          NOT NULL PRIMARY KEY,
    RUN_ID          NUMBER          NOT NULL,
    EMP_ID          NUMBER          NOT NULL,
    RUN_MONTH       CHAR(7)         NOT NULL,   -- 'YYYY-MM' denormalised
    GROSS_PAY       NUMBER(18,4)    NOT NULL,
    NET_PAY         NUMBER(18,4)    NOT NULL,   -- resolved: GROSS_PAY * 0.92
    _LOADED_AT      TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    _SOURCE_DB      VARCHAR(128)    NOT NULL DEFAULT 'LabERP_DB'
);
