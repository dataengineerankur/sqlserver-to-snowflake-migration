/*
  StockMovements are immutable journal entries — append-only.
  Dedup is a safety net only.
*/

WITH source AS (
    SELECT
        MOV_ID, WH_ID, SKU_ID, QTY_CHANGE, REASON, MOV_DATE,
        _DMS_OPERATION, _LOADED_AT, _SOURCE_DB
    FROM {{ source('bronze', 'inv_stock_movements') }}
    WHERE _DMS_OPERATION IS NULL OR _DMS_OPERATION != 'D'
)
SELECT MOV_ID, WH_ID, SKU_ID, QTY_CHANGE, REASON, MOV_DATE, _LOADED_AT, _SOURCE_DB
FROM source
QUALIFY ROW_NUMBER() OVER (PARTITION BY MOV_ID ORDER BY _LOADED_AT DESC) = 1
