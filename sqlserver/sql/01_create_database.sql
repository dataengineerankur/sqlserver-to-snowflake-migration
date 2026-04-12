/* Idempotent database creation for SnowConvert stress / migration lab */
SET NOCOUNT ON;

IF DB_ID(N'SnowConvertStressDB') IS NULL
BEGIN
    CREATE DATABASE SnowConvertStressDB;
    PRINT 'Created database SnowConvertStressDB';
END
ELSE
    PRINT 'Database SnowConvertStressDB already exists';

GO
