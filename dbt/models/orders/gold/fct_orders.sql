{{ config(
    materialized = 'incremental',
    unique_key = 'order_id',
    incremental_strategy = 'merge',
    on_schema_change = 'append_new_columns'
) }}

WITH orders AS (
  SELECT * FROM {{ ref('int_orders') }}
),
items AS (
  SELECT
    ORDER_ID,
    SUM(QUANTITY) AS TOTAL_ITEMS,
    SUM(LINE_TOTAL) AS GROSS_REVENUE,
    MAX(ITEM_UPDATED_AT) AS ITEMS_UPDATED_AT
  FROM {{ ref('int_order_items') }}
  GROUP BY ORDER_ID
),
final AS (
  SELECT
    orders.ORDER_ID,
    orders.CUSTOMER_ID,
    orders.FIRST_NAME,
    orders.LAST_NAME,
    orders.EMAIL,
    orders.ORDER_STATUS,
    orders.ORDER_DATE,
    orders.ORDER_UPDATED_AT,
    COALESCE(items.TOTAL_ITEMS, 0) AS TOTAL_ITEMS,
    COALESCE(items.GROSS_REVENUE, 0) AS GROSS_REVENUE,
    GREATEST(
      orders.ORDER_UPDATED_AT,
      COALESCE(items.ITEMS_UPDATED_AT, orders.ORDER_UPDATED_AT)
    ) AS RECORD_UPDATED_AT
  FROM orders
  LEFT JOIN items
    ON orders.ORDER_ID = items.ORDER_ID
)

SELECT * FROM final

{% if is_incremental() %}
WHERE RECORD_UPDATED_AT >= DATEADD(
  day,
  -{{ var('fct_orders_lookback_days') }},
  (SELECT COALESCE(MAX(RECORD_UPDATED_AT), '1970-01-01') FROM {{ this }})
)
{% endif %}
