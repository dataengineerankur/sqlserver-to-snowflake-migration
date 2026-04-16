{{
    config(
        materialized = 'view',
        schema       = 'GOLD'
    )
}}
-- ============================================================
-- Replaces: SnowConvertStressDB.dbo.vw_OrderLineDetail
-- Original: plain SELECT join across Orders/Customers/Products/Categories
-- Migration note: direct view equivalent — no T-SQL syntax changes needed
-- ============================================================

SELECT
    o.ORDER_ID,
    o.ORDER_DATE,
    o.STATUS,
    c.CUSTOMER_CODE,
    c.FULL_NAME                        AS CUSTOMER_NAME,
    p.SKU,
    p.PRODUCT_NAME,
    oi.QUANTITY,
    oi.UNIT_PRICE,
    oi.LINE_TOTAL,
    cat.CATEGORY_NAME,
    -- bonus: formatted money via macro (replaces fn_FormatMoney UDF)
    {{ fn_format_money('oi.LINE_TOTAL') }} AS LINE_TOTAL_FMT

FROM {{ ref('int_order_items') }}    oi
JOIN {{ ref('int_orders') }}          o   ON o.ORDER_ID  = oi.ORDER_ID
JOIN {{ ref('int_customers') }}       c   ON c.CUSTOMER_ID = o.CUSTOMER_ID
JOIN {{ ref('int_products') }}        p   ON p.PRODUCT_ID  = oi.PRODUCT_ID
JOIN {{ source('bronze', 'categories') }} cat ON cat.CATEGORY_ID = p.CATEGORY_ID
