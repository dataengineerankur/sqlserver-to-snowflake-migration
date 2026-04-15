{% snapshot snp_customers %}

{{
    config(
        target_schema = 'SILVER',
        unique_key     = 'CUSTOMER_ID',
        strategy       = 'check',
        check_cols     = ['FULL_NAME', 'EMAIL', 'COUNTRY'],
        invalidate_hard_deletes = true
    )
}}

/*
  SCD Type-2 snapshot for Customers.
  Source: BRONZE.CUSTOMERS (deduplicated by stg_customers).
  Tracks: name changes, email changes, country changes.
  dbt adds: dbt_scd_id, dbt_updated_at, dbt_valid_from, dbt_valid_to.
  int_customers reads WHERE dbt_valid_to IS NULL (current records only).
*/

SELECT
    CUSTOMER_ID,
    CUSTOMER_CODE,
    FULL_NAME,
    EMAIL,
    COUNTRY,
    CREATED_AT,
    _SOURCE_DB
FROM {{ ref('stg_customers') }}

{% endsnapshot %}
