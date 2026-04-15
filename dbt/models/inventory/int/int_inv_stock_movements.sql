{{ config(
    materialized         = 'incremental',
    incremental_strategy = 'append',
    unique_key           = 'MOV_ID'
) }}

/*
  Intermediate: stock movements enriched with warehouse + SKU info.
  Append-only — movements are immutable journal entries.
*/

SELECT
    m.MOV_ID,
    m.WH_ID,
    w.WH_CODE,
    w.LOCATION       AS WH_LOCATION,
    m.SKU_ID,
    s.SKU_CODE,
    s.DESCR          AS SKU_DESCRIPTION,
    s.UNIT_COST,
    m.QTY_CHANGE,
    m.REASON,
    m.MOV_DATE,
    m.QTY_CHANGE * s.UNIT_COST  AS MOVEMENT_VALUE_USD,
    m._LOADED_AT,
    m._SOURCE_DB
FROM {{ ref('stg_inv_stock_movements') }} AS m
LEFT JOIN {{ ref('stg_inv_warehouses') }} AS w ON m.WH_ID = w.WH_ID
LEFT JOIN {{ ref('snp_inv_sku') }} AS s
    ON m.SKU_ID = s.SKU_ID AND s.dbt_valid_to IS NULL

{% if is_incremental() %}
WHERE m._LOADED_AT > (SELECT COALESCE(MAX(_LOADED_AT), '1970-01-01') FROM {{ this }})
{% endif %}
