{{ config(
    materialized         = 'incremental',
    incremental_strategy = 'append',
    unique_key           = 'LINE_ID'
) }}

/*
  Intermediate: payroll lines enriched with current employee + department.
  Append-only — a payroll line is never modified once posted.
*/

SELECT
    p.LINE_ID,
    p.RUN_ID,
    p.RUN_MONTH,
    p.RUN_STATUS,
    p.EMPLOYEE_ID,
    e.EMP_CODE,
    e.FULL_NAME          AS EMPLOYEE_NAME,
    e.DEPT_ID,
    e.DEPT_CODE,
    e.DEPT_NAME,
    p.GROSS_PAY,
    p.NET_PAY,
    p._LOADED_AT,
    p._SOURCE_DB
FROM {{ ref('stg_erp_payroll_lines') }} AS p
LEFT JOIN {{ ref('int_erp_employees') }} AS e
    ON p.EMPLOYEE_ID = e.EMPLOYEE_ID

{% if is_incremental() %}
WHERE p._LOADED_AT > (SELECT COALESCE(MAX(_LOADED_AT), '1970-01-01') FROM {{ this }})
{% endif %}
