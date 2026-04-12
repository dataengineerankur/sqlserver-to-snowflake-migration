resource "snowflake_warehouse" "migration" {
  name           = "WH_MSSQL_MIGRATION"
  warehouse_size = "XSMALL"
  auto_suspend   = 60
  auto_resume    = true
  initially_suspended = true
  comment        = "Lab warehouse for SQL Server → S3 → Snowflake"
}

resource "snowflake_database" "migration" {
  name    = var.database_name
  comment = "SQL Server migration lab — raw + medallion"
}

resource "snowflake_schema" "raw" {
  name     = "RAW_MSSQL"
  database = snowflake_database.migration.name
  comment  = "Snowpipe landing (DMS / Glue paths)"
}

resource "snowflake_schema" "bronze" {
  name     = "BRONZE"
  database = snowflake_database.migration.name
}

resource "snowflake_schema" "silver" {
  name     = "SILVER"
  database = snowflake_database.migration.name
}

resource "snowflake_schema" "gold" {
  name     = "GOLD"
  database = snowflake_database.migration.name
}

resource "snowflake_file_format" "parquet" {
  name                         = "FF_PARQUET"
  database                     = snowflake_database.migration.name
  schema                       = snowflake_schema.raw.name
  format_type                  = "PARQUET"
  compression                  = "AUTO"
}

resource "snowflake_storage_integration" "s3_mssql" {
  name    = "S3_MSSQL_MIGRATION_INT"
  type    = "EXTERNAL_STAGE"
  enabled = true
  storage_allowed_locations = [
    "s3://${var.aws_dms_bucket}/",
    "s3://${var.aws_glue_bucket}/",
  ]
  storage_provider     = "S3"
  storage_aws_role_arn = var.aws_storage_integration_role_arn
}

resource "snowflake_stage" "dms" {
  name                = "STG_DMS_MSSQL"
  database            = snowflake_database.migration.name
  schema              = snowflake_schema.raw.name
  url                 = "s3://${var.aws_dms_bucket}/dms/"
  storage_integration = snowflake_storage_integration.s3_mssql.name
  # file_format omitted — pipes specify FILE_FORMAT = (TYPE = PARQUET) inline
}

resource "snowflake_stage" "glue" {
  name                = "STG_GLUE_MSSQL"
  database            = snowflake_database.migration.name
  schema              = snowflake_schema.raw.name
  url                 = "s3://${var.aws_glue_bucket}/glue/mssql/"
  storage_integration = snowflake_storage_integration.s3_mssql.name
  # file_format omitted — pipes specify FILE_FORMAT = (TYPE = PARQUET) inline
}

# Flexible landing: Parquet rows load as VARIANT (schema drift / many tables).
resource "snowflake_table" "raw_dms_variant" {
  name     = "RAW_DMS_VARIANT"
  database = snowflake_database.migration.name
  schema   = snowflake_schema.raw.name
  column {
    name = "V"
    type = "VARIANT"
  }
  comment = "DMS Parquet → VARIANT; flatten in bronze dbt models"
}

resource "snowflake_table" "raw_glue_variant" {
  name     = "RAW_GLUE_VARIANT"
  database = snowflake_database.migration.name
  schema   = snowflake_schema.raw.name
  column {
    name = "V"
    type = "VARIANT"
  }
  comment = "Glue JDBC incremental Parquet → VARIANT"
}

resource "snowflake_pipe" "dms_raw" {
  database = snowflake_database.migration.name
  schema   = snowflake_schema.raw.name
  name     = "PIPE_DMS_RAW"
  copy_statement = <<-EOT
    COPY INTO ${snowflake_database.migration.name}.${snowflake_schema.raw.name}.${snowflake_table.raw_dms_variant.name}(V)
    FROM @${snowflake_database.migration.name}.${snowflake_schema.raw.name}.${snowflake_stage.dms.name}
    FILE_FORMAT = (TYPE = PARQUET)
  EOT
  auto_ingest = false
}

resource "snowflake_pipe" "glue_raw" {
  database = snowflake_database.migration.name
  schema   = snowflake_schema.raw.name
  name     = "PIPE_GLUE_RAW"
  copy_statement = <<-EOT
    COPY INTO ${snowflake_database.migration.name}.${snowflake_schema.raw.name}.${snowflake_table.raw_glue_variant.name}(V)
    FROM @${snowflake_database.migration.name}.${snowflake_schema.raw.name}.${snowflake_stage.glue.name}
    FILE_FORMAT = (TYPE = PARQUET)
  EOT
  auto_ingest = false
}

# Pipeline observability: one row per DAG run written by the Airflow pipeline task.
resource "snowflake_table" "gold_migration_metadata" {
  name     = "MIGRATION_METADATA"
  database = snowflake_database.migration.name
  schema   = snowflake_schema.gold.name
  comment  = "Pipeline run audit — source DB, row counts, load timestamps per DAG execution"

  column {
    name    = "RUN_ID"
    type    = "VARCHAR(64)"
    comment = "Airflow dag_run.run_id"
  }
  column {
    name    = "SOURCE_DB"
    type    = "VARCHAR(128)"
    comment = "SQL Server database name (e.g. SnowConvertStressDB)"
  }
  column {
    name    = "PIPELINE_STAGE"
    type    = "VARCHAR(32)"
    comment = "RAW | BRONZE | SILVER | GOLD"
  }
  column {
    name    = "ROWS_LOADED"
    type    = "NUMBER(18,0)"
    comment = "Row count written in this stage for this run"
  }
  column {
    name    = "LOADED_AT"
    type    = "TIMESTAMP_NTZ(9)"
    comment = "UTC timestamp when this row was inserted"
  }
  column {
    name    = "STATUS"
    type    = "VARCHAR(16)"
    comment = "SUCCESS | FAILED | PARTIAL"
  }
}
