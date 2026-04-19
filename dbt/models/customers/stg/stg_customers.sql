/*
  Staging: BRONZE.CUSTOMERS → deduplication + delete filtering.
  Column names aligned to actual BRONZE DDL (FULL_NAME, not FIRST/LAST split).
  QUALIFY keeps only the most recent DMS version per CUSTOMER_ID.
*/

WITH source AS (
    SELECT
        CUSTOMER_ID,
        CUSTOMER_CODE,
        FULL_NAME,
        EMAIL,
        COUNTRY,
        CREATED_AT,
        _DMS_OPERATION,
        _DMS_COMMIT_TS,
        _LOADED_AT,
        _SOURCE_DB,
        COALESCE(_DMS_COMMIT_TS, CREATED_AT) AS _EFFECTIVE_TS
    FROM {{ source('bronze', 'customers') }}
    WHERE _DMS_OPERATION IS NULL OR _DMS_OPERATION != 'D'
)

SELECT
    CUSTOMER_ID,
    CUSTOMER_CODE,
    FULL_NAME,
    EMAIL,
    COUNTRY,
    CREATED_AT,
    _DMS_OPERATION,
    _DMS_COMMIT_TS,
    _LOADED_AT,
    _SOURCE_DB
FROM source
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY CUSTOMER_ID
    ORDER BY _EFFECTIVE_TS DESC, _LOADED_AT DESC
) = 1
