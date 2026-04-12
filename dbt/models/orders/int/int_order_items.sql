{{ config(
    materialized = 'incremental',
    incremental_strategy = 'merge',
    unique_key = 'order_item_id',
    on_schema_change = 'append_new_columns'
) }}

SELECT
  items.ORDER_ITEM_ID,
  items.ORDER_ID,
  items.PRODUCT_ID,
  products.SKU,
  products.PRODUCT_NAME,
  products.CATEGORY,
  items.QUANTITY,
  items.UNIT_PRICE,
  items.LINE_TOTAL,
  orders.CUSTOMER_ID,
  orders.ORDER_DATE,
  items.ITEM_UPDATED_AT
FROM {{ ref('stg_order_items') }} AS items
LEFT JOIN {{ ref('stg_products') }} AS products
  ON items.PRODUCT_ID = products.PRODUCT_ID
LEFT JOIN {{ ref('stg_orders') }} AS orders
  ON items.ORDER_ID = orders.ORDER_ID
