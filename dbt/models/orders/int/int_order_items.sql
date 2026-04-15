/*
  Intermediate: order items enriched with product info.
  OrderItems are append-only — no snapshot needed, incremental append is correct.
  Joins to int_products (current product state at query time).
*/

{{ config(
    materialized           = 'incremental',
    incremental_strategy   = 'append',
    unique_key             = 'ORDER_ITEM_ID'
) }}

SELECT
    i.ORDER_ITEM_ID,
    i.ORDER_ID,
    i.PRODUCT_ID,
    p.SKU,
    p.PRODUCT_NAME,
    p.CATEGORY_ID,
    i.QUANTITY,
    i.UNIT_PRICE,
    i.LINE_TOTAL,
    i._LOADED_AT
FROM {{ ref('stg_order_items') }} AS i
LEFT JOIN {{ ref('int_products') }} AS p
    ON i.PRODUCT_ID = p.PRODUCT_ID

{% if is_incremental() %}
WHERE i._LOADED_AT > (SELECT COALESCE(MAX(_LOADED_AT), '1970-01-01') FROM {{ this }})
{% endif %}
