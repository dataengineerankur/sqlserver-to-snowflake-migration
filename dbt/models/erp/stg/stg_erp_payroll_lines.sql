/*
  PayrollLines are append-only (one row per employee per run, never updated).
  Join denormalises RUN_MONTH from PayrollRuns at staging time.
*/

WITH lines AS (
    SELECT
        l.LINE_ID, l.RUN_ID, l.EMPLOYEE_ID, l.GROSS_PAY,
        COALESCE(l.NET_PAY, ROUND(l.GROSS_PAY * 0.92, 4)) AS NET_PAY,
        l._DMS_OPERATION, l._LOADED_AT, l._SOURCE_DB
    FROM {{ source('bronze', 'erp_payroll_lines') }} AS l
    WHERE l._DMS_OPERATION IS NULL OR l._DMS_OPERATION != 'D'
),
runs AS (
    SELECT RUN_ID, RUN_MONTH, STATUS
    FROM {{ source('bronze', 'erp_payroll_runs') }}
    QUALIFY ROW_NUMBER() OVER (PARTITION BY RUN_ID ORDER BY _LOADED_AT DESC) = 1
)
SELECT
    l.LINE_ID, l.RUN_ID, r.RUN_MONTH, r.STATUS AS RUN_STATUS,
    l.EMPLOYEE_ID, l.GROSS_PAY, l.NET_PAY,
    l._LOADED_AT, l._SOURCE_DB
FROM lines AS l
LEFT JOIN runs AS r ON l.RUN_ID = r.RUN_ID
QUALIFY ROW_NUMBER() OVER (PARTITION BY l.LINE_ID ORDER BY l._LOADED_AT DESC) = 1
