/* Seed data — safe to re-run after 02_tables (which drops dependent objects) */
SET NOCOUNT ON;
USE SnowConvertStressDB;
GO

SET IDENTITY_INSERT dbo.Categories ON;
MERGE dbo.Categories AS t
USING (VALUES
    (1, N'Electronics', N'Devices and accessories'),
    (2, N'Apparel', N'Clothing'),
    (3, N'Home', N'Kitchen and decor')
) AS s(CategoryId, CategoryName, Description)
ON t.CategoryId = s.CategoryId
WHEN NOT MATCHED THEN INSERT (CategoryId, CategoryName, Description) VALUES (s.CategoryId, s.CategoryName, s.Description);
SET IDENTITY_INSERT dbo.Categories OFF;
GO

DBCC CHECKIDENT ('dbo.Categories', RESEED, 3);
GO

SET IDENTITY_INSERT dbo.Customers ON;
MERGE dbo.Customers AS t
USING (VALUES
    (1, N'CUST-001', N'Ada Lovelace', N'ada@example.com', N'UK'),
    (2, N'CUST-002', N'Alan Turing', N'alan@example.com', N'UK'),
    (3, N'CUST-003', N'Grace Hopper', N'grace@example.com', N'US'),
    (4, N'CUST-004', N'Donald Knuth', N'don@example.com', N'US'),
    (5, N'CUST-005', N'Barbara Liskov', N'barbara@example.com', N'US')
) AS s(CustomerId, CustomerCode, FullName, Email, Country)
ON t.CustomerId = s.CustomerId
WHEN NOT MATCHED THEN INSERT (CustomerId, CustomerCode, FullName, Email, Country)
VALUES (s.CustomerId, s.CustomerCode, s.FullName, s.Email, s.Country);
SET IDENTITY_INSERT dbo.Customers OFF;
GO

DBCC CHECKIDENT ('dbo.Customers', RESEED, 5);
GO

SET IDENTITY_INSERT dbo.Products ON;
MERGE dbo.Products AS t
USING (VALUES
    (1, 1, N'SKU-E-100', N'Noise-Canceling Headphones', 249.9900, 1),
    (2, 1, N'SKU-E-101', N'USB-C Dock', 129.5000, 1),
    (3, 2, N'SKU-A-200', N'Running Jacket', 89.9900, 1),
    (4, 3, N'SKU-H-300', N'Pour-Over Kettle', 45.0000, 1),
    (5, 3, N'SKU-H-301', N'Ceramic Mug Set', 32.5000, 1)
) AS s(ProductId, CategoryId, SKU, ProductName, ListPrice, IsActive)
ON t.ProductId = s.ProductId
WHEN NOT MATCHED THEN INSERT (ProductId, CategoryId, SKU, ProductName, ListPrice, IsActive)
VALUES (s.ProductId, s.CategoryId, s.SKU, s.ProductName, s.ListPrice, s.IsActive);
SET IDENTITY_INSERT dbo.Products OFF;
GO

DBCC CHECKIDENT ('dbo.Products', RESEED, 5);
GO

SET IDENTITY_INSERT dbo.Orders ON;
MERGE dbo.Orders AS t
USING (VALUES
    (1, 1, CAST('2025-01-10' AS DATE), N'Closed', 379.9800, N'Web order'),
    (2, 2, CAST('2025-01-12' AS DATE), N'Open', 129.5000, NULL),
    (3, 3, CAST('2025-02-01' AS DATE), N'Shipped', 134.9900, N'Expedited'),
    (4, 4, CAST('2025-02-05' AS DATE), N'Open', 77.5000, NULL),
    (5, 5, CAST('2025-02-07' AS DATE), N'Closed', 249.9900, N'Gift wrap')
) AS s(OrderId, CustomerId, OrderDate, Status, TotalAmount, Notes)
ON t.OrderId = s.OrderId
WHEN NOT MATCHED THEN INSERT (OrderId, CustomerId, OrderDate, Status, TotalAmount, Notes)
VALUES (s.OrderId, s.CustomerId, s.OrderDate, s.Status, s.TotalAmount, s.Notes);
SET IDENTITY_INSERT dbo.Orders OFF;
GO

DBCC CHECKIDENT ('dbo.Orders', RESEED, 5);
GO

SET IDENTITY_INSERT dbo.OrderItems ON;
MERGE dbo.OrderItems AS t
USING (VALUES
    (1, 1, 1, 1, 249.9900),
    (2, 1, 2, 1, 129.9900),
    (3, 2, 2, 1, 129.5000),
    (4, 3, 3, 1, 89.9900),
    (5, 3, 4, 1, 45.0000),
    (6, 4, 5, 2, 32.5000),
    (7, 5, 1, 1, 249.9900)
) AS s(OrderItemId, OrderId, ProductId, Quantity, UnitPrice)
ON t.OrderItemId = s.OrderItemId
WHEN NOT MATCHED THEN INSERT (OrderItemId, OrderId, ProductId, Quantity, UnitPrice)
VALUES (s.OrderItemId, s.OrderId, s.ProductId, s.Quantity, s.UnitPrice);
SET IDENTITY_INSERT dbo.OrderItems OFF;
GO

DBCC CHECKIDENT ('dbo.OrderItems', RESEED, 7);
GO

PRINT 'Seed data applied';
GO
