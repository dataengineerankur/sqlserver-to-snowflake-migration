/* Stored procedures for lab execution tests */
SET NOCOUNT ON;
USE SnowConvertStressDB;
GO

IF OBJECT_ID(N'dbo.usp_RefreshOrderTotals', N'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_RefreshOrderTotals;
GO

CREATE PROCEDURE dbo.usp_RefreshOrderTotals
    @OrderId BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH agg AS (
        SELECT oi.OrderId, SUM(oi.LineTotal) AS ComputedTotal
        FROM dbo.OrderItems oi
        WHERE @OrderId IS NULL OR oi.OrderId = @OrderId
        GROUP BY oi.OrderId
    )
    UPDATE o
    SET TotalAmount = a.ComputedTotal
    FROM dbo.Orders o
    INNER JOIN agg a ON a.OrderId = o.OrderId;
END;
GO

IF OBJECT_ID(N'dbo.usp_ListOpenOrders', N'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_ListOpenOrders;
GO

CREATE PROCEDURE dbo.usp_ListOpenOrders
AS
BEGIN
    SET NOCOUNT ON;
    SELECT OrderId, CustomerId, OrderDate, Status, TotalAmount
    FROM dbo.Orders
    WHERE Status = N'Open'
    ORDER BY OrderDate;
END;
GO

PRINT 'Procedures created';
GO
