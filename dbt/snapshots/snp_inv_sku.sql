{% snapshot snp_inv_sku %}

{{
    config(
        target_schema = 'SILVER',
        unique_key     = 'SKU_ID',
        strategy       = 'check',
        check_cols     = ['DESCR', 'UNIT_COST'],
        invalidate_hard_deletes = true
    )
}}

/*
  SCD Type-2 snapshot for Inventory SKUs.
  Tracks: unit cost changes (key for stock valuation history),
  description updates.
*/

SELECT
    SKU_ID,
    SKU_CODE,
    DESCR,
    UNIT_COST,
    _SOURCE_DB
FROM {{ ref('stg_inv_sku') }}

{% endsnapshot %}
