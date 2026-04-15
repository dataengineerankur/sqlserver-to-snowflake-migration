-- ============================================================
-- Iceberg Tables: Audit & Activity Logs
-- ============================================================
-- These three tables are the best candidates for Apache Iceberg
-- format in this migration because:
--   1. They are append-only (immutable journal semantics)
--   2. They grow unboundedly and need time-travel / point-in-time
--      queries for compliance and incident investigation
--   3. They benefit from partition pruning on event date for query cost
--   4. External tooling (Spark, Trino, AWS Athena) may need to read
--      them directly from S3 without going through Snowflake
--
-- Prerequisites:
--   1. An EXTERNAL VOLUME pointing to the S3 bucket where Iceberg
--      metadata and data files will be stored.
--   2. A CATALOG INTEGRATION (using SNOWFLAKE as the Iceberg catalog).
--
-- Run once per environment (dev / prod) — adjust bucket paths below.
-- ============================================================

USE DATABASE MSSQL_MIGRATION_LAB;
CREATE SCHEMA IF NOT EXISTS AUDIT;

-- ── 1. Prerequisites ─────────────────────────────────────────────────────
-- Create external volume (run as ACCOUNTADMIN; adjust bucket + IAM role)

CREATE EXTERNAL VOLUME IF NOT EXISTS iceberg_audit_vol
    STORAGE_LOCATIONS = (
        (
            NAME                 = 'iceberg-audit-s3'
            STORAGE_PROVIDER     = 'S3'
            STORAGE_BASE_URL     = 's3://mssql-migration-datalake/iceberg/'
            STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::YOUR_ACCOUNT_ID:role/snowflake-iceberg-role'
        )
    );

-- ── 2. MIGRATION_AUDIT_LOG ───────────────────────────────────────────────
-- Tracks every DMS full-load and Snowpipe batch event.
-- Written by the Airflow DAG (mssql_migration_pipeline.py) after each load.
-- Replaces: GOLD.MIGRATION_METADATA (non-Iceberg table created earlier).

CREATE ICEBERG TABLE IF NOT EXISTS AUDIT.MIGRATION_AUDIT_LOG (
    EVENT_ID        VARCHAR         NOT NULL COMMENT 'UUID generated at insert time',
    EVENT_TS        TIMESTAMP_NTZ   NOT NULL COMMENT 'When the event was recorded',
    EVENT_DATE      DATE            NOT NULL COMMENT 'Partition key — derived from EVENT_TS',
    SOURCE_DB       VARCHAR(128)    NOT NULL COMMENT 'e.g. SnowConvertStressDB, LabERP_DB',
    SOURCE_TABLE    VARCHAR(256)    NOT NULL COMMENT 'Fully qualified SQL Server table name',
    TARGET_TABLE    VARCHAR(256)    NOT NULL COMMENT 'Snowflake Bronze table name',
    LOAD_TYPE       VARCHAR(20)     NOT NULL COMMENT 'FULL_LOAD | CDC | SNOWPIPE',
    ROW_COUNT       NUMBER                   COMMENT 'Rows ingested in this batch',
    BYTES_LOADED    NUMBER                   COMMENT 'Uncompressed bytes loaded',
    STATUS          VARCHAR(20)     NOT NULL COMMENT 'SUCCESS | PARTIAL | FAILED',
    ERROR_MSG       VARCHAR(2000)            COMMENT 'Populated on failure',
    DMS_TASK_ARN    VARCHAR(512)             COMMENT 'AWS DMS task ARN if applicable',
    PIPELINE_RUN_ID VARCHAR(128)             COMMENT 'Airflow DAG run ID'
)
    CATALOG         = 'SNOWFLAKE'
    EXTERNAL_VOLUME = 'iceberg_audit_vol'
    BASE_LOCATION   = 'migration_audit_log/'
    PARTITION BY (EVENT_DATE)
    COMMENT = 'Append-only DMS + Snowpipe ingestion audit log — never update or delete rows';


-- ── 3. ERP_AUDIT_LOG ─────────────────────────────────────────────────────
-- Replaces SQL Server tr_Employees_Audit trigger.
-- Every salary, department, or name change captured here at the application
-- level (written by the ERP app / stored proc equivalent in Snowflake).
-- The dbt snp_erp_employees snapshot gives the full SCD2 history;
-- this table gives the raw "who changed what and when" audit trail.

