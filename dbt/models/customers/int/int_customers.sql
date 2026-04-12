{{ config(
    materialized = 'incremental',
    incremental_strategy = 'merge',
    unique_key = 'customer_id',
    on_schema_change = 'append_new_columns'
) }}

SELECT
  CUSTOMER_ID,
  FIRST_NAME,
  LAST_NAME,
  EMAIL,
  CREATED_AT,
  UPDATED_AT,
  DMS_COMMIT_TS,
  DMS_LOAD_TS,
  DMS_FILE_NAME
FROM {{ ref('stg_customers') }}
