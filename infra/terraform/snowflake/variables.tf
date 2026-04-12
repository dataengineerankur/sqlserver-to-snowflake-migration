variable "snowflake_account" {
  type        = string
  description = "Account identifier for CI (env SNOWFLAKE_ACCOUNT overrides). Local: read from profile."
  default     = ""
}

variable "snowflake_user" {
  type        = string
  description = "Snowflake login name for CI (env SNOWFLAKE_USER overrides). Local: read from profile."
  default     = ""
}

variable "snowflake_password" {
  type        = string
  sensitive   = true
  description = "Snowflake password for CI (env SNOWFLAKE_PASSWORD overrides). Local: externalbrowser via profile."
  default     = ""
}

variable "snowflake_role" {
  type    = string
  default = "ACCOUNTADMIN"
}

variable "snowflake_region" {
  type        = string
  description = "Snowflake region id for AWS, e.g. us-east-1"
  default     = "us-east-1"
}

variable "aws_dms_bucket" {
  type        = string
  description = "S3 bucket name from CDK DataLanding (DMS only)"
}

variable "aws_glue_bucket" {
  type        = string
  description = "S3 bucket name from CDK DataLanding (Glue only)"
}

variable "aws_storage_integration_role_arn" {
  type        = string
  description = "IAM role ARN Snowflake will assume to read S3 (trust Snowflake + external id after first DESC)"
}

variable "database_name" {
  type    = string
  default = "MSSQL_MIGRATION_LAB"
}
