{% snapshot snp_crm_accounts %}

{{
    config(
        target_schema = 'SILVER',
        unique_key     = 'ACCOUNT_ID',
        strategy       = 'check',
        check_cols     = ['NAME', 'REGION'],
        invalidate_hard_deletes = true
    )
}}

/*
  SCD Type-2 snapshot for CRM Accounts.
  Tracks: account renames, region reassignments.
*/

SELECT
    ACCOUNT_ID,
    ACCOUNT_CODE,
    NAME,
    REGION,
    CREATED_AT,
    _SOURCE_DB
FROM {{ ref('stg_crm_accounts') }}

{% endsnapshot %}
