/* Post-deploy sanity checks (also used by run_validation.sh) */
SET NOCOUNT ON;
USE SnowConvertStressDB;
GO

SELECT 'Categories' AS TableName, COUNT(*) AS RowCnt FROM dbo.Categories
UNION ALL SELECT 'Customers', COUNT(*) FROM dbo.Customers
UNION ALL SELECT 'Products', COUNT(*) FROM dbo.Products
UNION ALL SELECT 'Orders', COUNT(*) FROM dbo.Orders
UNION ALL SELECT 'OrderItems', COUNT(*) FROM dbo.OrderItems;
GO

SELECT TOP 3 * FROM dbo.vw_OrderLineDetail ORDER BY OrderId, SKU;
GO

EXEC dbo.usp_ListOpenOrders;
GO

SELECT dbo.fn_FormatMoney(t.GrandTotal) AS FormattedGrandTotal
FROM (SELECT SUM(TotalAmount) AS GrandTotal FROM dbo.Orders) AS t;
GO

/* Stress procedure smoke tests (should succeed) */
EXEC dbo.usp_Stress_DynamicSearchOrders @Status = N'Open', @SortColumn = N'OrderDate', @SortDir = N'DESC';
GO

EXEC dbo.usp_Stress_JsonOrderLines @OrderId = 1;
GO

EXEC dbo.usp_Stress_MultiResultSets @CustomerId = 1;
GO

EXEC dbo.usp_Stress_RecursiveCategoryClosure;
GO

SELECT COUNT(*) AS TriggerCount_Orders FROM sys.triggers WHERE parent_id = OBJECT_ID(N'dbo.Orders');
SELECT COUNT(*) AS TriggerCount_OrderItems FROM sys.triggers WHERE parent_id = OBJECT_ID(N'dbo.OrderItems');
SELECT COUNT(*) AS TriggerCount_Products FROM sys.triggers WHERE parent_id = OBJECT_ID(N'dbo.Products');
SELECT COUNT(*) AS TriggerCount_OnViews FROM sys.triggers t
INNER JOIN sys.views v ON t.parent_id = v.object_id;
GO
