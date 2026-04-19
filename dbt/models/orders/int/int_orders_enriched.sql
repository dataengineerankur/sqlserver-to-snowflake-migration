/*
  Intermediate: orders with derived analytics fields.
  Extends int_orders with:
    DAYS_TO_SHIP      — NULL until status = 'Closed', then days from order to close
    ORDER_VALUE_TIER  — LOW / MEDIUM / HIGH bracket
    IS_REPEAT_CUSTOMER — TRUE if customer had prior orders
  Used by fct_orders gold model and any downstream ML pipelines.
*/

WITH order_history AS (
    SELECT
        CUSTOMER_ID,
        ORDER_DATE,
        COUNT(*) OVER (
            PARTITION BY CUSTOMER_ID
            ORDER BY ORDER_DATE
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS PRIOR_ORDER_COUNT
    FROM {{ ref('snp_orders') }}
    WHERE dbt_valid_to IS NULL
)

SELECT
    o.ORDER_ID,
    o.CUSTOMER_ID,
    o.CUSTOMER_NAME,
    o.CUSTOMER_EMAIL,
    o.CUSTOMER_COUNTRY,
    o.ORDER_DATE,
    o.STATUS,
    o.TOTAL_AMOUNT,
    o._SOURCE_DB,

    CASE
        WHEN o.STATUS = 'Closed'
        THEN DATEDIFF('day', o.ORDER_DATE, o._LAST_CHANGED_AT::DATE)
        ELSE NULL
    END                                                 AS DAYS_TO_SHIP,

    CASE
        WHEN o.TOTAL_AMOUNT < 100  THEN 'LOW'
        WHEN o.TOTAL_AMOUNT < 500  THEN 'MEDIUM'
        ELSE                            'HIGH'
    END                                                 AS ORDER_VALUE_TIER,

    COALESCE(h.PRIOR_ORDER_COUNT, 0) > 0                AS IS_REPEAT_CUSTOMER,

    o._VALID_FROM,
    o._LAST_CHANGED_AT

FROM {{ ref('int_orders') }} AS o
LEFT JOIN order_history AS h
    ON o.CUSTOMER_ID = h.CUSTOMER_ID
    AND o.ORDER_DATE  = h.ORDER_DATE
