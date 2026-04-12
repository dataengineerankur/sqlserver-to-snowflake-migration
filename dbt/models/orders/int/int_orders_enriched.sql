{{ config(
    materialized = 'incremental',
    incremental_strategy = 'merge',
    unique_key = 'order_id',
    on_schema_change = 'append_new_columns'
) }}

/*
  Enriched orders intermediate model.
  Adds derived fields used by both fct_orders (gold) and any downstream ML pipelines:
    - days_to_ship: NULL until ORDER_STATUS = 'shipped'
    - order_value_tier: LOW / MEDIUM / HIGH based on total_amount brackets
    - is_repeat_customer: TRUE if the customer had a prior order
*/

WITH base AS (
    SELECT
        o.ORDER_ID,
        o.CUSTOMER_ID,
        c.FIRST_NAME,
        c.LAST_NAME,
        c.EMAIL,
        o.ORDER_STATUS,
        o.ORDER_DATE,
        o.ORDER_UPDATED_AT,
        o.TOTAL_AMOUNT
    FROM {{ ref('stg_orders') }}    AS o
    LEFT JOIN {{ ref('stg_customers') }} AS c
        ON o.CUSTOMER_ID = c.CUSTOMER_ID
),

order_history AS (
    SELECT
        CUSTOMER_ID,
        ORDER_DATE,
        COUNT(*) OVER (
            PARTITION BY CUSTOMER_ID
            ORDER BY ORDER_DATE
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prior_order_count
    FROM {{ ref('stg_orders') }}
)

SELECT
    b.ORDER_ID,
    b.CUSTOMER_ID,
    b.FIRST_NAME,
    b.LAST_NAME,
    b.EMAIL,
    b.ORDER_STATUS,
    b.ORDER_DATE,
    b.ORDER_UPDATED_AT,
    b.TOTAL_AMOUNT,

    CASE
        WHEN b.ORDER_STATUS = 'shipped'
        THEN DATEDIFF('day', b.ORDER_DATE, b.ORDER_UPDATED_AT)
        ELSE NULL
    END                                                    AS DAYS_TO_SHIP,

    CASE
        WHEN b.TOTAL_AMOUNT < 100   THEN 'LOW'
        WHEN b.TOTAL_AMOUNT < 500   THEN 'MEDIUM'
        ELSE                             'HIGH'
    END                                                    AS ORDER_VALUE_TIER,

    COALESCE(h.prior_order_count, 0) > 0                   AS IS_REPEAT_CUSTOMER,

    CURRENT_TIMESTAMP()                                    AS _DBT_UPDATED_AT

FROM base AS b
LEFT JOIN order_history AS h
    ON b.ORDER_ID = h.CUSTOMER_ID   -- keyed on CUSTOMER_ID for the window lookup
   AND b.ORDER_DATE = h.ORDER_DATE
