-- ============================================================
-- GOLD layer: cross-domain analytics tables + views
-- Sources: SILVER.* tables
-- Pattern: wide denormalized tables, pre-aggregated for BI
-- ============================================================

USE DATABASE MSSQL_MIGRATION_LAB;
CREATE SCHEMA IF NOT EXISTS GOLD;

-- ── Sales summary (from SnowConvertStressDB) ─────────────────
CREATE OR REPLACE TABLE GOLD.FACT_ORDERS (
    ORDER_SK            NUMBER          NOT NULL,
    ORDER_ID            NUMBER          NOT NULL,
    ORDER_DATE          DATE            NOT NULL,
    ORDER_MONTH         CHAR(7)         NOT NULL,   -- derived: FORMAT(order_date, 'yyyy-MM')
    CUSTOMER_ID         NUMBER          NOT NULL,
    CUSTOMER_CODE       VARCHAR(20),
    CUSTOMER_NAME       VARCHAR(200),
    COUNTRY             VARCHAR(100),
    STATUS              VARCHAR(30)     NOT NULL,
    LINE_COUNT          NUMBER          NOT NULL DEFAULT 0,
    TOTAL_AMOUNT        NUMBER(18,4)    NOT NULL,
    _LOADED_AT          TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE GOLD.FACT_ORDER_ITEMS (
    ORDER_ITEM_SK       NUMBER          NOT NULL,
    ORDER_ID            NUMBER          NOT NULL,
    ORDER_DATE          DATE            NOT NULL,
    PRODUCT_ID          NUMBER          NOT NULL,
    SKU                 VARCHAR(50),
    PRODUCT_NAME        VARCHAR(200),
    CATEGORY_NAME       VARCHAR(100),
    QUANTITY            NUMBER          NOT NULL,
    UNIT_PRICE          NUMBER(18,4)    NOT NULL,
    LINE_TOTAL          NUMBER(18,4)    NOT NULL,
    _LOADED_AT          TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP()
);

-- ── ERP payroll summary ──────────────────────────────────────
CREATE OR REPLACE TABLE GOLD.FACT_PAYROLL_SUMMARY (
    RUN_MONTH           CHAR(7)         NOT NULL,
    DEPT_CODE           VARCHAR(20),
    DEPT_NAME           VARCHAR(120),
    EMPLOYEE_COUNT      NUMBER          NOT NULL DEFAULT 0,
    TOTAL_GROSS_PAY     NUMBER(18,4)    NOT NULL DEFAULT 0,
    TOTAL_NET_PAY       NUMBER(18,4)    NOT NULL DEFAULT 0,
    _LOADED_AT          TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP()
);

-- ── CRM pipeline summary ─────────────────────────────────────
CREATE OR REPLACE TABLE GOLD.FACT_CRM_PIPELINE (
    REGION              VARCHAR(50)     NOT NULL,
    STAGE               VARCHAR(40)     NOT NULL,
    OPP_COUNT           NUMBER          NOT NULL DEFAULT 0,
    TOTAL_AMOUNT_USD    NUMBER(18,2)    NOT NULL DEFAULT 0,
    AVG_AMOUNT_USD      NUMBER(18,2),
    _LOADED_AT          TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP()
);

-- ── Inventory position ───────────────────────────────────────
CREATE OR REPLACE TABLE GOLD.FACT_INVENTORY_POSITION (
    WH_CODE             VARCHAR(20)     NOT NULL,
    SKU_CODE            VARCHAR(40)     NOT NULL,
    DESCR               VARCHAR(200),
    UNIT_COST           NUMBER(18,4),
    CURRENT_QTY         NUMBER          NOT NULL DEFAULT 0,
    STOCK_VALUE_USD     NUMBER(18,4),   -- CURRENT_QTY * UNIT_COST
    _LOADED_AT          TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP()
);

-- ── Cross-domain dimension: DATE ─────────────────────────────
CREATE OR REPLACE TABLE GOLD.DIM_DATE (
    DATE_KEY            NUMBER          NOT NULL PRIMARY KEY,   -- YYYYMMDD int
    FULL_DATE           DATE            NOT NULL,
    YEAR                NUMBER          NOT NULL,
    QUARTER             NUMBER          NOT NULL,
    MONTH               NUMBER          NOT NULL,
    MONTH_NAME          VARCHAR(12)     NOT NULL,
    WEEK_OF_YEAR        NUMBER          NOT NULL,
    DAY_OF_WEEK         NUMBER          NOT NULL,
    DAY_NAME            VARCHAR(12)     NOT NULL,
    IS_WEEKEND          BOOLEAN         NOT NULL
);
