/* Migration-stress triggers: audit, INSTEAD OF on view, nested firing, UPDATE(column), queue, ordering */
SET NOCOUNT ON;
USE SnowConvertStressDB;
GO

ALTER DATABASE CURRENT SET RECURSIVE_TRIGGERS OFF;
GO

/* ---- Drop (reverse dependency order) ---- */
IF OBJECT_ID(N'dbo.tr_vw_Orders_Dml_IOU', N'TR') IS NOT NULL DROP TRIGGER dbo.tr_vw_Orders_Dml_IOU;
IF OBJECT_ID(N'dbo.tr_vw_Orders_Dml_IOD', N'TR') IS NOT NULL DROP TRIGGER dbo.tr_vw_Orders_Dml_IOD;
IF OBJECT_ID(N'dbo.tr_OrderItems_RecalcAndQueue', N'TR') IS NOT NULL DROP TRIGGER dbo.tr_OrderItems_RecalcAndQueue;
IF OBJECT_ID(N'dbo.tr_Products_ListPriceAudit', N'TR') IS NOT NULL DROP TRIGGER dbo.tr_Products_ListPriceAudit;
IF OBJECT_ID(N'dbo.tr_Orders_Audit_IU', N'TR') IS NOT NULL DROP TRIGGER dbo.tr_Orders_Audit_IU;
IF OBJECT_ID(N'dbo.vw_Orders_Dml', N'V') IS NOT NULL DROP VIEW dbo.vw_Orders_Dml;
GO

/* Updatable view surface — INSTEAD OF DML is tricky for converters */
CREATE VIEW dbo.vw_Orders_Dml
AS
SELECT OrderId, CustomerId, OrderDate, Status, TotalAmount, Notes
FROM dbo.Orders;
GO

CREATE TRIGGER dbo.tr_vw_Orders_Dml_IOD
ON dbo.vw_Orders_Dml
INSTEAD OF DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM deleted WHERE Status = N'Closed')
    BEGIN
        RAISERROR(N'Cannot delete closed orders through vw_Orders_Dml (archive pattern).', 16, 1);
        RETURN;
    END;

    INSERT INTO dbo.OrdersArchive (OrderId, CustomerId, OrderDate, Status, TotalAmount, Notes, ArchiveReason)
    SELECT OrderId, CustomerId, OrderDate, Status, TotalAmount, Notes, N'INSTEAD OF DELETE via view'
    FROM deleted;

    DELETE o
    FROM dbo.Orders o
    INNER JOIN deleted d ON d.OrderId = o.OrderId;
END;
GO

CREATE TRIGGER dbo.tr_vw_Orders_Dml_IOU
ON dbo.vw_Orders_Dml
INSTEAD OF UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF UPDATE(OrderId)
    BEGIN
        RAISERROR(N'OrderId is immutable through vw_Orders_Dml.', 16, 1);
        RETURN;
    END;

    UPDATE o
    SET
        Status      = CASE WHEN UPDATE(Status) THEN i.Status ELSE o.Status END,
        Notes       = CASE WHEN UPDATE(Notes) THEN i.Notes ELSE o.Notes END,
        TotalAmount = CASE WHEN UPDATE(TotalAmount) THEN i.TotalAmount ELSE o.TotalAmount END
    FROM dbo.Orders o
    INNER JOIN inserted i ON i.OrderId = o.OrderId;
END;
GO

/* FIRST trigger: audit trail + JSON payload for inserted/deleted diff pattern */
CREATE TRIGGER dbo.tr_Orders_Audit_IU
ON dbo.Orders
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL() > 3 RETURN;

    INSERT INTO dbo.MigrationAuditLog (TableName, DmlAction, RowPk, OldPayload, NewPayload, SqlTrigger)
    SELECT
        N'Orders',
        CASE WHEN d.OrderId IS NULL THEN N'INSERT' ELSE N'UPDATE' END,
        CAST(i.OrderId AS NVARCHAR(50)),
        CASE WHEN d.OrderId IS NULL THEN NULL
             ELSE (SELECT d.OrderId, d.CustomerId, d.OrderDate, d.Status, d.TotalAmount, d.Notes
                   FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) END,
        (SELECT i.OrderId, i.CustomerId, i.OrderDate, i.Status, i.TotalAmount, i.Notes
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        N'tr_Orders_Audit_IU'
    FROM inserted i
    LEFT JOIN deleted d ON d.OrderId = i.OrderId;
END;
GO

EXEC sys.sp_settriggerorder
    @triggername = N'dbo.tr_Orders_Audit_IU',
    @order = N'First',
    @stmttype = N'INSERT';
EXEC sys.sp_settriggerorder
    @triggername = N'dbo.tr_Orders_Audit_IU',
    @order = N'First',
    @stmttype = N'UPDATE';
GO

/* AFTER on line items: recalc header + event queue (fires nested Orders UPDATE) */
CREATE TRIGGER dbo.tr_OrderItems_RecalcAndQueue
ON dbo.OrderItems
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @oids TABLE (OrderId BIGINT PRIMARY KEY);

    INSERT INTO @oids (OrderId)
    SELECT DISTINCT OrderId FROM inserted
    UNION
    SELECT DISTINCT OrderId FROM deleted;

    INSERT INTO dbo.OrderEventQueue (OrderId, EventType, Payload)
    SELECT o.OrderId,
           N'LINE_ITEMS_CHANGED',
           (SELECT COUNT(*) AS Cnt FROM dbo.OrderItems oi WHERE oi.OrderId = o.OrderId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM @oids o;

    ;WITH agg AS (
        SELECT oi.OrderId, SUM(oi.LineTotal) AS NewTotal
        FROM dbo.OrderItems oi
        INNER JOIN @oids t ON t.OrderId = oi.OrderId
        GROUP BY oi.OrderId
    )
    UPDATE ord
    SET TotalAmount = COALESCE(a.NewTotal, 0)
    FROM dbo.Orders ord
    INNER JOIN @oids t ON t.OrderId = ord.OrderId
    LEFT JOIN agg a ON a.OrderId = ord.OrderId;
END;
GO

/* UPDATE(ListPrice) narrow predicate — common migration gap */
CREATE TRIGGER dbo.tr_Products_ListPriceAudit
ON dbo.Products
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE(ListPrice) RETURN;

    INSERT INTO dbo.ProductPriceHistory (ProductId, OldPrice, NewPrice)
    SELECT i.ProductId, d.ListPrice, i.ListPrice
    FROM inserted i
    INNER JOIN deleted d ON d.ProductId = i.ProductId
    WHERE i.ListPrice <> d.ListPrice
       OR (i.ListPrice IS NULL AND d.ListPrice IS NOT NULL)
       OR (i.ListPrice IS NOT NULL AND d.ListPrice IS NULL);
END;
GO

PRINT 'Stress triggers + vw_Orders_Dml created';
GO
