{{
    config(
        materialized = 'table',
        schema       = 'GOLD'
    )
}}
-- ============================================================
-- Replaces: SnowConvertStressDB.dbo.usp_Stress_RecursiveCategoryClosure
--           + supporting table dbo.CategoryClosure
-- Original T-SQL: used a WHILE/recursive CTE with SYNTHETIC edges
--   (ABS(CHECKSUM(p.CategoryId,c.CategoryId)) % 3 = 0) — there is
--   no real parent-child column in the Categories table.
--   The stored proc was a migration-stress test, not real business logic.
--
-- Snowflake equivalent: recursive CTE with the same synthetic edge rule,
--   demonstrating Snowflake supports RECURSIVE CTEs natively.
--   Max recursion depth capped at 5 (same as original).
--
-- In a real hierarchy use case, add PARENT_CATEGORY_ID to the table
-- and use: INNER JOIN categories c ON c.PARENT_CATEGORY_ID = w.DESCENDANT_ID
-- ============================================================

WITH categories AS (
    SELECT CATEGORY_ID, CATEGORY_NAME
    FROM {{ source('bronze', 'categories') }}
),

-- Synthetic edges: same rule as original T-SQL stress proc
edges AS (
    SELECT
        p.CATEGORY_ID AS PARENT_ID,
        c.CATEGORY_ID AS CHILD_ID
    FROM categories p
    CROSS JOIN categories c
    WHERE c.CATEGORY_ID > p.CATEGORY_ID
      AND ABS(HASH(p.CATEGORY_ID, c.CATEGORY_ID)) % 3 = 0  -- equiv. to T-SQL CHECKSUM % 3
),

-- Recursive closure walk (Snowflake RECURSIVE CTE)
walk(ANCESTOR_ID, DESCENDANT_ID, DEPTH) AS (
    -- Anchor: each category is its own ancestor at depth 0
    SELECT CATEGORY_ID, CATEGORY_ID, 0
    FROM categories

    UNION ALL

    -- Recursive: follow edges one step deeper
    SELECT w.ANCESTOR_ID, e.CHILD_ID, w.DEPTH + 1
    FROM walk w
    JOIN edges e ON e.PARENT_ID = w.DESCENDANT_ID
    WHERE w.DEPTH < 5  -- cap at depth 5, same as original
),

deduped AS (
    SELECT DISTINCT ANCESTOR_ID, DESCENDANT_ID, DEPTH
    FROM walk
)

SELECT
    d.ANCESTOR_ID,
    d.DESCENDANT_ID,
    d.DEPTH,
    a.CATEGORY_NAME  AS ANCESTOR_NAME,
    c.CATEGORY_NAME  AS DESCENDANT_NAME

FROM deduped d
JOIN categories a ON a.CATEGORY_ID = d.ANCESTOR_ID
JOIN categories c ON c.CATEGORY_ID = d.DESCENDANT_ID

ORDER BY d.ANCESTOR_ID, d.DEPTH, d.DESCENDANT_ID
