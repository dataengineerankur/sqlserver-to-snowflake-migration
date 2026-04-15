{{ config(
    materialized         = 'incremental',
    unique_key           = 'ORDER_ID',
    incremental_strategy = 'merge'
) }}

/*
  Gold: order fact with enriched analytics fields.
  Source: int_orders_enriched (snapshot-backed, current state only).
  Includes line-level aggregates joined from int_order_items.
  Replaces SQL Server vw_OrderLineDetail + usp_RefreshOrderTotals.
*/

WITH items AS (
    SELECT
        ORDER_ID,
        COUNT(*)        AS LINE_COUNT,
        SUM(QUANTITY)   AS TOTAL_QUANTITY,
        SUM(LINE_TOTAL) AS GROSS_REVENUE
    FROM {{ ref('int_order_items') }}
    GROUP BY ORDER_ID
)

SELECT
    o.ORDER_ID,
    o.CUSTOMER_ID,
    o.CUSTOMER_NAME,
    o.CUSTOMER_EMAIL,
    o.CUSTOMER_COUNTRY,
    TO_CHAR(o.ORDER_DATE, 'YYYY-MM')        AS ORDER_MONTH,
    o.ORDER_DATE,
    o.STATUS,
    o.TOTAL_AMOUNT,
    o.ORDER_VALUE_TIER,
    o.IS_REPEAT_CUSTOMER,
    o.DAYS_TO_SHIP,
    COALESCE(i.LINE_COUNT, 0)               AS LINE_COUNT,
    COALESCE(i.TOTAL_QUANTITY, 0)           AS TOTAL_QUANTITY,
    COALESCE(i.GROSS_REVENUE, 0)            AS GROSS_REVENUE,
    o._VALID_FROM,
    o._LAST_CHANGED_AT                      AS _UPDATED_AT,
    o._SOURCE_DB
FROM {{ ref('int_orders_enriched') }} AS o
LEFT JOIN items AS i ON o.ORDER_ID = i.ORDER_ID

{% if is_incremental() %}
WHERE o._LAST_CHANGED_AT > (
    SELECT COALESCE(MAX(_UPDATED_AT), '1970-01-01') FROM {{ this }}
)
{% endif %}
