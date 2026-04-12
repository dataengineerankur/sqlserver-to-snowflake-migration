output "dms_bucket_name" {
  value       = aws_s3_bucket.dms.bucket
  description = "DMS landing bucket."
}

output "dms_bucket_arn" {
  value       = aws_s3_bucket.dms.arn
  description = "DMS landing bucket ARN."
}

output "dms_role_arn" {
  value       = aws_iam_role.dms_access.arn
  description = "IAM role ARN for DMS S3 access."
}

output "snowflake_storage_role_arn" {
  value       = aws_iam_role.snowflake_storage.arn
  description = "IAM role ARN for Snowflake storage integration."
}

output "redshift_endpoint" {
  value       = var.enable_redshift_serverless ? aws_redshiftserverless_workgroup.redshift[0].endpoint[0].address : (var.enable_redshift ? aws_redshift_cluster.redshift[0].endpoint : "")
  description = "Redshift endpoint address."
}

output "redshift_database" {
  value       = var.enable_redshift ? aws_redshift_cluster.redshift[0].database_name : ""
  description = "Redshift database name."
}

output "redshift_security_group_id" {
  value       = var.enable_redshift ? aws_security_group.redshift[0].id : ""
  description = "Redshift security group ID."
}

output "glue_job_name" {
  value       = var.enable_redshift ? aws_glue_job.redshift_load[0].name : ""
  description = "Glue job name for Redshift load."
}

output "glue_silver_job_name" {
  value       = ""
  description = "Glue job name for silver transforms."
}

output "glue_gold_job_name" {
  value       = ""
  description = "Glue job name for gold transforms."
}

output "glue_silver_customers_job_name" {
  value       = var.enable_glue_athena ? aws_glue_job.silver_customers[0].name : ""
  description = "Glue job name for silver customers transform."
}

output "glue_silver_products_job_name" {
  value       = var.enable_glue_athena ? aws_glue_job.silver_products[0].name : ""
  description = "Glue job name for silver products transform."
}

output "glue_silver_orders_job_name" {
  value       = var.enable_glue_athena ? aws_glue_job.silver_orders[0].name : ""
  description = "Glue job name for silver orders transform."
}

output "glue_gold_customers_job_name" {
  value       = var.enable_glue_athena ? aws_glue_job.gold_customers[0].name : ""
  description = "Glue job name for gold customers transform."
}

output "glue_gold_products_job_name" {
  value       = var.enable_glue_athena ? aws_glue_job.gold_products[0].name : ""
  description = "Glue job name for gold products transform."
}

output "glue_gold_orders_job_name" {
  value       = var.enable_glue_athena ? aws_glue_job.gold_orders[0].name : ""
  description = "Glue job name for gold orders transform."
}

output "step_trigger_lambda_name" {
  value       = var.enable_step_function ? aws_lambda_function.step_trigger[0].function_name : ""
  description = "Lambda function name that triggers the Step Function."
}

output "step_function_arn" {
  value       = var.enable_step_function ? aws_sfn_state_machine.datalake_orchestrator[0].arn : ""
  description = "Step Functions state machine ARN."
}

output "glue_catalog_database_raw" {
  value       = var.enable_glue_athena ? aws_glue_catalog_database.raw[0].name : ""
  description = "Glue Catalog database name for DMS raw landing."
}

output "glue_catalog_database_bronze" {
  value       = var.enable_glue_athena ? aws_glue_catalog_database.bronze[0].name : ""
  description = "Glue Catalog database name for bronze."
}

output "glue_catalog_database_silver" {
  value       = var.enable_glue_athena ? aws_glue_catalog_database.silver[0].name : ""
  description = "Glue Catalog database name for silver."
}

output "glue_catalog_database_gold" {
  value       = var.enable_glue_athena ? aws_glue_catalog_database.gold[0].name : ""
  description = "Glue Catalog database name for gold."
}

output "glue_crawler_raw_name" {
  value       = var.enable_glue_athena ? aws_glue_crawler.raw[0].name : ""
  description = "Glue crawler name for raw data."
}

output "glue_crawler_silver_name" {
  value       = var.enable_glue_athena ? aws_glue_crawler.silver[0].name : ""
  description = "Glue crawler name for silver data."
}

output "glue_crawler_gold_name" {
  value       = var.enable_glue_athena ? aws_glue_crawler.gold[0].name : ""
  description = "Glue crawler name for gold data."
}

output "athena_workgroup_name" {
  value       = var.enable_glue_athena ? aws_athena_workgroup.dms[0].name : ""
  description = "Athena workgroup name."
}

output "dms_replication_instance_arn" {
  value       = aws_dms_replication_instance.dms.replication_instance_arn
  description = "DMS replication instance ARN."
}

output "dms_replication_task_arn" {
  value       = aws_dms_replication_task.full_load_cdc.replication_task_arn
  description = "DMS replication task ARN."
}

output "rds_endpoint" {
  value       = var.use_rds ? aws_db_instance.source[0].address : ""
  description = "RDS Postgres endpoint address."
}

output "rds_port" {
  value       = var.use_rds ? aws_db_instance.source[0].port : 5432
  description = "RDS Postgres port."
}

output "rds_security_group_id" {
  value       = var.use_rds ? aws_security_group.rds[0].id : ""
  description = "RDS security group ID."
}
