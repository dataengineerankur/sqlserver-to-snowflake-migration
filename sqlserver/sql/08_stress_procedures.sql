/* Migration-stress stored procedures: dynamic SQL, TVP, cursors, MERGE, XML/JSON, nesting, savepoints */
SET NOCOUNT ON;
USE SnowConvertStressDB;
GO

/* Drop dependents first */
IF OBJECT_ID(N'dbo.usp_Stress_TvpAppendOrderLines', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_Stress_TvpAppendOrderLines;
IF OBJECT_ID(N'dbo.usp_Stress_OpenJsonApplyPatch', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_Stress_OpenJsonApplyPatch;
IF OBJECT_ID(N'dbo.usp_Stress_DynamicSearchOrders', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_Stress_DynamicSearchOrders;
IF OBJECT_ID(N'dbo.usp_Stress_CursorRepriceProductsByCategory', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_Stress_CursorRepriceProductsByCategory;
IF OBJECT_ID(N'dbo.usp_Stress_MergeUpsertCustomers', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_Stress_MergeUpsertCustomers;
IF OBJECT_ID(N'dbo.usp_Stress_XmlOrderDocument', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_Stress_XmlOrderDocument;
IF OBJECT_ID(N'dbo.usp_Stress_JsonOrderLines', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_Stress_JsonOrderLines;
IF OBJECT_ID(N'dbo.usp_Stress_ChainedC_Inner', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_Stress_ChainedC_Inner;
IF OBJECT_ID(N'dbo.usp_Stress_ChainedB_Middle', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_Stress_ChainedB_Middle;
IF OBJECT_ID(N'dbo.usp_Stress_ChainedA_Outer', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_Stress_ChainedA_Outer;
IF OBJECT_ID(N'dbo.usp_Stress_RecursiveCategoryClosure', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_Stress_RecursiveCategoryClosure;
IF OBJECT_ID(N'dbo.usp_Stress_SavePointPartialRollback', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_Stress_SavePointPartialRollback;
IF OBJECT_ID(N'dbo.usp_Stress_ThrowCatchAndRethrow', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_Stress_ThrowCatchAndRethrow;
IF OBJECT_ID(N'dbo.usp_Stress_OutputMergePriceHistory', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_Stress_OutputMergePriceHistory;
IF OBJECT_ID(N'dbo.usp_Stress_WhileBatchNumbers', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_Stress_WhileBatchNumbers;
IF OBJECT_ID(N'dbo.usp_Stress_MultiResultSets', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_Stress_MultiResultSets;
IF OBJECT_ID(N'dbo.usp_Stress_WaitForShort', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_Stress_WaitForShort;
IF OBJECT_ID(N'dbo.usp_Stress_TempTableDynamicPivot', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_Stress_TempTableDynamicPivot;
IF OBJECT_ID(N'dbo.usp_Stress_ScopedTempTableCaller', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_Stress_ScopedTempTableCaller;
IF OBJECT_ID(N'dbo.usp_Stress_ScopedTempTableCallee', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_Stress_ScopedTempTableCallee;
GO

IF TYPE_ID(N'dbo.OrderLineInput') IS NOT NULL DROP TYPE dbo.OrderLineInput;
GO

CREATE TYPE dbo.OrderLineInput AS TABLE (
    ProductId INT            NOT NULL,
    Quantity  INT            NOT NULL,
    UnitPrice DECIMAL(18, 4) NOT NULL
);
GO

CREATE PROCEDURE dbo.usp_Stress_DynamicSearchOrders
    @Status       NVARCHAR(30) = NULL,
    @Country      NVARCHAR(100) = NULL,
    @MinTotal     DECIMAL(18, 4) = NULL,
    @SortColumn   NVARCHAR(50)  = N'OrderDate',
    @SortDir      NVARCHAR(4)   = N'DESC'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @sql NVARCHAR(MAX);
    DECLARE @safeSort SYSNAME =
        CASE WHEN @SortColumn IN (N'OrderDate', N'TotalAmount', N'OrderId', N'Status') THEN @SortColumn ELSE N'OrderDate' END;
    DECLARE @dir NVARCHAR(4) = CASE WHEN UPPER(@SortDir) = N'ASC' THEN N'ASC' ELSE N'DESC' END;

    SET @sql = N'
    SELECT o.OrderId, o.OrderDate, o.Status, o.TotalAmount, c.CustomerCode, c.Country
    FROM dbo.Orders o
    INNER JOIN dbo.Customers c ON c.CustomerId = o.CustomerId
    WHERE 1=1'
    + CASE WHEN @Status IS NOT NULL THEN N' AND o.Status = @pStatus' ELSE N'' END
    + CASE WHEN @Country IS NOT NULL THEN N' AND c.Country = @pCountry' ELSE N'' END
    + CASE WHEN @MinTotal IS NOT NULL THEN N' AND o.TotalAmount >= @pMinTotal' ELSE N'' END
    + N' ORDER BY ' + QUOTENAME(@safeSort) + N' ' + @dir;

    EXEC sp_executesql @sql,
        N'@pStatus NVARCHAR(30), @pCountry NVARCHAR(100), @pMinTotal DECIMAL(18,4)',
        @pStatus = @Status, @pCountry = @Country, @pMinTotal = @MinTotal;
END;
GO

CREATE PROCEDURE dbo.usp_Stress_CursorRepriceProductsByCategory
    @CategoryId INT,
    @PctBump    DECIMAL(9, 6)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pid INT;
    DECLARE @old DECIMAL(18, 4);
    DECLARE @new DECIMAL(18, 4);

    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT ProductId, ListPrice
        FROM dbo.Products
        WHERE CategoryId = @CategoryId AND IsActive = 1;

    OPEN cur;
    FETCH NEXT FROM cur INTO @pid, @old;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @new = ROUND(@old * (1 + @PctBump), 4);
        UPDATE dbo.Products SET ListPrice = @new WHERE ProductId = @pid;
        FETCH NEXT FROM cur INTO @pid, @old;
    END
    CLOSE cur;
    DEALLOCATE cur;
END;
GO

CREATE PROCEDURE dbo.usp_Stress_MergeUpsertCustomers
    @SourceJson NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @t TABLE (
        CustomerCode NVARCHAR(20),
        FullName     NVARCHAR(200),
        Email        NVARCHAR(320),
        Country      NVARCHAR(100)
    );

    INSERT INTO @t (CustomerCode, FullName, Email, Country)
    SELECT CustomerCode, FullName, Email, Country
    FROM OPENJSON(@SourceJson)
    WITH (
        CustomerCode NVARCHAR(20)  N'$.CustomerCode',
        FullName     NVARCHAR(200) N'$.FullName',
        Email        NVARCHAR(320) N'$.Email',
        Country      NVARCHAR(100) N'$.Country'
    );

    MERGE dbo.Customers AS tgt
    USING @t AS src ON tgt.CustomerCode = src.CustomerCode
    WHEN MATCHED THEN
        UPDATE SET FullName = src.FullName, Email = src.Email, Country = src.Country
    WHEN NOT MATCHED THEN
        INSERT (CustomerCode, FullName, Email, Country)
        VALUES (src.CustomerCode, src.FullName, src.Email, ISNULL(src.Country, N'US'))
    OUTPUT $action, inserted.CustomerId, deleted.CustomerId;
END;
GO

CREATE PROCEDURE dbo.usp_Stress_XmlOrderDocument
    @OrderId BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @x XML;

    SET @x = (
        SELECT
            o.OrderId,
            o.OrderDate,
            o.Status,
            o.TotalAmount,
            (SELECT c.CustomerCode, c.FullName, c.Country
             FROM dbo.Customers c WHERE c.CustomerId = o.CustomerId
             FOR XML PATH(N'Customer'), TYPE),
            (SELECT oi.OrderItemId, oi.Quantity, oi.UnitPrice, oi.LineTotal,
                    p.SKU, p.ProductName
             FROM dbo.OrderItems oi
             INNER JOIN dbo.Products p ON p.ProductId = oi.ProductId
             WHERE oi.OrderId = o.OrderId
             FOR XML PATH(N'Line'), TYPE)
        FROM dbo.Orders o
        WHERE o.OrderId = @OrderId
        FOR XML PATH(N'Order'), ROOT(N'OrderBundle'), TYPE
    );

    SELECT @x AS OrderXml;
END;
GO

CREATE PROCEDURE dbo.usp_Stress_JsonOrderLines
    @OrderId BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT (
        SELECT oi.OrderItemId, oi.ProductId, oi.Quantity, oi.UnitPrice, oi.LineTotal, p.SKU
        FROM dbo.OrderItems oi
        INNER JOIN dbo.Products p ON p.ProductId = oi.ProductId
        WHERE oi.OrderId = @OrderId
        FOR JSON PATH, INCLUDE_NULL_VALUES
    ) AS LinesJson;
END;
GO

CREATE PROCEDURE dbo.usp_Stress_ChainedC_Inner
    @OrderId BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.Orders SET Notes = ISNULL(Notes, N'') + N' [C]'
    WHERE OrderId = @OrderId;
END;
GO

CREATE PROCEDURE dbo.usp_Stress_ChainedB_Middle
    @OrderId BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.usp_Stress_ChainedC_Inner @OrderId = @OrderId;
    UPDATE dbo.Orders SET Notes = ISNULL(Notes, N'') + N' [B]'
    WHERE OrderId = @OrderId;
END;
GO

CREATE PROCEDURE dbo.usp_Stress_ChainedA_Outer
    @OrderId BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.usp_Stress_ChainedB_Middle @OrderId = @OrderId;
    UPDATE dbo.Orders SET Notes = ISNULL(Notes, N'') + N' [A]'
    WHERE OrderId = @OrderId;
END;
GO

CREATE PROCEDURE dbo.usp_Stress_RecursiveCategoryClosure
AS
BEGIN
    SET NOCOUNT ON;
    TRUNCATE TABLE dbo.CategoryClosure;

    /* Self depth 0 */
    INSERT INTO dbo.CategoryClosure (AncestorId, DescendantId, Depth)
    SELECT c.CategoryId, c.CategoryId, 0
    FROM dbo.Categories c;

    /* BFS-style closure for small tree (categories are shallow in seed) */
    ;WITH edges AS (
        SELECT p.CategoryId AS ParentId, c.CategoryId AS ChildId
        FROM dbo.Categories p
        INNER JOIN dbo.Categories c ON c.CategoryId > p.CategoryId
        WHERE ABS(CHECKSUM(p.CategoryId, c.CategoryId)) % 3 = 0 /* synthetic edges for demo graph */
    ),
    walk AS (
        SELECT ParentId AS AncestorId, ChildId AS DescendantId, 1 AS Depth FROM edges
        UNION ALL
        SELECT w.AncestorId, e.ChildId, w.Depth + 1
        FROM walk w
        INNER JOIN edges e ON e.ParentId = w.DescendantId
        WHERE w.Depth < 5
    )
    INSERT INTO dbo.CategoryClosure (AncestorId, DescendantId, Depth)
    SELECT DISTINCT AncestorId, DescendantId, Depth FROM walk
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.CategoryClosure cc
        WHERE cc.AncestorId = walk.AncestorId AND cc.DescendantId = walk.DescendantId
    );

    SELECT COUNT(*) AS ClosureRows FROM dbo.CategoryClosure;
END;
GO

CREATE PROCEDURE dbo.usp_Stress_SavePointPartialRollback
    @CustomerId INT
AS
BEGIN
    SET NOCOUNT ON;
    /* Demonstrates savepoint rollback then full rollback — leaves no net data change */
    BEGIN TRANSACTION;
    SAVE TRANSACTION Save1;
    UPDATE dbo.Customers SET Country = N'_SP_A' WHERE CustomerId = @CustomerId;
    SAVE TRANSACTION Save2;
    UPDATE dbo.Customers SET Country = N'_SP_B' WHERE CustomerId = @CustomerId;
    ROLLBACK TRANSACTION Save2;
    DECLARE @mid NVARCHAR(100) = (SELECT Country FROM dbo.Customers WHERE CustomerId = @CustomerId);
    ROLLBACK TRANSACTION;
    SELECT @mid AS CountrySeenInsideTran_Expect_SP_A;
END;
GO

CREATE PROCEDURE dbo.usp_Stress_ThrowCatchAndRethrow
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        ;THROW 50001, N'Stress: intentional error for migration harness', 1;
    END TRY
    BEGIN CATCH
        INSERT INTO dbo.MigrationAuditLog (TableName, DmlAction, RowPk, NewPayload, SqlTrigger)
        VALUES (N'_ERROR_', N'CATCH', N'', ERROR_MESSAGE(), N'usp_Stress_ThrowCatchAndRethrow');
        THROW;
    END CATCH
END;
GO

CREATE PROCEDURE dbo.usp_Stress_OutputMergePriceHistory
    @ProductId INT,
    @NewPrice  DECIMAL(18, 4)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @delta TABLE (OldP DECIMAL(18,4), NewP DECIMAL(18,4));

    UPDATE dbo.Products
    SET ListPrice = @NewPrice
    OUTPUT deleted.ListPrice, inserted.ListPrice INTO @delta (OldP, NewP)
    WHERE ProductId = @ProductId;

    INSERT INTO dbo.ProductPriceHistory (ProductId, OldPrice, NewPrice)
    SELECT @ProductId, OldP, NewP FROM @delta;
END;
GO

CREATE PROCEDURE dbo.usp_Stress_WhileBatchNumbers
    @Iterations INT = 1000
AS
BEGIN
    SET NOCOUNT ON;
    CREATE TABLE #nums (n INT NOT NULL PRIMARY KEY);
    DECLARE @i INT = 1;
    WHILE @i <= @Iterations AND @i <= 5000
    BEGIN
        INSERT INTO #nums (n) VALUES (@i);
        SET @i += 1;
    END
    SELECT COUNT(*) AS NumRows, SUM(n) AS SumN FROM #nums;
    DROP TABLE #nums;
END;
GO

CREATE PROCEDURE dbo.usp_Stress_MultiResultSets
    @CustomerId INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT * FROM dbo.Customers WHERE CustomerId = @CustomerId;
    SELECT * FROM dbo.Orders WHERE CustomerId = @CustomerId ORDER BY OrderDate DESC;
    SELECT oi.* FROM dbo.OrderItems oi
    INNER JOIN dbo.Orders o ON o.OrderId = oi.OrderId
    WHERE o.CustomerId = @CustomerId;
END;
GO

CREATE PROCEDURE dbo.usp_Stress_WaitForShort
AS
BEGIN
    SET NOCOUNT ON;
    WAITFOR DELAY '00:00:00.100';
    SELECT CAST(1 AS INT) AS Ok;
END;
GO

CREATE PROCEDURE dbo.usp_Stress_TempTableDynamicPivot
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cols NVARCHAR(MAX);
    DECLARE @sql  NVARCHAR(MAX);

    SELECT @cols = STRING_AGG(QUOTENAME(Status), N',') WITHIN GROUP (ORDER BY Status)
    FROM (SELECT DISTINCT Status FROM dbo.Orders) s;

    IF @cols IS NULL SET @cols = N'[Open]';

    SET @sql = N'
    SELECT * FROM (
        SELECT o.Status, o.CustomerId, o.TotalAmount
        FROM dbo.Orders o
    ) src
    PIVOT (SUM(TotalAmount) FOR Status IN (' + @cols + N')) p';

    EXEC sp_executesql @sql;
END;
GO

CREATE PROCEDURE dbo.usp_Stress_ScopedTempTableCallee
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO #shared (x) VALUES (2);
END;
GO

CREATE PROCEDURE dbo.usp_Stress_ScopedTempTableCaller
AS
BEGIN
    SET NOCOUNT ON;
    CREATE TABLE #shared (x INT);
    INSERT INTO #shared (x) VALUES (1);
    EXEC dbo.usp_Stress_ScopedTempTableCallee;
    SELECT SUM(x) AS SharedSum FROM #shared;
END;
GO

CREATE PROCEDURE dbo.usp_Stress_TvpAppendOrderLines
    @OrderId BIGINT,
    @Lines   dbo.OrderLineInput READONLY
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.OrderItems (OrderId, ProductId, Quantity, UnitPrice)
    SELECT @OrderId, l.ProductId, l.Quantity, l.UnitPrice FROM @Lines AS l;
    EXEC dbo.usp_RefreshOrderTotals @OrderId = @OrderId;
END;
GO

CREATE PROCEDURE dbo.usp_Stress_OpenJsonApplyPatch
    @PatchJson NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE p
    SET ListPrice = COALESCE(j.NewPrice, p.ListPrice),
        IsActive  = COALESCE(j.IsActive, p.IsActive)
    FROM dbo.Products p
    INNER JOIN OPENJSON(@PatchJson)
    WITH (ProductId INT N'$.ProductId', NewPrice DECIMAL(18,4) N'$.NewPrice', IsActive BIT N'$.IsActive') j
        ON j.ProductId = p.ProductId;
END;
GO

PRINT 'Stress procedures created';
GO
