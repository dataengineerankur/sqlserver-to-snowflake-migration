/* Views for reporting-style inspection */
SET NOCOUNT ON;
USE SnowConvertStressDB;
GO

IF OBJECT_ID(N'dbo.vw_OrderLineDetail', N'V') IS NOT NULL
    DROP VIEW dbo.vw_OrderLineDetail;
GO

CREATE VIEW dbo.vw_OrderLineDetail
AS
SELECT
    o.OrderId,
    o.OrderDate,
    o.Status,
    c.CustomerCode,
    c.FullName AS CustomerName,
    p.SKU,
    p.ProductName,
    oi.Quantity,
    oi.UnitPrice,
    oi.LineTotal,
    cat.CategoryName
FROM dbo.OrderItems oi
INNER JOIN dbo.Orders o ON o.OrderId = oi.OrderId
INNER JOIN dbo.Customers c ON c.CustomerId = o.CustomerId
INNER JOIN dbo.Products p ON p.ProductId = oi.ProductId
INNER JOIN dbo.Categories cat ON cat.CategoryId = p.CategoryId;
GO

IF OBJECT_ID(N'dbo.vw_CustomerOrderTotals', N'V') IS NOT NULL
    DROP VIEW dbo.vw_CustomerOrderTotals;
GO

CREATE VIEW dbo.vw_CustomerOrderTotals
AS
SELECT
    c.CustomerId,
    c.CustomerCode,
    c.FullName,
    COUNT(DISTINCT o.OrderId) AS OrderCount,
    SUM(o.TotalAmount) AS SumOrderTotals
FROM dbo.Customers c
LEFT JOIN dbo.Orders o ON o.CustomerId = c.CustomerId
GROUP BY c.CustomerId, c.CustomerCode, c.FullName;
GO

PRINT 'Views created';
GO
