/* Supporting tables + TVP for migration-stress procedures & triggers */
SET NOCOUNT ON;
USE SnowConvertStressDB;
GO

IF OBJECT_ID(N'dbo.OrderEventQueue', N'U') IS NOT NULL DROP TABLE dbo.OrderEventQueue;
IF OBJECT_ID(N'dbo.OrdersArchive', N'U') IS NOT NULL DROP TABLE dbo.OrdersArchive;
IF OBJECT_ID(N'dbo.ProductPriceHistory', N'U') IS NOT NULL DROP TABLE dbo.ProductPriceHistory;
IF OBJECT_ID(N'dbo.MigrationAuditLog', N'U') IS NOT NULL DROP TABLE dbo.MigrationAuditLog;
IF OBJECT_ID(N'dbo.CategoryClosure', N'U') IS NOT NULL DROP TABLE dbo.CategoryClosure;
GO

CREATE TABLE dbo.MigrationAuditLog (
    AuditId      BIGINT         IDENTITY(1,1) NOT NULL PRIMARY KEY,
    TableName    SYSNAME        NOT NULL,
    DmlAction    NVARCHAR(10)   NOT NULL,
    RowPk        NVARCHAR(200)  NULL,
    OldPayload   NVARCHAR(MAX)  NULL,
    NewPayload   NVARCHAR(MAX)  NULL,
    SqlTrigger   NVARCHAR(256)  NULL,
    NestLevel    INT            NOT NULL DEFAULT TRIGGER_NESTLEVEL(),
    ChangedAt    DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
    ChangedBy    NVARCHAR(256)  NOT NULL DEFAULT SUSER_SNAME()
);

CREATE TABLE dbo.OrderEventQueue (
    EventId     BIGINT         IDENTITY(1,1) NOT NULL PRIMARY KEY,
    OrderId     BIGINT         NOT NULL,
    EventType   NVARCHAR(40)   NOT NULL,
    Payload     NVARCHAR(MAX)  NULL,
    CreatedAt   DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
    Processed   BIT            NOT NULL DEFAULT 0
);

CREATE TABLE dbo.OrdersArchive (
    ArchiveId    BIGINT         IDENTITY(1,1) NOT NULL PRIMARY KEY,
    OrderId      BIGINT         NOT NULL,
    CustomerId   INT            NOT NULL,
    OrderDate    DATE           NOT NULL,
    Status       NVARCHAR(30)   NOT NULL,
    TotalAmount  DECIMAL(18, 4) NOT NULL,
    Notes        NVARCHAR(500)  NULL,
    ArchivedAt   DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
    ArchiveReason NVARCHAR(200) NULL
);

CREATE TABLE dbo.ProductPriceHistory (
    HistoryId    BIGINT         IDENTITY(1,1) NOT NULL PRIMARY KEY,
    ProductId    INT            NOT NULL,
    OldPrice     DECIMAL(18, 4) NULL,
    NewPrice     DECIMAL(18, 4) NOT NULL,
    ChangedAt    DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
    ChangedBy    NVARCHAR(256)  NOT NULL DEFAULT SUSER_SNAME()
);

/* Materialized closure for recursive-Category stress (populated by proc) */
CREATE TABLE dbo.CategoryClosure (
    AncestorId   INT NOT NULL,
    DescendantId INT NOT NULL,
    Depth        INT NOT NULL,
    CONSTRAINT PK_CategoryClosure PRIMARY KEY (AncestorId, DescendantId)
);

CREATE INDEX IX_OrderEventQueue_OrderId ON dbo.OrderEventQueue(OrderId);
CREATE INDEX IX_MigrationAuditLog_TableName ON dbo.MigrationAuditLog(TableName, ChangedAt);
GO

PRINT 'Stress DDL tables created';
GO
