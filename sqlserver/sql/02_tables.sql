/* Core relational model — idempotent drops/recreate for lab repeatability */
SET NOCOUNT ON;
USE SnowConvertStressDB;
GO

IF OBJECT_ID(N'dbo.OrderItems', N'U') IS NOT NULL DROP TABLE dbo.OrderItems;
IF OBJECT_ID(N'dbo.Orders', N'U') IS NOT NULL DROP TABLE dbo.Orders;
IF OBJECT_ID(N'dbo.Products', N'U') IS NOT NULL DROP TABLE dbo.Products;
IF OBJECT_ID(N'dbo.Customers', N'U') IS NOT NULL DROP TABLE dbo.Customers;
IF OBJECT_ID(N'dbo.Categories', N'U') IS NOT NULL DROP TABLE dbo.Categories;
GO

CREATE TABLE dbo.Categories (
    CategoryId   INT           IDENTITY(1,1) NOT NULL PRIMARY KEY,
    CategoryName NVARCHAR(100) NOT NULL,
    Description  NVARCHAR(500) NULL
);

CREATE TABLE dbo.Customers (
    CustomerId   INT           IDENTITY(1,1) NOT NULL PRIMARY KEY,
    CustomerCode NVARCHAR(20)  NOT NULL UNIQUE,
    FullName     NVARCHAR(200) NOT NULL,
    Email        NVARCHAR(320) NULL,
    Country      NVARCHAR(100) NOT NULL DEFAULT N'US',
    CreatedAt    DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE TABLE dbo.Products (
    ProductId    INT            IDENTITY(1,1) NOT NULL PRIMARY KEY,
    CategoryId   INT            NOT NULL REFERENCES dbo.Categories(CategoryId),
    SKU          NVARCHAR(50)   NOT NULL UNIQUE,
    ProductName  NVARCHAR(200)  NOT NULL,
    ListPrice    DECIMAL(18, 4) NOT NULL,
    IsActive     BIT            NOT NULL DEFAULT 1
);

CREATE TABLE dbo.Orders (
    OrderId      BIGINT         IDENTITY(1,1) NOT NULL PRIMARY KEY,
    CustomerId   INT            NOT NULL REFERENCES dbo.Customers(CustomerId),
    OrderDate    DATE           NOT NULL,
    Status       NVARCHAR(30)   NOT NULL DEFAULT N'Open',
    TotalAmount  DECIMAL(18, 4) NOT NULL DEFAULT 0,
    Notes        NVARCHAR(500)  NULL
);

CREATE TABLE dbo.OrderItems (
    OrderItemId  BIGINT         IDENTITY(1,1) NOT NULL PRIMARY KEY,
    OrderId      BIGINT         NOT NULL REFERENCES dbo.Orders(OrderId),
    ProductId    INT            NOT NULL REFERENCES dbo.Products(ProductId),
    Quantity     INT            NOT NULL CHECK (Quantity > 0),
    UnitPrice    DECIMAL(18, 4) NOT NULL,
    LineTotal    AS (CAST(Quantity * UnitPrice AS DECIMAL(18, 4))) PERSISTED
);

CREATE INDEX IX_Orders_CustomerId ON dbo.Orders(CustomerId);
CREATE INDEX IX_OrderItems_OrderId ON dbo.OrderItems(OrderId);
CREATE INDEX IX_Products_CategoryId ON dbo.Products(CategoryId);

PRINT 'Tables created (Categories, Customers, Products, Orders, OrderItems)';
GO
