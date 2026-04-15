{% snapshot snp_orders %}

{{
    config(
        target_schema = 'SILVER',
        unique_key     = 'ORDER_ID',
        strategy       = 'check',
        check_cols     = ['STATUS', 'TOTAL_AMOUNT', 'NOTES'],
        invalidate_hard_deletes = false
    )
}}

/*
  SCD Type-2 snapshot for Orders.
  Tracks: status transitions (Open → Closed), total amount recalculations.
  Preserves the full lifecycle of each order — replaces the SQL Server
  tr_Orders_Audit_IU trigger for status-change history.
  invalidate_hard_deletes = false: a deleted order row should stay in history.
*/

SELECT
    ORDER_ID,
    CUSTOMER_ID,
    ORDER_DATE,
    STATUS,
    TOTAL_AMOUNT,
    NOTES,
    _SOURCE_DB
FROM {{ ref('stg_orders') }}

{% endsnapshot %}
