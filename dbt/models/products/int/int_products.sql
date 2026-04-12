{{ config(
    materialized = 'incremental',
    incremental_strategy = 'merge',
    unique_key = 'product_id',
    on_schema_change = 'append_new_columns'
) }}

SELECT
  PRODUCT_ID,
  SKU,
  PRODUCT_NAME,
  CATEGORY,
  PRICE,
  CREATED_AT,
  UPDATED_AT,
  DMS_COMMIT_TS,
  DMS_LOAD_TS,
  DMS_FILE_NAME
FROM {{ ref('stg_products') }}
