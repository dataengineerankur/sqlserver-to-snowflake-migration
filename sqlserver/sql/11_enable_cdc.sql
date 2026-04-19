-- Enable SQL Server CDC at the database and table level for all 4 lab databases.
-- SQL Server Agent must be running before CDC can capture changes.
-- Run this AFTER all database and table creation scripts (01–22) have completed.

-- ── SnowConvertStressDB ───────────────────────────────────────────────────────
USE [SnowConvertStressDB];
GO

EXEC sys.sp_cdc_enable_db;
GO

EXEC sys.sp_cdc_enable_table
    @source_schema = 'dbo',
    @source_name   = 'Categories',
    @role_name     = NULL;
GO

EXEC sys.sp_cdc_enable_table
    @source_schema = 'dbo',
    @source_name   = 'Customers',
    @role_name     = NULL;
GO

EXEC sys.sp_cdc_enable_table
    @source_schema = 'dbo',
    @source_name   = 'Products',
    @role_name     = NULL;
GO

EXEC sys.sp_cdc_enable_table
    @source_schema = 'dbo',
    @source_name   = 'Orders',
    @role_name     = NULL;
GO

EXEC sys.sp_cdc_enable_table
    @source_schema = 'dbo',
    @source_name   = 'OrderItems',
    @role_name     = NULL;
GO

-- ── LabERP_DB ─────────────────────────────────────────────────────────────────
USE [LabERP_DB];
GO

EXEC sys.sp_cdc_enable_db;
GO

EXEC sys.sp_cdc_enable_table
    @source_schema = 'dbo',
    @source_name   = 'Departments',
    @role_name     = NULL;
GO

EXEC sys.sp_cdc_enable_table
    @source_schema = 'dbo',
    @source_name   = 'Employees',
    @role_name     = NULL;
GO

EXEC sys.sp_cdc_enable_table
    @source_schema = 'dbo',
    @source_name   = 'PayrollRuns',
    @role_name     = NULL;
GO

EXEC sys.sp_cdc_enable_table
    @source_schema = 'dbo',
    @source_name   = 'PayrollLines',
    @role_name     = NULL;
GO

-- ── LabCRM_DB ─────────────────────────────────────────────────────────────────
USE [LabCRM_DB];
GO

EXEC sys.sp_cdc_enable_db;
GO

EXEC sys.sp_cdc_enable_table
    @source_schema = 'dbo',
    @source_name   = 'Accounts',
    @role_name     = NULL;
GO

EXEC sys.sp_cdc_enable_table
    @source_schema = 'dbo',
    @source_name   = 'Contacts',
    @role_name     = NULL;
GO

EXEC sys.sp_cdc_enable_table
    @source_schema = 'dbo',
    @source_name   = 'Opportunities',
    @role_name     = NULL;
GO

-- ── LabInventory_DB ───────────────────────────────────────────────────────────
USE [LabInventory_DB];
GO

EXEC sys.sp_cdc_enable_db;
GO

EXEC sys.sp_cdc_enable_table
    @source_schema = 'dbo',
    @source_name   = 'Warehouses',
    @role_name     = NULL;
GO

EXEC sys.sp_cdc_enable_table
    @source_schema = 'dbo',
    @source_name   = 'Sku',
    @role_name     = NULL;
GO

EXEC sys.sp_cdc_enable_table
    @source_schema = 'dbo',
    @source_name   = 'StockMovements',
    @role_name     = NULL;
GO

-- ── Verify: all tables should show is_tracked_by_cdc = 1 ─────────────────────
USE [SnowConvertStressDB];
SELECT name, is_tracked_by_cdc
FROM sys.tables
WHERE name IN ('Categories','Customers','Products','Orders','OrderItems')
ORDER BY name;

USE [LabERP_DB];
SELECT name, is_tracked_by_cdc
FROM sys.tables
WHERE name IN ('Departments','Employees','PayrollRuns','PayrollLines')
ORDER BY name;

USE [LabCRM_DB];
SELECT name, is_tracked_by_cdc
FROM sys.tables
WHERE name IN ('Accounts','Contacts','Opportunities')
ORDER BY name;

USE [LabInventory_DB];
SELECT name, is_tracked_by_cdc
FROM sys.tables
WHERE name IN ('Warehouses','Sku','StockMovements')
ORDER BY name;
