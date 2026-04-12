{{ config(
    materialized = 'incremental',
    unique_key = 'order_item_id',
    incremental_strategy = 'merge',
    on_schema_change = 'append_new_columns'
) }}

WITH final AS (
  SELECT
    ORDER_ITEM_ID,
    ORDER_ID,
    CUSTOMER_ID,
    PRODUCT_ID,
    SKU,
    PRODUCT_NAME,
    CATEGORY,
    QUANTITY,
    UNIT_PRICE,
    LINE_TOTAL,
    ORDER_DATE,
    ITEM_UPDATED_AT AS RECORD_UPDATED_AT
  FROM {{ ref('int_order_items') }}
)

SELECT * FROM final

{% if is_incremental() %}
WHERE RECORD_UPDATED_AT >= DATEADD(
  day,
  -{{ var('fct_orders_lookback_days') }},
  (SELECT COALESCE(MAX(RECORD_UPDATED_AT), '1970-01-01') FROM {{ this }})
)
{% endif %}
