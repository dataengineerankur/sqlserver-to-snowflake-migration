/*
  Staging: BRONZE.PRODUCTS → deduplication + delete filtering.
  Column names aligned to actual BRONZE DDL (LIST_PRICE, CATEGORY_ID, IS_ACTIVE).
*/

WITH source AS (
    SELECT
        PRODUCT_ID,
        CATEGORY_ID,
        SKU,
        PRODUCT_NAME,
        LIST_PRICE,
        IS_ACTIVE,
        _DMS_OPERATION,
        _DMS_COMMIT_TS,
        _LOADED_AT,
        _SOURCE_DB,
        COALESCE(_DMS_COMMIT_TS, _LOADED_AT) AS _EFFECTIVE_TS
    FROM {{ source('bronze', 'products') }}
    WHERE _DMS_OPERATION IS NULL OR _DMS_OPERATION != 'D'
)

SELECT
    PRODUCT_ID,
    CATEGORY_ID,
    SKU,
    PRODUCT_NAME,
    LIST_PRICE,
    IS_ACTIVE,
    _DMS_OPERATION,
    _DMS_COMMIT_TS,
    _LOADED_AT,
    _SOURCE_DB
FROM source
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY PRODUCT_ID
    ORDER BY _EFFECTIVE_TS DESC, _LOADED_AT DESC
) = 1
