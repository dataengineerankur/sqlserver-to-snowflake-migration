/* LabCRM_DB — accounts / opportunities + merge proc + instead-of style guard via trigger */
SET NOCOUNT ON;
USE LabCRM_DB;
GO

IF OBJECT_ID(N'dbo.ActivityLog', N'U') IS NOT NULL DROP TABLE dbo.ActivityLog;
IF OBJECT_ID(N'dbo.Opportunities', N'U') IS NOT NULL DROP TABLE dbo.Opportunities;
IF OBJECT_ID(N'dbo.Contacts', N'U') IS NOT NULL DROP TABLE dbo.Contacts;
IF OBJECT_ID(N'dbo.Accounts', N'U') IS NOT NULL DROP TABLE dbo.Accounts;
GO

CREATE TABLE dbo.Accounts (
    AccountId   INT           IDENTITY(1,1) NOT NULL PRIMARY KEY,
    AccountCode NVARCHAR(30)  NOT NULL UNIQUE,
    Name        NVARCHAR(200) NOT NULL,
    Region      NVARCHAR(50)  NOT NULL,
    CreatedAt   DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE TABLE dbo.Contacts (
    ContactId   INT           IDENTITY(1,1) NOT NULL PRIMARY KEY,
    AccountId   INT           NOT NULL REFERENCES dbo.Accounts(AccountId),
    Email       NVARCHAR(320) NOT NULL,
    FullName    NVARCHAR(200) NOT NULL,
    IsPrimary   BIT           NOT NULL DEFAULT 0
);

CREATE TABLE dbo.Opportunities (
    OppId       BIGINT        IDENTITY(1,1) NOT NULL PRIMARY KEY,
    AccountId   INT           NOT NULL REFERENCES dbo.Accounts(AccountId),
    Title       NVARCHAR(200) NOT NULL,
    Stage       NVARCHAR(40)  NOT NULL DEFAULT N'Prospect',
    AmountUsd   DECIMAL(18,2) NOT NULL,
    CloseDate   DATE          NULL
);

CREATE TABLE dbo.ActivityLog (
    LogId BIGINT IDENTITY(1,1) PRIMARY KEY,
    Entity NVARCHAR(50) NOT NULL,
    EntityKey NVARCHAR(100) NOT NULL,
    Note NVARCHAR(500) NULL,
    LoggedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

SET IDENTITY_INSERT dbo.Accounts ON;
INSERT dbo.Accounts (AccountId, AccountCode, Name, Region) VALUES
(1, N'ACME', N'Acme Corp', N'NA'),
(2, N'GLOB', N'Global Foods', N'EU');
SET IDENTITY_INSERT dbo.Accounts OFF;
DBCC CHECKIDENT ('dbo.Accounts', RESEED, 2);

INSERT dbo.Contacts (AccountId, Email, FullName, IsPrimary) VALUES
(1, N'buyer@acme.test', N'Pat Buyer', 1),
(2, N'proc@glob.test', N'Jamie Proc', 1);

INSERT dbo.Opportunities (AccountId, Title, Stage, AmountUsd, CloseDate) VALUES
(1, N'Enterprise renewal', N'Negotiation', 250000, '2025-06-30'),
(2, N'Cold chain rollout', N'Prospect', 120000, NULL);
GO

IF OBJECT_ID(N'dbo.usp_Crm_MergeAccountsFromJson', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_Crm_MergeAccountsFromJson;
IF OBJECT_ID(N'dbo.usp_Crm_ListPipeline', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_Crm_ListPipeline;
GO

CREATE PROCEDURE dbo.usp_Crm_MergeAccountsFromJson @Json NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    MERGE dbo.Accounts AS t
    USING (
        SELECT AccountCode, Name, Region
        FROM OPENJSON(@Json) WITH (
            AccountCode NVARCHAR(30) N'$.AccountCode',
            Name NVARCHAR(200) N'$.Name',
            Region NVARCHAR(50) N'$.Region'
        )
    ) s ON t.AccountCode = s.AccountCode
    WHEN MATCHED THEN UPDATE SET Name = s.Name, Region = s.Region
    WHEN NOT MATCHED THEN INSERT (AccountCode, Name, Region) VALUES (s.AccountCode, s.Name, s.Region);
END;
GO

CREATE PROCEDURE dbo.usp_Crm_ListPipeline @Region NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT o.OppId, a.AccountCode, o.Title, o.Stage, o.AmountUsd
    FROM dbo.Opportunities o
    INNER JOIN dbo.Accounts a ON a.AccountId = o.AccountId
    WHERE @Region IS NULL OR a.Region = @Region
    ORDER BY o.AmountUsd DESC;
END;
GO

IF OBJECT_ID(N'dbo.tr_Opportunities_StageGuard', N'TR') IS NOT NULL DROP TRIGGER dbo.tr_Opportunities_StageGuard;
IF OBJECT_ID(N'dbo.tr_Accounts_Activity', N'TR') IS NOT NULL DROP TRIGGER dbo.tr_Accounts_Activity;
GO

CREATE TRIGGER dbo.tr_Opportunities_StageGuard
ON dbo.Opportunities
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF UPDATE(Stage)
    AND EXISTS (
        SELECT 1 FROM inserted i
        INNER JOIN deleted d ON d.OppId = i.OppId
        WHERE d.Stage = N'Won' AND i.Stage <> N'Won'
    )
    BEGIN
        RAISERROR(N'Cannot move backwards from Won', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END;
END;
GO

CREATE TRIGGER dbo.tr_Accounts_Activity
ON dbo.Accounts
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.ActivityLog (Entity, EntityKey, Note)
    SELECT N'Account', i.AccountCode, N'Upsert'
    FROM inserted i;
END;
GO

PRINT 'LabCRM_DB deployed';
GO
