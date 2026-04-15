{{ config(
    materialized         = 'incremental',
    unique_key           = ['REGION', 'STAGE'],
    incremental_strategy = 'merge'
) }}

/*
  Gold: CRM pipeline summary by region and stage.
  Replaces GOLD.FACT_CRM_PIPELINE.
*/

SELECT
    REGION,
    STAGE,
    COUNT(*)             AS OPP_COUNT,
    SUM(AMOUNT_USD)      AS TOTAL_AMOUNT_USD,
    AVG(AMOUNT_USD)      AS AVG_AMOUNT_USD,
    MAX(_LAST_CHANGED_AT) AS _UPDATED_AT,
    MAX(_SOURCE_DB)      AS _SOURCE_DB
FROM {{ ref('int_crm_opportunities') }}
GROUP BY REGION, STAGE

{% if is_incremental() %}
HAVING MAX(_LAST_CHANGED_AT) > (
    SELECT COALESCE(MAX(_UPDATED_AT), '1970-01-01') FROM {{ this }}
)
{% endif %}
