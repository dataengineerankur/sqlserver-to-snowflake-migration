/* Scalar and inline functions */
SET NOCOUNT ON;
USE SnowConvertStressDB;
GO

IF OBJECT_ID(N'dbo.fn_FormatMoney', N'FN') IS NOT NULL
    DROP FUNCTION dbo.fn_FormatMoney;
GO

CREATE FUNCTION dbo.fn_FormatMoney (@amount DECIMAL(18, 4))
RETURNS NVARCHAR(50)
AS
BEGIN
    RETURN N'$' + CONVERT(NVARCHAR(50), CAST(@amount AS MONEY), 1);
END;
GO

IF OBJECT_ID(N'dbo.fn_OrderLineCount', N'IF') IS NOT NULL
    DROP FUNCTION dbo.fn_OrderLineCount;
GO

CREATE FUNCTION dbo.fn_OrderLineCount (@orderId BIGINT)
RETURNS TABLE
AS
RETURN
(
    SELECT COUNT_BIG(*) AS LineCount
    FROM dbo.OrderItems
    WHERE OrderId = @orderId
);
GO

PRINT 'Functions created';
GO
