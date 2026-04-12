/* LabERP_DB — HR / payroll style schema + procedures + triggers (migration stress) */
SET NOCOUNT ON;
USE LabERP_DB;
GO

IF OBJECT_ID(N'dbo.PayrollLines', N'U') IS NOT NULL DROP TABLE dbo.PayrollLines;
IF OBJECT_ID(N'dbo.PayrollRuns', N'U') IS NOT NULL DROP TABLE dbo.PayrollRuns;
IF OBJECT_ID(N'dbo.Employees', N'U') IS NOT NULL DROP TABLE dbo.Employees;
IF OBJECT_ID(N'dbo.Departments', N'U') IS NOT NULL DROP TABLE dbo.Departments;
IF OBJECT_ID(N'dbo.ErpAuditLog', N'U') IS NOT NULL DROP TABLE dbo.ErpAuditLog;
GO

CREATE TABLE dbo.Departments (
    DeptId      INT           IDENTITY(1,1) NOT NULL PRIMARY KEY,
    DeptCode    NVARCHAR(20)  NOT NULL UNIQUE,
    DeptName    NVARCHAR(120) NOT NULL,
    BudgetUsd   DECIMAL(18,2) NOT NULL DEFAULT 0
);

CREATE TABLE dbo.Employees (
    EmployeeId  INT           IDENTITY(1,1) NOT NULL PRIMARY KEY,
    DeptId      INT           NOT NULL REFERENCES dbo.Departments(DeptId),
    EmpCode     NVARCHAR(20)  NOT NULL UNIQUE,
    FullName    NVARCHAR(200) NOT NULL,
    HireDate    DATE          NOT NULL,
    Salary      DECIMAL(18,4) NOT NULL,
    RowVer      ROWVERSION    NOT NULL
);

CREATE TABLE dbo.PayrollRuns (
    RunId       BIGINT        IDENTITY(1,1) NOT NULL PRIMARY KEY,
    RunMonth    CHAR(7)       NOT NULL,
    Status      NVARCHAR(20)  NOT NULL DEFAULT N'Draft',
    CreatedAt   DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE TABLE dbo.PayrollLines (
    LineId      BIGINT        IDENTITY(1,1) NOT NULL PRIMARY KEY,
    RunId       BIGINT        NOT NULL REFERENCES dbo.PayrollRuns(RunId),
    EmployeeId  INT           NOT NULL REFERENCES dbo.Employees(EmployeeId),
    GrossPay    DECIMAL(18,4) NOT NULL,
    NetPay      AS (CAST(GrossPay * CAST(0.92 AS DECIMAL(18,4)) AS DECIMAL(18,4))) PERSISTED
);

CREATE TABLE dbo.ErpAuditLog (
    Id BIGINT IDENTITY(1,1) PRIMARY KEY,
    TableName SYSNAME NOT NULL,
    ActionType NVARCHAR(10) NOT NULL,
    Payload NVARCHAR(MAX) NULL,
    LoggedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

SET IDENTITY_INSERT dbo.Departments ON;
INSERT dbo.Departments (DeptId, DeptCode, DeptName, BudgetUsd) VALUES
(1, N'ENG', N'Engineering', 500000),
(2, N'SALES', N'Sales', 200000),
(3, N'OPS', N'Operations', 150000);
SET IDENTITY_INSERT dbo.Departments OFF;
DBCC CHECKIDENT ('dbo.Departments', RESEED, 3);

SET IDENTITY_INSERT dbo.Employees ON;
INSERT dbo.Employees (EmployeeId, DeptId, EmpCode, FullName, HireDate, Salary) VALUES
(1, 1, N'E001', N'Alex Rivera', '2020-01-15', 120000),
(2, 1, N'E002', N'Jordan Lee', '2021-06-01', 95000),
(3, 2, N'E003', N'Casey Morgan', '2019-03-20', 88000);
SET IDENTITY_INSERT dbo.Employees OFF;
DBCC CHECKIDENT ('dbo.Employees', RESEED, 3);

SET IDENTITY_INSERT dbo.PayrollRuns ON;
INSERT dbo.PayrollRuns (RunId, RunMonth, Status) VALUES (1, N'2025-01', N'Posted');
SET IDENTITY_INSERT dbo.PayrollRuns OFF;
DBCC CHECKIDENT ('dbo.PayrollRuns', RESEED, 1);

INSERT dbo.PayrollLines (RunId, EmployeeId, GrossPay) VALUES
(1, 1, 10000), (1, 2, 7916.67), (1, 3, 7333.33);
GO

IF OBJECT_ID(N'dbo.usp_Erp_DynamicDeptReport', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_Erp_DynamicDeptReport;
IF OBJECT_ID(N'dbo.usp_Erp_ClosePayrollRun', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_Erp_ClosePayrollRun;
GO

CREATE PROCEDURE dbo.usp_Erp_DynamicDeptReport
    @MinSalary DECIMAL(18,4) = NULL,
    @OrderBy   NVARCHAR(32) = N'Salary'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @sql NVARCHAR(MAX);
    DECLARE @ord SYSNAME = CASE WHEN @OrderBy IN (N'Salary', N'HireDate', N'EmpCode') THEN @OrderBy ELSE N'Salary' END;
    SET @sql = N'SELECT e.EmpCode, e.FullName, d.DeptCode, e.Salary FROM dbo.Employees e
      INNER JOIN dbo.Departments d ON d.DeptId = e.DeptId WHERE 1=1'
      + CASE WHEN @MinSalary IS NOT NULL THEN N' AND e.Salary >= @p' ELSE N'' END
      + N' ORDER BY ' + QUOTENAME(@ord);
    EXEC sp_executesql @sql, N'@p DECIMAL(18,4)', @p = @MinSalary;
END;
GO

CREATE PROCEDURE dbo.usp_Erp_ClosePayrollRun @RunId BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.PayrollRuns SET Status = N'Closed' WHERE RunId = @RunId;
END;
GO

IF OBJECT_ID(N'dbo.tr_Employees_Audit', N'TR') IS NOT NULL DROP TRIGGER dbo.tr_Employees_Audit;
IF OBJECT_ID(N'dbo.tr_PayrollLines_Recalc', N'TR') IS NOT NULL DROP TRIGGER dbo.tr_PayrollLines_Recalc;
GO

CREATE TRIGGER dbo.tr_Employees_Audit
ON dbo.Employees
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.ErpAuditLog (TableName, ActionType, Payload)
    SELECT N'Employees', CASE WHEN d.EmployeeId IS NULL THEN N'INSERT' ELSE N'UPDATE' END,
           (SELECT i.EmpCode, i.Salary, i.DeptId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM inserted i LEFT JOIN deleted d ON d.EmployeeId = i.EmployeeId;
END;
GO

CREATE TRIGGER dbo.tr_PayrollLines_Recalc
ON dbo.PayrollLines
AFTER INSERT, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM inserted) OR EXISTS (SELECT 1 FROM deleted)
        UPDATE pr SET Status = N'Adjusted'
        FROM dbo.PayrollRuns pr
        WHERE pr.RunId IN (SELECT RunId FROM inserted UNION SELECT RunId FROM deleted);
END;
GO

PRINT 'LabERP_DB deployed';
GO
