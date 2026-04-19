-- =============================================================================
-- 03_merge_crm.sql
-- Domain: CRM  (LabCRM_DB)
-- Tables: CRM_ACCOUNTS → CRM_CONTACTS → CRM_OPPORTUNITIES
--
-- Called from: dag_01_ingest_bronze.py → task group 'crm_domain'
-- =============================================================================


-- ── CRM_ACCOUNTS ─────────────────────────────────────────────────────────────
MERGE INTO MSSQL_MIGRATION_LAB.BRONZE.CRM_ACCOUNTS tgt
USING (
    SELECT
        v:AccountId::NUMBER         AS ACCOUNT_ID,
        v:AccountCode::VARCHAR      AS ACCOUNT_CODE,
        v:Name::VARCHAR             AS NAME,
        v:Region::VARCHAR           AS REGION,
        v:CreatedAt::TIMESTAMP_NTZ  AS CREATED_AT,
        _DMS_OPERATION,
        _DMS_COMMIT_TS
    FROM MSSQL_MIGRATION_LAB.RAW_MSSQL.RAW_DMS_VARIANT
    WHERE v:AccountId   IS NOT NULL
      AND v:AccountCode IS NOT NULL
      AND _DMS_COMMIT_TS > COALESCE(
            (SELECT MAX(_DMS_COMMIT_TS) FROM MSSQL_MIGRATION_LAB.BRONZE.CRM_ACCOUNTS
             WHERE _DMS_COMMIT_TS IS NOT NULL),
            '1970-01-01'::TIMESTAMP_NTZ
          )
    QUALIFY ROW_NUMBER() OVER (PARTITION BY v:AccountId ORDER BY _DMS_COMMIT_TS DESC) = 1
) src
ON tgt.ACCOUNT_ID = src.ACCOUNT_ID
WHEN MATCHED AND src._DMS_OPERATION = 'D' THEN DELETE
WHEN MATCHED THEN UPDATE SET
    ACCOUNT_CODE   = src.ACCOUNT_CODE,
    NAME           = src.NAME,
    REGION         = src.REGION,
    CREATED_AT     = src.CREATED_AT,
    _DMS_OPERATION = src._DMS_OPERATION,
    _DMS_COMMIT_TS = src._DMS_COMMIT_TS,
    _LOADED_AT     = CURRENT_TIMESTAMP()
WHEN NOT MATCHED AND src._DMS_OPERATION <> 'D' THEN INSERT
    (ACCOUNT_ID, ACCOUNT_CODE, NAME, REGION, CREATED_AT, _DMS_OPERATION, _DMS_COMMIT_TS)
VALUES
    (src.ACCOUNT_ID, src.ACCOUNT_CODE, src.NAME, src.REGION, src.CREATED_AT,
     src._DMS_OPERATION, src._DMS_COMMIT_TS);


-- ── CRM_CONTACTS ─────────────────────────────────────────────────────────────
MERGE INTO MSSQL_MIGRATION_LAB.BRONZE.CRM_CONTACTS tgt
USING (
    SELECT
        v:ContactId::NUMBER         AS CONTACT_ID,
        v:AccountId::NUMBER         AS ACCOUNT_ID,
        v:Email::VARCHAR            AS EMAIL,
        v:FullName::VARCHAR         AS FULL_NAME,
        v:IsPrimary::BOOLEAN        AS IS_PRIMARY,
        _DMS_OPERATION,
        _DMS_COMMIT_TS
    FROM MSSQL_MIGRATION_LAB.RAW_MSSQL.RAW_DMS_VARIANT
    WHERE v:ContactId IS NOT NULL
      AND v:Email     IS NOT NULL
      AND v:AccountId IS NOT NULL
      AND _DMS_COMMIT_TS > COALESCE(
            (SELECT MAX(_DMS_COMMIT_TS) FROM MSSQL_MIGRATION_LAB.BRONZE.CRM_CONTACTS
             WHERE _DMS_COMMIT_TS IS NOT NULL),
            '1970-01-01'::TIMESTAMP_NTZ
          )
    QUALIFY ROW_NUMBER() OVER (PARTITION BY v:ContactId ORDER BY _DMS_COMMIT_TS DESC) = 1
) src
ON tgt.CONTACT_ID = src.CONTACT_ID
WHEN MATCHED AND src._DMS_OPERATION = 'D' THEN DELETE
WHEN MATCHED THEN UPDATE SET
    ACCOUNT_ID     = src.ACCOUNT_ID,
    EMAIL          = src.EMAIL,
    FULL_NAME      = src.FULL_NAME,
    IS_PRIMARY     = src.IS_PRIMARY,
    _DMS_OPERATION = src._DMS_OPERATION,
    _DMS_COMMIT_TS = src._DMS_COMMIT_TS,
    _LOADED_AT     = CURRENT_TIMESTAMP()
