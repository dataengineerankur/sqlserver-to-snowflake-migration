/* Three additional migration-lab databases (SnowConvertStressDB remains primary in 01) */
SET NOCOUNT ON;

IF DB_ID(N'LabERP_DB') IS NULL
    CREATE DATABASE LabERP_DB;
IF DB_ID(N'LabCRM_DB') IS NULL
    CREATE DATABASE LabCRM_DB;
IF DB_ID(N'LabInventory_DB') IS NULL
    CREATE DATABASE LabInventory_DB;

PRINT 'Lab databases ensured: LabERP_DB, LabCRM_DB, LabInventory_DB';
GO
