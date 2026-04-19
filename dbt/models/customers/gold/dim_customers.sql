{{ config(materialized = 'table') }}

/*
  Gold: current customer dimension.
  Source: int_customers (current records from SCD2 snapshot).
  Replaces SQL Server vw_CustomerOrderTotals concept — order counts
  are in fct_orders; this dim carries only customer attributes.
*/

SELECT
    CUSTOMER_ID,
    CUSTOMER_CODE,
    FULL_NAME,
    EMAIL,
    COUNTRY,
    CREATED_AT,
    _VALID_FROM,
    _LAST_CHANGED_AT,
    _SOURCE_DB
FROM {{ ref('int_customers') }}
