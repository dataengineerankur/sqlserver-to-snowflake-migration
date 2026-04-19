/*
  Intermediate: current customer records from the SCD Type-2 snapshot.
  snp_customers writes to SILVER.SNP_CUSTOMERS with dbt snapshot columns.
  This model exposes only the current version (dbt_valid_to IS NULL).
  Downstream gold models always join to this view for the current state.
*/

SELECT
    CUSTOMER_ID,
    CUSTOMER_CODE,
    FULL_NAME,
    EMAIL,
    COUNTRY,
    CREATED_AT,
    _SOURCE_DB,
    dbt_valid_from  AS _VALID_FROM,
    dbt_updated_at  AS _LAST_CHANGED_AT
FROM {{ ref('snp_customers') }}
WHERE dbt_valid_to IS NULL
