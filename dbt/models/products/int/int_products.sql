/*
  Intermediate: current product records from the SCD Type-2 snapshot.
  snp_products tracks price changes — the full history lives in SILVER.SNP_PRODUCTS.
  This model exposes only the current (latest) version per product.
*/

SELECT
    PRODUCT_ID,
    CATEGORY_ID,
    SKU,
    PRODUCT_NAME,
    LIST_PRICE,
    IS_ACTIVE,
    _SOURCE_DB,
    dbt_valid_from  AS _VALID_FROM,
    dbt_updated_at  AS _LAST_CHANGED_AT
FROM {{ ref('snp_products') }}
WHERE dbt_valid_to IS NULL
