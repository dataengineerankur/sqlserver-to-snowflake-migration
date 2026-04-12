# Snowflake (Terraform)

Deploys warehouse, database/schemas, storage integration, stages, VARIANT landing tables, and pipes (manual refresh by default).

## Prerequisites

1. **IAM role for storage integration** (in your AWS account) with an S3 policy allowing `s3:GetObject`, `s3:GetObjectVersion`, `s3:ListBucket` on the DMS and Glue bucket ARNs. Put its ARN in Secrets Manager as `storage_iam_role_arn` (see root migration README).

2. **Trust policy (two-step):** After the first `terraform apply`, run in Snowflake:

   `DESC STORAGE INTEGRATION S3_MSSQL_MIGRATION_INT;`

   Set the role’s trust principal to `STORAGE_AWS_IAM_USER_ARN` and condition `sts:ExternalId` = `STORAGE_AWS_EXTERNAL_ID` from that output. Re-run apply if needed.

3. **Secrets Manager** secret `<project>/snowflake/creds` (JSON) used by CodeBuild:

   - `account`, `user`, `role`, `password`
   - `dms_bucket`, `glue_bucket`, `storage_iam_role_arn`
   - optional: `snowflake_region` (defaults to `us-east-1` in pipeline if omitted)

## Local apply

```bash
export TF_VAR_snowflake_account="WBZTWSY-KH99814"
export TF_VAR_snowflake_user="PATCHIT"
export TF_VAR_snowflake_role="ACCOUNTADMIN"
export TF_VAR_snowflake_password="***"
export TF_VAR_aws_dms_bucket="your-dms-bucket"
export TF_VAR_aws_glue_bucket="your-glue-bucket"
export TF_VAR_aws_storage_integration_role_arn="arn:aws:iam::123456789012:role/snowflake-s3"

terraform init -backend=false
terraform plan
terraform apply
```

Never commit passwords or keys.

## Pipes

`auto_ingest` is false by default. Option A: point S3 event notifications at SNS and set `notification_channel` on the pipe (see Snowflake docs). Option B: schedule `ALTER PIPE … REFRESH` / `SYSTEM$PIPE_FORCE_RESUME` from Airflow.
