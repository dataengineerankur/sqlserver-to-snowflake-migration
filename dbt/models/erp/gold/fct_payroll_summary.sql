{{ config(
    materialized         = 'incremental',
    unique_key           = ['RUN_MONTH', 'DEPT_CODE'],
    incremental_strategy = 'merge'
) }}

/*
  Gold: payroll summary by month and department.
  Replaces GOLD.FACT_PAYROLL_SUMMARY (hand-crafted DDL now driven by dbt).
*/

SELECT
    RUN_MONTH,
    DEPT_CODE,
    DEPT_NAME,
    COUNT(DISTINCT EMPLOYEE_ID)  AS EMPLOYEE_COUNT,
    SUM(GROSS_PAY)               AS TOTAL_GROSS_PAY,
    SUM(NET_PAY)                 AS TOTAL_NET_PAY,
    MAX(_LOADED_AT)              AS _LOADED_AT,
    MAX(_SOURCE_DB)              AS _SOURCE_DB
FROM {{ ref('int_erp_payroll_lines') }}
GROUP BY RUN_MONTH, DEPT_CODE, DEPT_NAME

{% if is_incremental() %}
HAVING MAX(_LOADED_AT) > (
    SELECT COALESCE(MAX(_LOADED_AT), '1970-01-01') FROM {{ this }}
)
{% endif %}
