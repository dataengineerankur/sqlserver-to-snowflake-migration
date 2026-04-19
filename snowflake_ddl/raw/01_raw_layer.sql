-- Landing zone for all DMS Parquet files from SQL Server via AWS DMS.
-- One table receives CDC events from all source tables across all 4 domains
-- (SnowConvertStressDB, LabERP_DB, LabCRM_DB, LabInventory_DB).
-- V holds the full source row payload; top-level columns carry DMS metadata.

USE DATABASE MSSQL_MIGRATION_LAB;

CREATE SCHEMA IF NOT EXISTS RAW_MSSQL;

-- ── Main landing table ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS RAW_MSSQL.RAW_DMS_VARIANT (
    V               VARIANT        NOT NULL,   -- full source row as JSON/Parquet payload
    _DMS_OPERATION  VARCHAR(1),                -- I=Insert  U=Update  D=Delete  (null on full-load)
    _DMS_COMMIT_TS  TIMESTAMP_NTZ(6),          -- CDC commit timestamp from SQL Server log
    _DMS_SEQNO      VARCHAR(40),               -- DMS internal sequence number for ordering
    _LOADED_AT      TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP()
);

-- ── S3 stage ──────────────────────────────────────────────────────────────────
-- Update STORAGE_INTEGRATION and URL with the real bucket ARN before deploying.
CREATE STAGE IF NOT EXISTS RAW_MSSQL.STG_DMS_MSSQL
    STORAGE_INTEGRATION = S3_DMS_INTEGRATION      -- replace with real storage integration name
    URL = 's3://YOUR-DMS-BUCKET/dms-output/'      -- replace with real bucket path
    FILE_FORMAT = RAW_MSSQL.FF_DMS_PARQUET;

-- ── File format ───────────────────────────────────────────────────────────────
CREATE FILE FORMAT IF NOT EXISTS RAW_MSSQL.FF_DMS_PARQUET
    TYPE = 'PARQUET'
    SNAPPY_COMPRESSION = TRUE;
