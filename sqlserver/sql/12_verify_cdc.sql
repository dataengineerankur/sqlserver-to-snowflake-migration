-- Standalone CDC verification. Run after 11_enable_cdc.sql.
-- Checks: CDC enabled on each database, each table tracked, SQL Server Agent running.

-- ── Database-level CDC status ─────────────────────────────────────────────────
SELECT name, is_cdc_enabled
FROM sys.databases
WHERE name IN ('SnowConvertStressDB','LabERP_DB','LabCRM_DB','LabInventory_DB')
ORDER BY name;

-- ── Table-level CDC status: SnowConvertStressDB ───────────────────────────────
USE [SnowConvertStressDB];
SELECT
    t.name              AS table_name,
    t.is_tracked_by_cdc,
    ct.capture_instance
FROM sys.tables t
LEFT JOIN cdc.change_tables ct ON t.object_id = ct.source_object_id
WHERE t.name IN ('Categories','Customers','Products','Orders','OrderItems')
ORDER BY t.name;

-- ── Table-level CDC status: LabERP_DB ─────────────────────────────────────────
USE [LabERP_DB];
SELECT
    t.name              AS table_name,
    t.is_tracked_by_cdc,
    ct.capture_instance
FROM sys.tables t
LEFT JOIN cdc.change_tables ct ON t.object_id = ct.source_object_id
WHERE t.name IN ('Departments','Employees','PayrollRuns','PayrollLines')
ORDER BY t.name;

-- ── Table-level CDC status: LabCRM_DB ─────────────────────────────────────────
USE [LabCRM_DB];
SELECT
    t.name              AS table_name,
    t.is_tracked_by_cdc,
    ct.capture_instance
FROM sys.tables t
LEFT JOIN cdc.change_tables ct ON t.object_id = ct.source_object_id
WHERE t.name IN ('Accounts','Contacts','Opportunities')
ORDER BY t.name;

-- ── Table-level CDC status: LabInventory_DB ───────────────────────────────────
USE [LabInventory_DB];
SELECT
    t.name              AS table_name,
    t.is_tracked_by_cdc,
    ct.capture_instance
FROM sys.tables t
LEFT JOIN cdc.change_tables ct ON t.object_id = ct.source_object_id
WHERE t.name IN ('Warehouses','Sku','StockMovements')
ORDER BY t.name;

-- ── SQL Server Agent state ────────────────────────────────────────────────────
-- CDC capture and cleanup jobs require Agent to be running.
EXEC xp_servicecontrol 'QUERYSTATE', 'SQLSERVERAGENT';
