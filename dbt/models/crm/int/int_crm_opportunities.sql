/*
  Intermediate: current opportunity state from SCD2 snapshot.
  Joins to int_crm_accounts for region + account name.
  Full stage history lives in SILVER.SNP_CRM_OPPORTUNITIES.
*/

SELECT
    o.OPP_ID,
    o.ACCOUNT_ID,
    a.NAME          AS ACCOUNT_NAME,
    a.REGION,
    o.TITLE,
    o.STAGE,
    o.AMOUNT_USD,
    o.CLOSE_DATE,
    o._SOURCE_DB,
    o.dbt_valid_from AS _VALID_FROM,
    o.dbt_updated_at AS _LAST_CHANGED_AT
FROM {{ ref('snp_crm_opportunities') }} AS o
LEFT JOIN {{ ref('int_crm_accounts') }} AS a
    ON o.ACCOUNT_ID = a.ACCOUNT_ID
WHERE o.dbt_valid_to IS NULL
