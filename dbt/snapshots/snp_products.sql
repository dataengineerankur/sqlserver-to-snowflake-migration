{% snapshot snp_products %}

{{
    config(
        target_schema = 'SILVER',
        unique_key     = 'PRODUCT_ID',
        strategy       = 'check',
        check_cols     = ['PRODUCT_NAME', 'LIST_PRICE', 'IS_ACTIVE', 'CATEGORY_ID'],
        invalidate_hard_deletes = true
    )
}}

/*
  SCD Type-2 snapshot for Products.
  Tracks: price changes, product name changes, active/inactive flips.
  Price history (LIST_PRICE changes) is the key use case — replaces
  the SQL Server tr_Products_ListPriceAudit trigger.
*/

SELECT
    PRODUCT_ID,
    CATEGORY_ID,
    SKU,
    PRODUCT_NAME,
    LIST_PRICE,
    IS_ACTIVE,
    _SOURCE_DB
FROM {{ ref('stg_products') }}

{% endsnapshot %}
