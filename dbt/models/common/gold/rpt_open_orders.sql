{{
    config(
        materialized = 'view',
        schema       = 'GOLD'
    )
}}
-- ============================================================
-- Replaces: SnowConvertStressDB.dbo.usp_ListOpenOrders
-- Original: SELECT ... FROM Orders WHERE Status = 'Open' ORDER BY OrderDate
-- Migration note: dbt view is the direct equivalent; ORDER BY omitted
--   (views have no guaranteed ordering — let BI tools sort).
--   Add a LIMIT in the consuming query if pagination is needed.
-- ============================================================

SELECT
    o.ORDER_ID,
    o.CUSTOMER_ID,
    c.CUSTOMER_CODE,
    c.FULL_NAME                            AS CUSTOMER_NAME,
    o.ORDER_DATE,
    o.STATUS,
    o.TOTAL_AMOUNT,
    {{ fn_format_money('o.TOTAL_AMOUNT') }} AS TOTAL_AMOUNT_FMT,
    o.NOTES,
    DATEDIFF(DAY, o.ORDER_DATE, CURRENT_DATE()) AS DAYS_OPEN

FROM {{ ref('int_orders') }}   o
JOIN {{ ref('int_customers') }} c ON c.CUSTOMER_ID = o.CUSTOMER_ID

WHERE o.STATUS = 'Open'
