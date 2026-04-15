{{ config(
    materialized         = 'incremental',
    unique_key           = ['WH_CODE', 'SKU_CODE'],
    incremental_strategy = 'merge'
) }}

/*
  Gold: current stock position per warehouse + SKU.
  Computed as SUM of all movements (positive = inbound, negative = outbound).
  Replaces GOLD.FACT_INVENTORY_POSITION + SILVER.INV_STOCK_BALANCE.
*/

SELECT
    WH_CODE,
    WH_LOCATION,
    SKU_CODE,
    SKU_DESCRIPTION,
    UNIT_COST,
    SUM(QTY_CHANGE)                    AS CURRENT_QTY,
    SUM(QTY_CHANGE) * MAX(UNIT_COST)   AS STOCK_VALUE_USD,
    MAX(_LOADED_AT)                    AS _LOADED_AT,
    MAX(_SOURCE_DB)                    AS _SOURCE_DB
FROM {{ ref('int_inv_stock_movements') }}
GROUP BY WH_CODE, WH_LOCATION, SKU_CODE, SKU_DESCRIPTION, UNIT_COST

{% if is_incremental() %}
HAVING MAX(_LOADED_AT) > (
    SELECT COALESCE(MAX(_LOADED_AT), '1970-01-01') FROM {{ this }}
)
{% endif %}