WHEN NOT MATCHED AND src._DMS_OPERATION <> 'D' THEN INSERT
    (CONTACT_ID, ACCOUNT_ID, EMAIL, FULL_NAME, IS_PRIMARY, _DMS_OPERATION, _DMS_COMMIT_TS)
VALUES
    (src.CONTACT_ID, src.ACCOUNT_ID, src.EMAIL, src.FULL_NAME, src.IS_PRIMARY,
     src._DMS_OPERATION, src._DMS_COMMIT_TS);


-- ── CRM_OPPORTUNITIES ────────────────────────────────────────────────────────
MERGE INTO MSSQL_MIGRATION_LAB.BRONZE.CRM_OPPORTUNITIES tgt
USING (
    SELECT
        v:OppId::NUMBER             AS OPP_ID,
        v:AccountId::NUMBER         AS ACCOUNT_ID,
        v:Title::VARCHAR            AS TITLE,
        v:Stage::VARCHAR            AS STAGE,
        v:AmountUsd::NUMBER(18,2)   AS AMOUNT_USD,
        v:CloseDate::DATE           AS CLOSE_DATE,
        _DMS_OPERATION,
        _DMS_COMMIT_TS
    FROM MSSQL_MIGRATION_LAB.RAW_MSSQL.RAW_DMS_VARIANT
    WHERE v:OppId     IS NOT NULL
      AND v:AccountId IS NOT NULL
      AND _DMS_COMMIT_TS > COALESCE(
            (SELECT MAX(_DMS_COMMIT_TS) FROM MSSQL_MIGRATION_LAB.BRONZE.CRM_OPPORTUNITIES
             WHERE _DMS_COMMIT_TS IS NOT NULL),
            '1970-01-01'::TIMESTAMP_NTZ
          )
    QUALIFY ROW_NUMBER() OVER (PARTITION BY v:OppId ORDER BY _DMS_COMMIT_TS DESC) = 1
) src
ON tgt.OPP_ID = src.OPP_ID
WHEN MATCHED AND src._DMS_OPERATION = 'D' THEN DELETE
WHEN MATCHED THEN UPDATE SET
    ACCOUNT_ID     = src.ACCOUNT_ID,
    TITLE          = src.TITLE,
    STAGE          = src.STAGE,
    AMOUNT_USD     = src.AMOUNT_USD,
    CLOSE_DATE     = src.CLOSE_DATE,
    _DMS_OPERATION = src._DMS_OPERATION,
    _DMS_COMMIT_TS = src._DMS_COMMIT_TS,
    _LOADED_AT     = CURRENT_TIMESTAMP()
WHEN NOT MATCHED AND src._DMS_OPERATION <> 'D' THEN INSERT
    (OPP_ID, ACCOUNT_ID, TITLE, STAGE, AMOUNT_USD, CLOSE_DATE,
     _DMS_OPERATION, _DMS_COMMIT_TS)
VALUES
    (src.OPP_ID, src.ACCOUNT_ID, src.TITLE, src.STAGE, src.AMOUNT_USD, src.CLOSE_DATE,
     src._DMS_OPERATION, src._DMS_COMMIT_TS);
