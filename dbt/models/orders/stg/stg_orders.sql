/*
  Staging: BRONZE.ORDERS → deduplication + delete filtering.
  Column names aligned to actual BRONZE DDL (STATUS, TOTAL_AMOUNT, NOTES).
*/

WITH source AS (
    SELECT
        ORDER_ID,
        CUSTOMER_ID,
        ORDER_DATE,
        STATUS,
        TOTAL_AMOUNT,
        NOTES,
        _DMS_OPERATION,
        _DMS_COMMIT_TS,
        _LOADED_AT,
        _SOURCE_DB,
        COALESCE(_DMS_COMMIT_TS, _LOADED_AT) AS _EFFECTIVE_TS
    FROM {{ source('bronze', 'orders') }}
    WHERE _DMS_OPERATION IS NULL OR _DMS_OPERATION != 'D'
)

SELECT
    ORDER_ID,
    CUSTOMER_ID,
    ORDER_DATE,
    STATUS,
    TOTAL_AMOUNT,
    NOTES,
    _DMS_OPERATION,
    _DMS_COMMIT_TS,
    _LOADED_AT,
    _SOURCE_DB
FROM source
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY ORDER_ID
    ORDER BY _EFFECTIVE_TS DESC, _LOADED_AT DESC
) = 1
