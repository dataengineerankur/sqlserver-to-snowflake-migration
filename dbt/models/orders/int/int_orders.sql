/*
  Intermediate: current order state from the SCD Type-2 snapshot.
  snp_orders tracks status transitions (Open → Closed) and total recalculations.
  Joins to int_customers to enrich with customer name/email for downstream gold.
*/

SELECT
    o.ORDER_ID,
    o.CUSTOMER_ID,
    c.FULL_NAME       AS CUSTOMER_NAME,
    c.EMAIL           AS CUSTOMER_EMAIL,
    c.COUNTRY         AS CUSTOMER_COUNTRY,
    o.ORDER_DATE,
    o.STATUS,
    o.TOTAL_AMOUNT,
    o.NOTES,
    o._SOURCE_DB,
    o.dbt_valid_from  AS _VALID_FROM,
    o.dbt_updated_at  AS _LAST_CHANGED_AT
FROM {{ ref('snp_orders') }} AS o
LEFT JOIN {{ ref('int_customers') }} AS c
    ON o.CUSTOMER_ID = c.CUSTOMER_ID
WHERE o.dbt_valid_to IS NULL