CREATE ICEBERG TABLE IF NOT EXISTS AUDIT.ERP_AUDIT_LOG (
    AUDIT_ID        VARCHAR         NOT NULL COMMENT 'UUID generated at insert time',
    AUDIT_TS        TIMESTAMP_NTZ   NOT NULL COMMENT 'When the change was recorded',
    AUDIT_DATE      DATE            NOT NULL COMMENT 'Partition key — derived from AUDIT_TS',
    EMP_ID          NUMBER          NOT NULL COMMENT 'Employee that was changed',
    CHANGED_BY      VARCHAR(200)             COMMENT 'User who made the change (NULL = system)',
    OPERATION       VARCHAR(10)     NOT NULL COMMENT 'INSERT | UPDATE | DELETE',
    FIELD_NAME      VARCHAR(100)             COMMENT 'Column that changed (NULL = full row event)',
    OLD_VALUE       VARCHAR(2000)            COMMENT 'Serialised previous value',
    NEW_VALUE       VARCHAR(2000)            COMMENT 'Serialised new value',
    SOURCE_DB       VARCHAR(128)    NOT NULL DEFAULT 'LabERP_DB',
    PIPELINE_RUN_ID VARCHAR(128)             COMMENT 'Airflow DAG run ID or NULL for direct writes'
)
    CATALOG         = 'SNOWFLAKE'
    EXTERNAL_VOLUME = 'iceberg_audit_vol'
    BASE_LOCATION   = 'erp_audit_log/'
    PARTITION BY (AUDIT_DATE)
    COMMENT = 'Append-only ERP employee audit log — replaces SQL Server tr_Employees_Audit trigger';


-- ── 4. CRM_ACTIVITY_LOG ──────────────────────────────────────────────────
-- Tracks all CRM entity interactions: calls, emails, meetings, stage changes.
-- High-volume, time-series data that grows ~10k rows/day per sales rep.
-- Queried almost exclusively by date range → partition by date is essential.
-- External analytics (Spark / Athena) may join this with Salesforce exports
-- without routing through Snowflake compute.

CREATE ICEBERG TABLE IF NOT EXISTS AUDIT.CRM_ACTIVITY_LOG (
    ACTIVITY_ID     VARCHAR         NOT NULL COMMENT 'UUID generated at insert time',
    ACTIVITY_TS     TIMESTAMP_NTZ   NOT NULL COMMENT 'When the activity occurred',
    ACTIVITY_DATE   DATE            NOT NULL COMMENT 'Partition key — derived from ACTIVITY_TS',
    ENTITY_TYPE     VARCHAR(40)     NOT NULL COMMENT 'ACCOUNT | CONTACT | OPPORTUNITY',
    ENTITY_ID       NUMBER          NOT NULL COMMENT 'FK to the relevant CRM entity',
    ACTIVITY_TYPE   VARCHAR(40)     NOT NULL COMMENT 'CALL | EMAIL | MEETING | STAGE_CHANGE | NOTE',
    PERFORMED_BY    VARCHAR(200)             COMMENT 'CRM user / rep name',
    DESCRIPTION     VARCHAR(4000)            COMMENT 'Free-text notes or stage transition detail',
    OLD_STAGE       VARCHAR(40)              COMMENT 'Previous pipeline stage (STAGE_CHANGE only)',
    NEW_STAGE       VARCHAR(40)              COMMENT 'New pipeline stage (STAGE_CHANGE only)',
    AMOUNT_CHANGED  NUMBER(18,2)             COMMENT 'Deal value delta if amount changed',
    SOURCE_DB       VARCHAR(128)    NOT NULL DEFAULT 'LabCRM_DB',
    PIPELINE_RUN_ID VARCHAR(128)             COMMENT 'Airflow DAG run ID or NULL for direct writes'
)
    CATALOG         = 'SNOWFLAKE'
    EXTERNAL_VOLUME = 'iceberg_audit_vol'
    BASE_LOCATION   = 'crm_activity_log/'
    PARTITION BY (ACTIVITY_DATE)
    COMMENT = 'Append-only CRM activity log — high-volume time-series, queryable by Spark/Athena via S3';


-- ── 5. Post-create: S3 lifecycle tie-in ──────────────────────────────────
-- The S3 bucket already has a Glacier transition rule for objects older
-- than 365 days (see infra/aws-cdk/lib/data-landing-stack.ts).
-- Iceberg data files under iceberg/migration_audit_log/ and siblings
-- will automatically transition to Glacier after 1 year, keeping storage
-- cost minimal while preserving full compliance history.
--
-- To read archived partitions via time-travel:
--   SELECT * FROM AUDIT.MIGRATION_AUDIT_LOG
--   AT (TIMESTAMP => '2025-01-01 00:00:00'::TIMESTAMP_NTZ)
--   WHERE SOURCE_DB = 'SnowConvertStressDB';
