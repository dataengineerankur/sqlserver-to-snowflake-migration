{{ config(
    materialized         = 'incremental',
    unique_key           = 'ORDER_ITEM_ID',
    incremental_strategy = 'append'
) }}

/*
  Gold: order line item fact.
  Source: int_order_items (already enriched with product info).
  Replaces SQL Server vw_OrderLineDetail.
  Append-only: order items never change once created.
*/

SELECT
    i.ORDER_ITEM_ID,
    i.ORDER_ID,
    o.CUSTOMER_ID,
    o.CUSTOMER_NAME,
    o.CUSTOMER_COUNTRY,
    o.ORDER_DATE,
    TO_CHAR(o.ORDER_DATE, 'YYYY-MM')  AS ORDER_MONTH,
    i.PRODUCT_ID,
    i.SKU,
    i.PRODUCT_NAME,
    i.CATEGORY_ID,
    d.CATEGORY_NAME,
    i.QUANTITY,
    i.UNIT_PRICE,
    i.LINE_TOTAL,
    i._LOADED_AT
FROM {{ ref('int_order_items') }} AS i
LEFT JOIN {{ ref('int_orders') }} AS o
    ON i.ORDER_ID = o.ORDER_ID
LEFT JOIN {{ source('bronze', 'categories') }} AS d
    ON i.CATEGORY_ID = d.CATEGORY_ID
    AND (d._DMS_OPERATION IS NULL OR d._DMS_OPERATION != 'D')

{% if is_incremental() %}
WHERE i._LOADED_AT > (
    SELECT COALESCE(MAX(_LOADED_AT), '1970-01-01') FROM {{ this }}
)
{% endif %}
