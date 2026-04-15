{{ config(materialized = 'table') }}

/*
  Gold: pipeline observability — row counts per bronze table per run.
  Updated on every dbt run. Used by the GOLD.MIGRATION_METADATA table
  populated by Airflow.
*/

SELECT CURRENT_TIMESTAMP()  AS RUN_TS, 'CUSTOMERS'    AS TABLE_NAME,
       COUNT(*)              AS ROW_COUNT,
       MAX(_DMS_COMMIT_TS)   AS MAX_DMS_COMMIT_TS,
       MAX(_LOADED_AT)       AS MAX_LOADED_AT
FROM {{ source('bronze', 'customers') }}

UNION ALL

SELECT CURRENT_TIMESTAMP(), 'PRODUCTS',
       COUNT(*), MAX(_DMS_COMMIT_TS), MAX(_LOADED_AT)
FROM {{ source('bronze', 'products') }}

UNION ALL

SELECT CURRENT_TIMESTAMP(), 'ORDERS',
       COUNT(*), MAX(_DMS_COMMIT_TS), MAX(_LOADED_AT)
FROM {{ source('bronze', 'orders') }}

UNION ALL

SELECT CURRENT_TIMESTAMP(), 'ORDER_ITEMS',
       COUNT(*), MAX(_DMS_COMMIT_TS), MAX(_LOADED_AT)
FROM {{ source('bronze', 'order_items') }}

UNION ALL

SELECT CURRENT_TIMESTAMP(), 'ERP_EMPLOYEES',
       COUNT(*), MAX(_DMS_COMMIT_TS), MAX(_LOADED_AT)
FROM {{ source('bronze', 'erp_employees') }}

UNION ALL

SELECT CURRENT_TIMESTAMP(), 'CRM_OPPORTUNITIES',
       COUNT(*), MAX(_DMS_COMMIT_TS), MAX(_LOADED_AT)
FROM {{ source('bronze', 'crm_opportunities') }}

UNION ALL

SELECT CURRENT_TIMESTAMP(), 'INV_STOCK_MOVEMENTS',
       COUNT(*), MAX(_DMS_COMMIT_TS), MAX(_LOADED_AT)
FROM {{ source('bronze', 'inv_stock_movements') }}
