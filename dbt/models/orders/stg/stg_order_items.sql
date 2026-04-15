/*
  Staging: BRONZE.ORDER_ITEMS → deduplication.
  OrderItems are append-only (no updates) — dedup is a safety net only.
  LINE_TOTAL is already computed in BRONZE (QUANTITY * UNIT_PRICE persisted).
*/

WITH source AS (
    SELECT
        ORDER_ITEM_ID,
        ORDER_ID,
        PRODUCT_ID,
        QUANTITY,
        UNIT_PRICE,
        LINE_TOTAL,
        _DMS_OPERATION,
        _DMS_COMMIT_TS,
        _LOADED_AT,
        _SOURCE_DB
    FROM {{ source('bronze', 'order_items') }}
    WHERE _DMS_OPERATION IS NULL OR _DMS_OPERATION != 'D'
)

SELECT
    ORDER_ITEM_ID,
    ORDER_ID,
    PRODUCT_ID,
    QUANTITY,
    UNIT_PRICE,
    -- recompute in case BRONZE LINE_TOTAL is NULL (DMS can null computed cols)
    COALESCE(LINE_TOTAL, QUANTITY * UNIT_PRICE) AS LINE_TOTAL,
    _DMS_COMMIT_TS,
    _LOADED_AT,
    _SOURCE_DB
FROM source
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY ORDER_ITEM_ID
    ORDER BY _LOADED_AT DESC
) = 1
