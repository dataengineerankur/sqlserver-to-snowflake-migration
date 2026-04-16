{{
    config(
        materialized = 'table',
        schema       = 'GOLD'
    )
}}
-- ============================================================
-- DIM_DATE — calendar dimension covering 2020-01-01 → 2034-12-31
-- Replaces: SQL Server manual DIM_DATE population (was ❌ Not done)
-- Generated entirely in Snowflake using GENERATOR — no seed CSV needed.
-- ============================================================

WITH date_spine AS (
    SELECT
        DATEADD(DAY, SEQ4(), '2020-01-01'::DATE) AS CALENDAR_DATE
    FROM TABLE(GENERATOR(ROWCOUNT => 5479))  -- 15 years = 5479 days
),

enriched AS (
    SELECT
        CALENDAR_DATE,

        -- surrogate key: YYYYMMDD integer
        TO_NUMBER(TO_CHAR(CALENDAR_DATE, 'YYYYMMDD'))       AS DATE_SK,

        -- calendar attributes
        YEAR(CALENDAR_DATE)                                  AS YEAR_NUM,
        QUARTER(CALENDAR_DATE)                               AS QUARTER_NUM,
        'Q' || QUARTER(CALENDAR_DATE)                        AS QUARTER_NAME,
        MONTH(CALENDAR_DATE)                                 AS MONTH_NUM,
        TO_CHAR(CALENDAR_DATE, 'Mon')                        AS MONTH_SHORT_NAME,
        TO_CHAR(CALENDAR_DATE, 'MMMM')                       AS MONTH_LONG_NAME,
        DAYOFMONTH(CALENDAR_DATE)                            AS DAY_OF_MONTH,
        DAYOFWEEK(CALENDAR_DATE)                             AS DAY_OF_WEEK,   -- 0=Sun
        DAYOFYEAR(CALENDAR_DATE)                             AS DAY_OF_YEAR,
        WEEKOFYEAR(CALENDAR_DATE)                            AS WEEK_OF_YEAR,

        -- fiscal periods (Jan-01 fiscal year — adjust offset if needed)
        YEAR(CALENDAR_DATE)                                  AS FISCAL_YEAR,
        QUARTER(CALENDAR_DATE)                               AS FISCAL_QUARTER,
        MONTH(CALENDAR_DATE)                                 AS FISCAL_MONTH,

        -- descriptive
        TO_CHAR(CALENDAR_DATE, 'YYYY-MM')                    AS YEAR_MONTH,    -- 'YYYY-MM'
        TO_CHAR(CALENDAR_DATE, 'YYYY-"W"WW')                 AS YEAR_WEEK,     -- 'YYYY-W01'
        DAYNAME(CALENDAR_DATE)                               AS DAY_NAME,      -- 'Monday'

        -- flags
        IFF(DAYOFWEEK(CALENDAR_DATE) IN (0, 6), TRUE, FALSE) AS IS_WEEKEND,
        IFF(DAYOFWEEK(CALENDAR_DATE) IN (0, 6), FALSE, TRUE) AS IS_WEEKDAY,

        -- first / last day helpers
        DATE_TRUNC('MONTH', CALENDAR_DATE)                   AS FIRST_DAY_OF_MONTH,
        LAST_DAY(CALENDAR_DATE)                              AS LAST_DAY_OF_MONTH,
        DATE_TRUNC('QUARTER', CALENDAR_DATE)                 AS FIRST_DAY_OF_QUARTER,
        DATE_TRUNC('YEAR', CALENDAR_DATE)                    AS FIRST_DAY_OF_YEAR

    FROM date_spine
)

SELECT * FROM enriched
