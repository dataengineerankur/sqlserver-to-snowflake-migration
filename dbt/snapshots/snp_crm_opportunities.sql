{% snapshot snp_crm_opportunities %}

{{
    config(
        target_schema = 'SILVER',
        unique_key     = 'OPP_ID',
        strategy       = 'check',
        check_cols     = ['STAGE', 'AMOUNT_USD', 'CLOSE_DATE'],
        invalidate_hard_deletes = false
    )
}}

/*
  SCD Type-2 snapshot for CRM Opportunities.
  Tracks: stage progression (Prospect → Negotiation → Won/Lost),
  amount revisions, close date changes.
  This is the core CRM pipeline audit trail.
*/

SELECT
    OPP_ID,
    ACCOUNT_ID,
    TITLE,
    STAGE,
    AMOUNT_USD,
    CLOSE_DATE,
    _SOURCE_DB
FROM {{ ref('stg_crm_opportunities') }}

{% endsnapshot %}
