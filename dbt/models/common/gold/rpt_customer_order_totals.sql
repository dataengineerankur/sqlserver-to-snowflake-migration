{{
    config(
        materialized = 'table',
        schema       = 'GOLD'
    )
}}
-- ============================================================
-- Replaces: SnowConvertStressDB.dbo.vw_CustomerOrderTotals
-- Original: GROUP BY customer with COUNT orders + SUM totals
-- Migration note: materialised as a table so BI tools can index it;
--   refresh on each dbt run (full table rebuild from current Silver data)
-- ============================================================

SELECT
    c.CUSTOMER_ID,
    c.CUSTOMER_CODE,
    c.FULL_NAME,
    c.EMAIL,
    c.COUNTRY,
    COUNT(DISTINCT o.ORDER_ID)   AS ORDER_COUNT,
    COALESCE(SUM(o.TOTAL_AMOUNT), 0)  AS SUM_ORDER_TOTALS,
    MAX(o.ORDER_DATE)            AS LAST_ORDER_DATE,
    MIN(o.ORDER_DATE)            AS FIRST_ORDER_DATE,
    -- formatted via macro (replaces fn_FormatMoney UDF)
    {{ fn_format_money('COALESCE(SUM(o.TOTAL_AMOUNT), 0)') }} AS SUM_ORDER_TOTALS_FMT

FROM {{ ref('int_customers') }}  c
LEFT JOIN {{ ref('int_orders') }} o ON o.CUSTOMER_ID = c.CUSTOMER_ID

GROUP BY
    c.CUSTOMER_ID,
    c.CUSTOMER_CODE,
    c.FULL_NAME,
    c.EMAIL,
    c.COUNTRY
