output "database" {
  value = snowflake_database.migration.name
}

output "storage_integration_name" {
  value       = snowflake_storage_integration.s3_mssql.name
  description = "Run DESC STORAGE INTEGRATION <name> in Snowflake; update IAM role trust with STORAGE_AWS_IAM_USER_ARN + EXTERNAL_ID"
}

output "stage_dms" {
  value = "${snowflake_database.migration.name}.${snowflake_schema.raw.name}.${snowflake_stage.dms.name}"
}

output "stage_glue" {
  value = "${snowflake_database.migration.name}.${snowflake_schema.raw.name}.${snowflake_stage.glue.name}"
}

output "pipe_dms" {
  value = "${snowflake_database.migration.name}.${snowflake_schema.raw.name}.${snowflake_pipe.dms_raw.name}"
}

output "pipe_glue" {
  value = "${snowflake_database.migration.name}.${snowflake_schema.raw.name}.${snowflake_pipe.glue_raw.name}"
}
