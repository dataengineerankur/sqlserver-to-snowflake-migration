/* LabInventory_DB — stock movements + view with INSTEAD OF + XML export proc */
SET NOCOUNT ON;
USE LabInventory_DB;
GO

IF OBJECT_ID(N'dbo.tr_vw_StockOrders_IOI', N'TR') IS NOT NULL DROP TRIGGER dbo.tr_vw_StockOrders_IOI;
IF OBJECT_ID(N'dbo.vw_StockOrders', N'V') IS NOT NULL DROP VIEW dbo.vw_StockOrders;
IF OBJECT_ID(N'dbo.StockMovements', N'U') IS NOT NULL DROP TABLE dbo.StockMovements;
IF OBJECT_ID(N'dbo.Sku', N'U') IS NOT NULL DROP TABLE dbo.Sku;
IF OBJECT_ID(N'dbo.Warehouses', N'U') IS NOT NULL DROP TABLE dbo.Warehouses;
GO

CREATE TABLE dbo.Warehouses (
    WhId     INT           IDENTITY(1,1) NOT NULL PRIMARY KEY,
    WhCode   NVARCHAR(20)  NOT NULL UNIQUE,
    Location NVARCHAR(200) NOT NULL
);

CREATE TABLE dbo.Sku (
    SkuId    INT           IDENTITY(1,1) NOT NULL PRIMARY KEY,
    SkuCode  NVARCHAR(40)  NOT NULL UNIQUE,
    Descr    NVARCHAR(200) NOT NULL,
    UnitCost DECIMAL(18,4) NOT NULL
);

CREATE TABLE dbo.StockMovements (
    MovId      BIGINT       IDENTITY(1,1) NOT NULL PRIMARY KEY,
    WhId       INT          NOT NULL REFERENCES dbo.Warehouses(WhId),
    SkuId      INT          NOT NULL REFERENCES dbo.Sku(SkuId),
    QtyChange  INT          NOT NULL,
    Reason     NVARCHAR(80) NOT NULL,
    MovDate    DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME()
);

INSERT dbo.Warehouses (WhCode, Location) VALUES (N'EAST', N'Newark'), (N'WEST', N'Reno');
INSERT dbo.Sku (SkuCode, Descr, UnitCost) VALUES (N'ITEM-A', N'Widget A', 12.5), (N'ITEM-B', N'Widget B', 4.25);
INSERT dbo.StockMovements (WhId, SkuId, QtyChange, Reason) VALUES
(1, 1, 100, N'Initial'), (1, 2, 200, N'Initial'), (2, 1, 50, N'Transfer in');
GO

CREATE VIEW dbo.vw_StockOrders
AS
SELECT MovId, WhId, SkuId, QtyChange, Reason, MovDate FROM dbo.StockMovements;
GO

CREATE TRIGGER dbo.tr_vw_StockOrders_IOI
ON dbo.vw_StockOrders
INSTEAD OF INSERT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.StockMovements (WhId, SkuId, QtyChange, Reason)
    SELECT WhId, SkuId, QtyChange, ISNULL(Reason, N'via view')
    FROM inserted;
END;
GO

IF OBJECT_ID(N'dbo.usp_Inv_StockXml', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_Inv_StockXml;
IF OBJECT_ID(N'dbo.usp_Inv_DynamicWhFilter', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_Inv_DynamicWhFilter;
GO

CREATE PROCEDURE dbo.usp_Inv_StockXml @WhId INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @x XML = (
        SELECT w.WhCode, s.SkuCode, m.QtyChange, m.Reason
        FROM dbo.StockMovements m
        INNER JOIN dbo.Warehouses w ON w.WhId = m.WhId
        INNER JOIN dbo.Sku s ON s.SkuId = m.SkuId
        WHERE m.WhId = @WhId
        FOR XML PATH(N'Move'), ROOT(N'Warehouse')
    );
    SELECT @x AS StockXml;
END;
GO

CREATE PROCEDURE dbo.usp_Inv_DynamicWhFilter @WhCode NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @sql NVARCHAR(MAX) = N'
      SELECT m.MovId, w.WhCode, s.SkuCode, m.QtyChange
      FROM dbo.StockMovements m
      INNER JOIN dbo.Warehouses w ON w.WhId = m.WhId
      INNER JOIN dbo.Sku s ON s.SkuId = m.SkuId
      WHERE w.WhCode = @wc';
    EXEC sp_executesql @sql, N'@wc NVARCHAR(20)', @wc = @WhCode;
END;
GO

IF OBJECT_ID(N'dbo.tr_Sku_NoNegativeCost', N'TR') IS NOT NULL DROP TRIGGER dbo.tr_Sku_NoNegativeCost;
GO

CREATE TRIGGER dbo.tr_Sku_NoNegativeCost
ON dbo.Sku
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM inserted WHERE UnitCost < 0)
    BEGIN
        RAISERROR(N'SKU unit cost cannot be negative', 16, 1);
        ROLLBACK TRANSACTION;
    END
END;
GO

PRINT 'LabInventory_DB deployed';
GO
