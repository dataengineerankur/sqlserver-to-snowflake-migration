/*
  Intermediate: current CRM account records from SCD2 snapshot.
*/

SELECT
    ACCOUNT_ID,
    ACCOUNT_CODE,
    NAME,
    REGION,
    CREATED_AT,
    _SOURCE_DB,
    dbt_valid_from  AS _VALID_FROM,
    dbt_updated_at  AS _LAST_CHANGED_AT
FROM {{ ref('snp_crm_accounts') }}
WHERE dbt_valid_to IS NULL
