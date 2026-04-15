/*
  Intermediate: current ERP employee records from SCD2 snapshot.
  Joins to stg_erp_departments for department name.
*/

SELECT
    e.EMPLOYEE_ID,
    e.EMP_CODE,
    e.FULL_NAME,
    e.HIRE_DATE,
    e.SALARY,
    e.DEPT_ID,
    d.DEPT_CODE,
    d.DEPT_NAME,
    d.BUDGET_USD     AS DEPT_BUDGET_USD,
    e._SOURCE_DB,
    e.dbt_valid_from AS _VALID_FROM,
    e.dbt_updated_at AS _LAST_CHANGED_AT
FROM {{ ref('snp_erp_employees') }} AS e
LEFT JOIN {{ ref('stg_erp_departments') }} AS d
    ON e.DEPT_ID = d.DEPT_ID
WHERE e.dbt_valid_to IS NULL
