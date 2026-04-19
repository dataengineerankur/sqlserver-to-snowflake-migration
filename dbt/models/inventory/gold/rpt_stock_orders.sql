{{
    config(
        materialized = 'view',
        schema       = 'GOLD'
    )
}}
-- ============================================================
-- Replaces: LabInventory_DB.dbo.vw_StockOrders
-- Original: SELECT MovId, WhId, SkuId, QtyChange, Reason, MovDate
--           FROM dbo.StockMovements
-- Original INSTEAD OF INSERT trigger (tr_vw_StockOrders_IOI):
--   → Not possible in dbt; replaced by a Snowflake Stored Procedure
--     snowflake_ddl/procedures/sp_insert_stock_order.sql (created separately)
--   → For direct Snowflake inserts, write to BRONZE.INV_STOCK_MOVEMENTS
--     which Snowpipe / DMS populates; this view is read-only.
-- ============================================================

SELECT
    m.MOV_ID,
    m.WH_ID,
    w.WH_CODE,
    w.LOCATION                          AS WH_LOCATION,
    m.SKU_ID,
    s.SKU_CODE,
    s.DESCR                             AS SKU_DESCRIPTION,
    m.QTY_CHANGE,
    m.REASON,
    m.MOV_DATE,
    -- computed: movement value at current unit cost
    m.QTY_CHANGE * s.UNIT_COST          AS MOVEMENT_VALUE_USD

FROM {{ ref('int_inv_stock_movements') }}  m
JOIN {{ source('bronze', 'inv_warehouses') }} w ON w.WH_ID = m.WH_ID
JOIN {{ ref('snp_inv_sku') }}              s ON s.SKU_ID = m.SKU_ID
                                            AND s.dbt_valid_to IS NULL  -- current cost
