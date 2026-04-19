{{ config(materialized = 'table') }}

/*
  Gold: current product dimension.
  Source: int_products (current records from SCD2 snapshot).
  Price history is preserved in SILVER.SNP_PRODUCTS (full snapshot table).
*/

SELECT
    p.PRODUCT_ID,
    p.SKU,
    p.PRODUCT_NAME,
    p.LIST_PRICE,
    p.IS_ACTIVE,
    p.CATEGORY_ID,
    c.CATEGORY_NAME,
    c.DESCRIPTION    AS CATEGORY_DESCRIPTION,
    p._VALID_FROM,
    p._LAST_CHANGED_AT,
    p._SOURCE_DB
FROM {{ ref('int_products') }} AS p
LEFT JOIN {{ source('bronze', 'categories') }} AS c
    ON p.CATEGORY_ID = c.CATEGORY_ID
    AND (c._DMS_OPERATION IS NULL OR c._DMS_OPERATION != 'D')
