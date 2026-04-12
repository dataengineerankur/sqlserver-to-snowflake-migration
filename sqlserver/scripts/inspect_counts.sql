/* Inventory and row counts for lab summary / reports */
SET NOCOUNT ON;
USE SnowConvertStressDB;
GO

PRINT '=== Object counts (user objects, non-system) ===';

SELECT N'TABLES' AS ObjectKind, COUNT(*) AS ObjectCount
FROM sys.tables
WHERE is_ms_shipped = 0
UNION ALL
SELECT N'VIEWS', COUNT(*)
FROM sys.views
WHERE is_ms_shipped = 0
UNION ALL
SELECT N'PROCEDURES', COUNT(*)
FROM sys.procedures
WHERE is_ms_shipped = 0
UNION ALL
SELECT N'FUNCTIONS', COUNT(*)
FROM sys.objects
WHERE type IN (N'FN', N'IF', N'TF', N'FS', N'FT')
  AND is_ms_shipped = 0
UNION ALL
SELECT N'TRIGGERS', COUNT(*)
FROM sys.triggers
WHERE parent_class = 1
  AND is_ms_shipped = 0;
GO

PRINT '=== Row counts (major tables) ===';

SELECT N'Categories' AS TableName, COUNT_BIG(*) AS RowCnt FROM dbo.Categories
UNION ALL SELECT N'Customers', COUNT_BIG(*) FROM dbo.Customers
UNION ALL SELECT N'Products', COUNT_BIG(*) FROM dbo.Products
UNION ALL SELECT N'Orders', COUNT_BIG(*) FROM dbo.Orders
UNION ALL SELECT N'OrderItems', COUNT_BIG(*) FROM dbo.OrderItems;
GO
