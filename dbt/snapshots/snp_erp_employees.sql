{% snapshot snp_erp_employees %}

{{
    config(
        target_schema = 'SILVER',
        unique_key     = 'EMPLOYEE_ID',
        strategy       = 'check',
        check_cols     = ['FULL_NAME', 'SALARY', 'DEPT_ID', 'HIRE_DATE'],
        invalidate_hard_deletes = true
    )
}}

/*
  SCD Type-2 snapshot for ERP Employees.
  Tracks: salary changes, department transfers, name corrections.
  Replaces SQL Server tr_Employees_Audit trigger — now async + version-safe.
*/

SELECT
    EMPLOYEE_ID,
    DEPT_ID,
    EMP_CODE,
    FULL_NAME,
    HIRE_DATE,
    SALARY,
    _SOURCE_DB
FROM {{ ref('stg_erp_employees') }}

{% endsnapshot %}
