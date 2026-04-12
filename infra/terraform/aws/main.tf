data "aws_caller_identity" "current" {}

data "aws_vpc" "default" {
  count   = var.dms_vpc_id == null ? 1 : 0
  default = true
}

data "aws_subnets" "default" {
  count = length(var.dms_subnet_ids) == 0 ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [local.dms_vpc_id]
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

locals {
  dms_vpc_id     = var.dms_vpc_id != null ? var.dms_vpc_id : data.aws_vpc.default[0].id
  dms_subnet_ids = length(var.dms_subnet_ids) > 0 ? var.dms_subnet_ids : data.aws_subnets.default[0].ids

  snowflake_principal_arn = var.snowflake_aws_iam_user_arn != "" ? var.snowflake_aws_iam_user_arn : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
  snowflake_external_id   = var.snowflake_external_id != "" ? var.snowflake_external_id : null

  bucket_name = var.bucket_name != "" ? var.bucket_name : "${var.project_name}-${var.environment}-${random_id.bucket_suffix.hex}"

  source_host = var.use_rds ? aws_db_instance.source[0].address : var.postgres_host

  redshift_enabled = var.enable_redshift || var.enable_redshift_serverless

  redshift_jdbc_url = local.redshift_enabled ? (var.enable_redshift_serverless ? "jdbc:redshift://${try(aws_redshiftserverless_workgroup.redshift[0].endpoint[0].address, "")}:5439/${var.redshift_database}" : "jdbc:redshift://${try(aws_redshift_cluster.redshift[0].endpoint, "")}:5439/${var.redshift_database}") : ""
}

resource "aws_s3_bucket" "dms" {
  bucket = local.bucket_name
  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "dms" {
  bucket                  = aws_s3_bucket.dms.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "dms" {
  bucket = aws_s3_bucket.dms.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "dms" {
  bucket = aws_s3_bucket.dms.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_notification" "snowpipe" {
  count  = length(var.snowpipe_sqs_queue_arns) > 0 ? 1 : 0
  bucket = aws_s3_bucket.dms.id

  dynamic "queue" {
    for_each = var.snowpipe_sqs_queue_arns
    content {
      queue_arn     = queue.value
      events        = ["s3:ObjectCreated:*"]
      filter_prefix = "dms/sales/${queue.key}/"
    }
  }
}

resource "aws_iam_role" "dms_access" {
  name = "${var.project_name}-${var.environment}-dms-s3-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "dms.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role" "dms_vpc_role" {
  name = "dms-vpc-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "dms.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "dms_vpc_role" {
  role       = aws_iam_role.dms_vpc_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
}

resource "aws_iam_role_policy" "dms_access" {
  name = "${var.project_name}-${var.environment}-dms-s3-policy"
  role = aws_iam_role.dms_access.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:PutObjectTagging",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.dms.arn,
          "${aws_s3_bucket.dms.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "dms" {
  name              = "/aws/dms/${var.project_name}-${var.environment}"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_stream" "dms_task" {
  name           = "dms-task"
  log_group_name = aws_cloudwatch_log_group.dms.name
}

resource "aws_security_group" "dms" {
  name   = "${var.project_name}-${var.environment}-dms-sg"
  vpc_id = local.dms_vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds" {
  count  = var.use_rds ? 1 : 0
  name   = "${var.project_name}-${var.environment}-rds-sg"
  vpc_id = local.dms_vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "rds_from_dms" {
  count                    = var.use_rds ? 1 : 0
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds[0].id
  source_security_group_id = aws_security_group.dms.id
}

resource "aws_security_group_rule" "rds_from_cidrs" {
  count             = var.use_rds && length(var.rds_allowed_cidrs) > 0 ? 1 : 0
  type              = "ingress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  security_group_id = aws_security_group.rds[0].id
  cidr_blocks       = var.rds_allowed_cidrs
}

resource "aws_dms_replication_subnet_group" "dms" {
  replication_subnet_group_description = "DMS subnet group"
  replication_subnet_group_id          = "${var.project_name}-${var.environment}-dms-subnets"
  subnet_ids                           = local.dms_subnet_ids
}

resource "aws_dms_replication_instance" "dms" {
  replication_instance_id     = "${var.project_name}-${var.environment}-dms"
  replication_instance_class  = var.dms_replication_instance_class
  allocated_storage           = var.dms_allocated_storage_gb
  vpc_security_group_ids      = [aws_security_group.dms.id]
  replication_subnet_group_id = aws_dms_replication_subnet_group.dms.id
  multi_az                    = false
  publicly_accessible         = true
}

resource "aws_dms_endpoint" "source" {
  endpoint_id   = "${var.project_name}-${var.environment}-pg-source"
  endpoint_type = "source"
  engine_name   = "postgres"

  server_name   = local.source_host
  port          = var.postgres_port
  database_name = var.postgres_db
  username      = var.postgres_user
  password      = var.postgres_password
  ssl_mode      = "require"
}

resource "aws_dms_endpoint" "target" {
  endpoint_id   = "${var.project_name}-${var.environment}-s3-target"
  endpoint_type = "target"
  engine_name   = "s3"

  s3_settings {
    bucket_name               = aws_s3_bucket.dms.bucket
    bucket_folder             = "dms"
    compression_type          = "GZIP"
    data_format               = "parquet"
    parquet_version           = "parquet-1-0"
    service_access_role_arn   = aws_iam_role.dms_access.arn
    date_partition_enabled    = true
    date_partition_sequence   = "YYYYMMDD"
    date_partition_delimiter  = "SLASH"
    include_op_for_full_load  = true
    timestamp_column_name     = "dms_commit_ts"
  }
}

resource "aws_dms_replication_task" "full_load_cdc" {
  replication_task_id       = "${var.project_name}-${var.environment}-full-cdc"
  replication_instance_arn  = aws_dms_replication_instance.dms.replication_instance_arn
  source_endpoint_arn       = aws_dms_endpoint.source.endpoint_arn
  target_endpoint_arn       = aws_dms_endpoint.target.endpoint_arn
  migration_type            = "full-load-and-cdc"
  table_mappings            = file("${path.module}/table_mappings.json")
  replication_task_settings = file("${path.module}/dms_task_settings.json")
  start_replication_task    = false
}

resource "aws_db_subnet_group" "rds" {
  count       = var.use_rds ? 1 : 0
  name        = "${var.project_name}-${var.environment}-rds-subnets"
  description = "RDS subnet group"
  subnet_ids  = local.dms_subnet_ids
}

resource "aws_db_parameter_group" "rds" {
  count  = var.use_rds ? 1 : 0
  name   = "${var.project_name}-${var.environment}-rds-params"
  family = var.rds_parameter_group_family

  parameter {
    apply_method = "pending-reboot"
    name  = "rds.logical_replication"
    value = "1"
  }

  parameter {
    apply_method = "pending-reboot"
    name  = "max_replication_slots"
    value = "5"
  }

  parameter {
    apply_method = "pending-reboot"
    name  = "max_wal_senders"
    value = "5"
  }
}

resource "aws_db_instance" "source" {
  count                   = var.use_rds ? 1 : 0
  identifier              = "${var.project_name}-${var.environment}-pg"
  engine                  = "postgres"
  engine_version          = var.rds_engine_version
  instance_class          = var.rds_instance_class
  allocated_storage       = var.rds_allocated_storage_gb
  db_subnet_group_name    = aws_db_subnet_group.rds[0].name
  vpc_security_group_ids  = [aws_security_group.rds[0].id]
  db_name                 = var.postgres_db
  username                = var.postgres_user
  password                = var.postgres_password
  parameter_group_name    = aws_db_parameter_group.rds[0].name
  publicly_accessible     = var.rds_publicly_accessible
  skip_final_snapshot     = true
  apply_immediately       = true
}

resource "aws_iam_role" "snowflake_storage" {
  name = "${var.project_name}-${var.environment}-snowflake-storage-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      merge(
        {
          Effect = "Allow"
          Principal = {
            AWS = local.snowflake_principal_arn
          }
          Action = "sts:AssumeRole"
        },
        local.snowflake_external_id == null ? {} : {
          Condition = {
            StringEquals = {
              "sts:ExternalId" = local.snowflake_external_id
            }
          }
        }
      )
    ]
  })
}

resource "aws_iam_role_policy" "snowflake_storage" {
  name = "${var.project_name}-${var.environment}-snowflake-storage-policy"
  role = aws_iam_role.snowflake_storage.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.dms.arn,
          "${aws_s3_bucket.dms.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role" "redshift_s3" {
  count = local.redshift_enabled ? 1 : 0
  name  = "${var.project_name}-${var.environment}-redshift-s3-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "redshift.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "redshift_s3" {
  count = local.redshift_enabled ? 1 : 0
  name  = "${var.project_name}-${var.environment}-redshift-s3-policy"
  role  = aws_iam_role.redshift_s3[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.dms.arn,
          "${aws_s3_bucket.dms.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role" "glue" {
  count = var.enable_glue_athena ? 1 : 0
  name  = "${var.project_name}-${var.environment}-glue-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  count      = var.enable_glue_athena ? 1 : 0
  role       = aws_iam_role.glue[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_s3" {
  count = var.enable_glue_athena ? 1 : 0
  name  = "${var.project_name}-${var.environment}-glue-s3-policy"
  role  = aws_iam_role.glue[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:AbortMultipartUpload"
        ]
        Resource = [
          aws_s3_bucket.dms.arn,
          "${aws_s3_bucket.dms.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_security_group" "redshift" {
  count  = local.redshift_enabled ? 1 : 0
  name   = "${var.project_name}-${var.environment}-redshift-sg"
  vpc_id = local.dms_vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "redshift_from_cidrs" {
  count             = local.redshift_enabled && length(var.redshift_allowed_cidrs) > 0 ? 1 : 0
  type              = "ingress"
  from_port         = 5439
  to_port           = 5439
  protocol          = "tcp"
  security_group_id = aws_security_group.redshift[0].id
  cidr_blocks       = var.redshift_allowed_cidrs
}

resource "aws_security_group" "glue" {
  count  = local.redshift_enabled ? 1 : 0
  name   = "${var.project_name}-${var.environment}-glue-sg"
  vpc_id = local.dms_vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "redshift_from_glue" {
  count                    = local.redshift_enabled ? 1 : 0
  type                     = "ingress"
  from_port                = 5439
  to_port                  = 5439
  protocol                 = "tcp"
  security_group_id        = aws_security_group.redshift[0].id
  source_security_group_id = aws_security_group.glue[0].id
}

resource "aws_redshift_subnet_group" "redshift" {
  count       = var.enable_redshift ? 1 : 0
  name        = "${var.project_name}-${var.environment}-redshift-subnets"
  description = "Redshift subnet group"
  subnet_ids  = local.dms_subnet_ids
}

resource "aws_redshift_cluster" "redshift" {
  count                      = var.enable_redshift ? 1 : 0
  cluster_identifier         = var.redshift_cluster_identifier
  node_type                  = var.redshift_node_type
  cluster_type               = "single-node"
  master_username            = var.redshift_master_username
  master_password            = var.redshift_master_password
  database_name              = var.redshift_database
  publicly_accessible        = var.redshift_publicly_accessible
  vpc_security_group_ids     = [aws_security_group.redshift[0].id]
  cluster_subnet_group_name  = aws_redshift_subnet_group.redshift[0].name
  iam_roles                  = [aws_iam_role.redshift_s3[0].arn]
  skip_final_snapshot        = true
  automated_snapshot_retention_period = 1
}

resource "aws_redshiftserverless_namespace" "redshift" {
  count = var.enable_redshift_serverless ? 1 : 0
  namespace_name      = var.redshift_serverless_namespace
  db_name             = var.redshift_database
  admin_username      = var.redshift_master_username
  admin_user_password = var.redshift_master_password
  iam_roles           = [aws_iam_role.redshift_s3[0].arn]
}

resource "aws_redshiftserverless_workgroup" "redshift" {
  count = var.enable_redshift_serverless ? 1 : 0
  workgroup_name = var.redshift_serverless_workgroup
  namespace_name = aws_redshiftserverless_namespace.redshift[0].namespace_name
  base_capacity  = var.redshift_serverless_base_capacity
  subnet_ids     = local.dms_subnet_ids
  security_group_ids = [aws_security_group.redshift[0].id]
  publicly_accessible = var.redshift_publicly_accessible
}

resource "aws_glue_connection" "redshift" {
  count = local.redshift_enabled ? 1 : 0
  name  = "${var.project_name}-${var.environment}-redshift-conn"

  connection_properties = {
    JDBC_CONNECTION_URL = local.redshift_jdbc_url
    USERNAME            = var.redshift_master_username
    PASSWORD            = var.redshift_master_password
  }

  physical_connection_requirements {
    subnet_id              = local.dms_subnet_ids[0]
    security_group_id_list = [aws_security_group.glue[0].id]
  }
}

resource "aws_glue_job" "redshift_load" {
  count    = local.redshift_enabled ? 1 : 0
  name     = var.glue_job_name
  role_arn = aws_iam_role.glue[0].arn

  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "s3://${aws_s3_bucket.dms.bucket}/glue/redshift_load.py"
  }

  glue_version       = "4.0"
  worker_type        = var.glue_worker_type
  number_of_workers  = var.glue_number_of_workers
  timeout            = var.glue_timeout_minutes
  connections        = [aws_glue_connection.redshift[0].name]

  default_arguments = {
    "--job-language"            = "python"
    "--enable-glue-datacatalog" = "true"
    "--TempDir"                 = "s3://${aws_s3_bucket.dms.bucket}/glue/tmp/"
    "--S3_BUCKET"               = aws_s3_bucket.dms.bucket
    "--REDSHIFT_SCHEMA"         = "raw"
    "--REDSHIFT_CONNECTION_NAME" = aws_glue_connection.redshift[0].name
  }
}

resource "aws_s3_object" "glue_script" {
  count  = local.redshift_enabled ? 1 : 0
  bucket = aws_s3_bucket.dms.bucket
  key    = "glue/redshift_load.py"
  source = "${path.module}/../../scripts/glue/redshift_load.py"
  etag   = filemd5("${path.module}/../../scripts/glue/redshift_load.py")
}

resource "aws_glue_job" "silver_transform" {
  count    = 0
  name     = var.glue_silver_job_name
  role_arn = aws_iam_role.glue[0].arn

  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "s3://${aws_s3_bucket.dms.bucket}/glue/silver_transform.py"
  }

  glue_version       = "4.0"
  worker_type        = var.glue_worker_type
  number_of_workers  = var.glue_number_of_workers
  timeout            = var.glue_timeout_minutes

  default_arguments = {
    "--job-language"            = "python"
    "--enable-glue-datacatalog" = "true"
    "--TempDir"                 = "s3://${aws_s3_bucket.dms.bucket}/glue/tmp/"
    "--S3_BUCKET"               = aws_s3_bucket.dms.bucket
  }
}

resource "aws_glue_job" "gold_transform" {
  count    = 0
  name     = var.glue_gold_job_name
  role_arn = aws_iam_role.glue[0].arn

  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "s3://${aws_s3_bucket.dms.bucket}/glue/gold_transform.py"
  }

  glue_version       = "4.0"
  worker_type        = var.glue_worker_type
  number_of_workers  = var.glue_number_of_workers
  timeout            = var.glue_timeout_minutes

  default_arguments = {
    "--job-language"            = "python"
    "--enable-glue-datacatalog" = "true"
    "--TempDir"                 = "s3://${aws_s3_bucket.dms.bucket}/glue/tmp/"
    "--S3_BUCKET"               = aws_s3_bucket.dms.bucket
  }
}

resource "aws_s3_object" "glue_silver_script" {
  count  = 0
  bucket = aws_s3_bucket.dms.bucket
  key    = "glue/silver_transform.py"
  source = "${path.module}/../../scripts/glue/silver_transform.py"
  etag   = filemd5("${path.module}/../../scripts/glue/silver_transform.py")
}

resource "aws_s3_object" "glue_gold_script" {
  count  = 0
  bucket = aws_s3_bucket.dms.bucket
  key    = "glue/gold_transform.py"
  source = "${path.module}/../../scripts/glue/gold_transform.py"
  etag   = filemd5("${path.module}/../../scripts/glue/gold_transform.py")
}

resource "aws_s3_object" "glue_silver_customers_script" {
  count  = var.enable_glue_athena ? 1 : 0
  bucket = aws_s3_bucket.dms.bucket
  key    = "glue/silver_customers.py"
  source = "${path.module}/../../scripts/glue/silver_customers.py"
  etag   = filemd5("${path.module}/../../scripts/glue/silver_customers.py")
}

resource "aws_s3_object" "glue_silver_products_script" {
  count  = var.enable_glue_athena ? 1 : 0
  bucket = aws_s3_bucket.dms.bucket
  key    = "glue/silver_products.py"
  source = "${path.module}/../../scripts/glue/silver_products.py"
  etag   = filemd5("${path.module}/../../scripts/glue/silver_products.py")
}

resource "aws_s3_object" "glue_silver_orders_script" {
  count  = var.enable_glue_athena ? 1 : 0
  bucket = aws_s3_bucket.dms.bucket
  key    = "glue/silver_orders.py"
  source = "${path.module}/../../scripts/glue/silver_orders.py"
  etag   = filemd5("${path.module}/../../scripts/glue/silver_orders.py")
}

resource "aws_s3_object" "glue_gold_customers_script" {
  count  = var.enable_glue_athena ? 1 : 0
  bucket = aws_s3_bucket.dms.bucket
  key    = "glue/gold_customers.py"
  source = "${path.module}/../../scripts/glue/gold_customers.py"
  etag   = filemd5("${path.module}/../../scripts/glue/gold_customers.py")
}

resource "aws_s3_object" "glue_gold_products_script" {
  count  = var.enable_glue_athena ? 1 : 0
  bucket = aws_s3_bucket.dms.bucket
  key    = "glue/gold_products.py"
  source = "${path.module}/../../scripts/glue/gold_products.py"
  etag   = filemd5("${path.module}/../../scripts/glue/gold_products.py")
}

resource "aws_s3_object" "glue_gold_orders_script" {
  count  = var.enable_glue_athena ? 1 : 0
  bucket = aws_s3_bucket.dms.bucket
  key    = "glue/gold_orders.py"
  source = "${path.module}/../../scripts/glue/gold_orders.py"
  etag   = filemd5("${path.module}/../../scripts/glue/gold_orders.py")
}

resource "aws_s3_object" "glue_raw_ingest_script" {
  count  = var.enable_datalake_ingest ? 1 : 0
  bucket = aws_s3_bucket.dms.bucket
  key    = "glue/raw_ingest.py"
  source = "${path.module}/../../scripts/glue/raw_ingest.py"
  etag   = filemd5("${path.module}/../../scripts/glue/raw_ingest.py")
}

resource "aws_glue_job" "silver_customers" {
  count    = var.enable_glue_athena ? 1 : 0
  name     = var.glue_silver_customers_job_name
  role_arn = aws_iam_role.glue[0].arn

  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "s3://${aws_s3_bucket.dms.bucket}/glue/silver_customers.py"
  }

  glue_version       = "4.0"
  worker_type        = var.glue_worker_type
  number_of_workers  = var.glue_number_of_workers
  timeout            = var.glue_timeout_minutes

  default_arguments = {
    "--job-language"            = "python"
    "--enable-glue-datacatalog" = "true"
    "--TempDir"                 = "s3://${aws_s3_bucket.dms.bucket}/glue/tmp/"
    "--S3_BUCKET"               = aws_s3_bucket.dms.bucket
    "--RAW_PREFIX"              = var.raw_prefix
    "--SILVER_PREFIX"           = var.silver_prefix
  }
}

resource "aws_glue_job" "silver_products" {
  count    = var.enable_glue_athena ? 1 : 0
  name     = var.glue_silver_products_job_name
  role_arn = aws_iam_role.glue[0].arn

  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "s3://${aws_s3_bucket.dms.bucket}/glue/silver_products.py"
  }

  glue_version       = "4.0"
  worker_type        = var.glue_worker_type
  number_of_workers  = var.glue_number_of_workers
  timeout            = var.glue_timeout_minutes

  default_arguments = {
    "--job-language"            = "python"
    "--enable-glue-datacatalog" = "true"
    "--TempDir"                 = "s3://${aws_s3_bucket.dms.bucket}/glue/tmp/"
    "--S3_BUCKET"               = aws_s3_bucket.dms.bucket
    "--RAW_PREFIX"              = var.raw_prefix
    "--SILVER_PREFIX"           = var.silver_prefix
  }
}

resource "aws_glue_job" "silver_orders" {
  count    = var.enable_glue_athena ? 1 : 0
  name     = var.glue_silver_orders_job_name
  role_arn = aws_iam_role.glue[0].arn

  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "s3://${aws_s3_bucket.dms.bucket}/glue/silver_orders.py"
  }

  glue_version       = "4.0"
  worker_type        = var.glue_worker_type
  number_of_workers  = var.glue_number_of_workers
  timeout            = var.glue_timeout_minutes

  default_arguments = {
    "--job-language"            = "python"
    "--enable-glue-datacatalog" = "true"
    "--TempDir"                 = "s3://${aws_s3_bucket.dms.bucket}/glue/tmp/"
    "--S3_BUCKET"               = aws_s3_bucket.dms.bucket
    "--RAW_PREFIX"              = var.raw_prefix
    "--SILVER_PREFIX"           = var.silver_prefix
  }
}

resource "aws_glue_job" "gold_customers" {
  count    = var.enable_glue_athena ? 1 : 0
  name     = var.glue_gold_customers_job_name
  role_arn = aws_iam_role.glue[0].arn

  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "s3://${aws_s3_bucket.dms.bucket}/glue/gold_customers.py"
  }

  glue_version       = "4.0"
  worker_type        = var.glue_worker_type
  number_of_workers  = var.glue_number_of_workers
  timeout            = var.glue_timeout_minutes

  default_arguments = {
    "--job-language"            = "python"
    "--enable-glue-datacatalog" = "true"
    "--TempDir"                 = "s3://${aws_s3_bucket.dms.bucket}/glue/tmp/"
    "--S3_BUCKET"               = aws_s3_bucket.dms.bucket
    "--SILVER_PREFIX"           = var.silver_prefix
    "--GOLD_PREFIX"             = var.gold_prefix
  }
}

resource "aws_glue_job" "gold_products" {
  count    = var.enable_glue_athena ? 1 : 0
  name     = var.glue_gold_products_job_name
  role_arn = aws_iam_role.glue[0].arn

  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "s3://${aws_s3_bucket.dms.bucket}/glue/gold_products.py"
  }

  glue_version       = "4.0"
  worker_type        = var.glue_worker_type
  number_of_workers  = var.glue_number_of_workers
  timeout            = var.glue_timeout_minutes

  default_arguments = {
    "--job-language"            = "python"
    "--enable-glue-datacatalog" = "true"
    "--TempDir"                 = "s3://${aws_s3_bucket.dms.bucket}/glue/tmp/"
    "--S3_BUCKET"               = aws_s3_bucket.dms.bucket
    "--SILVER_PREFIX"           = var.silver_prefix
    "--GOLD_PREFIX"             = var.gold_prefix
  }
}

resource "aws_glue_job" "gold_orders" {
  count    = var.enable_glue_athena ? 1 : 0
  name     = var.glue_gold_orders_job_name
  role_arn = aws_iam_role.glue[0].arn

  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "s3://${aws_s3_bucket.dms.bucket}/glue/gold_orders.py"
  }

  glue_version       = "4.0"
  worker_type        = var.glue_worker_type
  number_of_workers  = var.glue_number_of_workers
  timeout            = var.glue_timeout_minutes

  default_arguments = {
    "--job-language"            = "python"
    "--enable-glue-datacatalog" = "true"
    "--TempDir"                 = "s3://${aws_s3_bucket.dms.bucket}/glue/tmp/"
    "--S3_BUCKET"               = aws_s3_bucket.dms.bucket
    "--SILVER_PREFIX"           = var.silver_prefix
    "--GOLD_PREFIX"             = var.gold_prefix
  }
}

resource "aws_glue_job" "raw_ingest" {
  count    = var.enable_datalake_ingest ? 1 : 0
  name     = var.glue_raw_ingest_job_name
  role_arn = aws_iam_role.glue[0].arn

  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "s3://${aws_s3_bucket.dms.bucket}/glue/raw_ingest.py"
  }

  glue_version       = "4.0"
  worker_type        = var.glue_worker_type
  number_of_workers  = var.glue_number_of_workers
  timeout            = var.glue_timeout_minutes

  default_arguments = {
    "--job-language"            = "python"
    "--enable-glue-datacatalog" = "true"
    "--TempDir"                 = "s3://${aws_s3_bucket.dms.bucket}/glue/tmp/"
    "--SOURCE_BUCKET"           = var.datalake_source_bucket
    "--SOURCE_PREFIX"           = var.datalake_source_prefix
    "--TARGET_BUCKET"           = aws_s3_bucket.dms.bucket
    "--RAW_PREFIX"              = var.raw_prefix
  }
}

resource "aws_glue_catalog_database" "raw" {
  count = var.enable_glue_athena ? 1 : 0
  name  = var.glue_catalog_database_raw
}

resource "aws_glue_catalog_database" "bronze" {
  count = var.enable_glue_athena ? 1 : 0
  name  = var.glue_catalog_database_bronze
}

resource "aws_glue_catalog_database" "silver" {
  count = var.enable_glue_athena ? 1 : 0
  name  = var.glue_catalog_database_silver
}

resource "aws_glue_catalog_database" "gold" {
  count = var.enable_glue_athena ? 1 : 0
  name  = var.glue_catalog_database_gold
}

resource "aws_glue_crawler" "raw" {
  count         = var.enable_glue_athena ? 1 : 0
  name          = var.glue_crawler_raw_name
  role          = aws_iam_role.glue[0].arn
  database_name = aws_glue_catalog_database.raw[0].name

  s3_target {
    path = "s3://${aws_s3_bucket.dms.bucket}/dms/"
    exclusions = [
      "**/awsdms_*"
    ]
  }

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }

  configuration = jsonencode({
    Version = 1.0
    Grouping = {
      TableLevelConfiguration = 2
      TableGroupingPolicy     = "CombineCompatibleSchemas"
    }
  })
}

resource "aws_glue_crawler" "bronze" {
  count         = var.enable_glue_athena ? 1 : 0
  name          = var.glue_crawler_bronze_name
  role          = aws_iam_role.glue[0].arn
  database_name = aws_glue_catalog_database.bronze[0].name

  s3_target {
    path = "s3://${aws_s3_bucket.dms.bucket}/${var.raw_prefix}/"
  }

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }

  configuration = jsonencode({
    Version = 1.0
    Grouping = {
      TableLevelConfiguration = 2
      TableGroupingPolicy     = "CombineCompatibleSchemas"
    }
  })
}

resource "aws_glue_crawler" "silver" {
  count         = var.enable_glue_athena ? 1 : 0
  name          = var.glue_crawler_silver_name
  role          = aws_iam_role.glue[0].arn
  database_name = aws_glue_catalog_database.silver[0].name

  s3_target {
    path = "s3://${aws_s3_bucket.dms.bucket}/${var.silver_prefix}/"
  }

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }

  configuration = jsonencode({
    Version = 1.0
    Grouping = {
      TableLevelConfiguration = 3
      TableGroupingPolicy     = "CombineCompatibleSchemas"
    }
  })

  depends_on = [
    aws_glue_job.silver_customers,
    aws_glue_job.silver_products,
    aws_glue_job.silver_orders
  ]
}

resource "aws_glue_crawler" "gold" {
  count         = var.enable_glue_athena ? 1 : 0
  name          = var.glue_crawler_gold_name
  role          = aws_iam_role.glue[0].arn
  database_name = aws_glue_catalog_database.gold[0].name

  s3_target {
    path = "s3://${aws_s3_bucket.dms.bucket}/${var.gold_prefix}/"
  }

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }

  configuration = jsonencode({
    Version = 1.0
    Grouping = {
      TableLevelConfiguration = 3
      TableGroupingPolicy     = "CombineCompatibleSchemas"
    }
  })

  depends_on = [
    aws_glue_job.gold_customers,
    aws_glue_job.gold_products,
    aws_glue_job.gold_orders
  ]
}

resource "aws_athena_workgroup" "dms" {
  count = var.enable_glue_athena ? 1 : 0
  name = var.athena_workgroup_name

  configuration {
    enforce_workgroup_configuration = true
    publish_cloudwatch_metrics_enabled = false

    result_configuration {
      output_location = "s3://${aws_s3_bucket.dms.bucket}/${var.athena_output_prefix}"
    }
  }
}

data "archive_file" "step_trigger" {
  count       = var.enable_step_function ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/../../scripts/lambda/trigger_step_function.py"
  output_path = "${path.module}/.terraform/trigger_step_function.zip"
}

resource "aws_iam_role" "step_trigger" {
  count = var.enable_step_function ? 1 : 0
  name  = "${var.project_name}-${var.environment}-step-trigger-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "step_trigger_basic" {
  count      = var.enable_step_function ? 1 : 0
  role       = aws_iam_role.step_trigger[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "step_trigger" {
  count = var.enable_step_function ? 1 : 0
  name  = "${var.project_name}-${var.environment}-step-trigger-policy"
  role  = aws_iam_role.step_trigger[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "states:StartExecution"
        ]
        Resource = [
          aws_sfn_state_machine.datalake_orchestrator[0].arn
        ]
      }
    ]
  })
}

resource "aws_lambda_function" "step_trigger" {
  count         = var.enable_step_function ? 1 : 0
  function_name = "${var.project_name}-${var.environment}-step-trigger"
  role          = aws_iam_role.step_trigger[0].arn
  handler       = "trigger_step_function.lambda_handler"
  runtime       = "python3.11"
  filename      = data.archive_file.step_trigger[0].output_path
  source_code_hash = data.archive_file.step_trigger[0].output_base64sha256

  environment {
    variables = {
      STATE_MACHINE_ARN = aws_sfn_state_machine.datalake_orchestrator[0].arn
    }
  }
}

resource "aws_lambda_permission" "allow_s3_step_trigger" {
  count         = var.enable_step_function && var.enable_datalake_notifications ? 1 : 0
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.step_trigger[0].function_name
  principal     = "s3.amazonaws.com"
  source_arn    = "arn:aws:s3:::${var.datalake_source_bucket}"
}

resource "aws_s3_bucket_notification" "datalake_ingest" {
  count  = var.enable_step_function && var.enable_datalake_notifications ? 1 : 0
  bucket = var.datalake_source_bucket

  lambda_function {
    lambda_function_arn = aws_lambda_function.step_trigger[0].arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = var.datalake_source_prefix
  }

  depends_on = [aws_lambda_permission.allow_s3_step_trigger]
}

resource "aws_iam_role" "step_function" {
  count = var.enable_step_function ? 1 : 0
  name  = "${var.project_name}-${var.environment}-step-function-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "step_function" {
  count = var.enable_step_function ? 1 : 0
  name  = "${var.project_name}-${var.environment}-step-function-policy"
  role  = aws_iam_role.step_function[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "glue:StartJobRun",
          "glue:GetJobRun",
          "glue:GetJobRuns"
        ]
        Resource = [
          aws_glue_job.raw_ingest[0].arn,
          aws_glue_job.silver_customers[0].arn,
          aws_glue_job.silver_products[0].arn,
          aws_glue_job.silver_orders[0].arn,
          aws_glue_job.gold_customers[0].arn,
          aws_glue_job.gold_products[0].arn,
          aws_glue_job.gold_orders[0].arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "glue:StartCrawler"
        ]
        Resource = [
          aws_glue_crawler.raw[0].arn,
          aws_glue_crawler.bronze[0].arn,
          aws_glue_crawler.silver[0].arn,
          aws_glue_crawler.gold[0].arn
        ]
      }
    ]
  })
}

resource "aws_sfn_state_machine" "datalake_orchestrator" {
  count    = var.enable_step_function ? 1 : 0
  name     = var.step_function_name
  role_arn = aws_iam_role.step_function[0].arn

  definition = jsonencode({
    Comment = "Glue raw -> Crawler raw -> Silver -> Crawler silver -> Gold -> Crawler gold"
    StartAt = "RawIngest"
    States = {
      RawIngest = {
        Type = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync"
        Parameters = {
          JobName = aws_glue_job.raw_ingest[0].name
        }
        Next = "CrawlerRaw"
      }
      CrawlerRaw = {
        Type = "Task"
        Resource = "arn:aws:states:::aws-sdk:glue:startCrawler"
        Parameters = {
          Name = aws_glue_crawler.bronze[0].name
        }
        Next = "SilverParallel"
      }
      SilverParallel = {
        Type = "Parallel"
        Branches = [
          {
            StartAt = "SilverCustomers"
            States = {
              SilverCustomers = {
                Type = "Task"
                Resource = "arn:aws:states:::glue:startJobRun.sync"
                Parameters = {
                  JobName = aws_glue_job.silver_customers[0].name
                }
                End = true
              }
            }
          },
          {
            StartAt = "SilverProducts"
            States = {
              SilverProducts = {
                Type = "Task"
                Resource = "arn:aws:states:::glue:startJobRun.sync"
                Parameters = {
                  JobName = aws_glue_job.silver_products[0].name
                }
                End = true
              }
            }
          },
          {
            StartAt = "SilverOrders"
            States = {
              SilverOrders = {
                Type = "Task"
                Resource = "arn:aws:states:::glue:startJobRun.sync"
                Parameters = {
                  JobName = aws_glue_job.silver_orders[0].name
                }
                End = true
              }
            }
          }
        ]
        Next = "CrawlerSilver"
      }
      CrawlerSilver = {
        Type = "Task"
        Resource = "arn:aws:states:::aws-sdk:glue:startCrawler"
        Parameters = {
          Name = aws_glue_crawler.silver[0].name
        }
        Next = "GoldParallel"
      }
      GoldParallel = {
        Type = "Parallel"
        Branches = [
          {
            StartAt = "GoldCustomers"
            States = {
              GoldCustomers = {
                Type = "Task"
                Resource = "arn:aws:states:::glue:startJobRun.sync"
                Parameters = {
                  JobName = aws_glue_job.gold_customers[0].name
                }
                End = true
              }
            }
          },
          {
            StartAt = "GoldProducts"
            States = {
              GoldProducts = {
                Type = "Task"
                Resource = "arn:aws:states:::glue:startJobRun.sync"
                Parameters = {
                  JobName = aws_glue_job.gold_products[0].name
                }
                End = true
              }
            }
          },
          {
            StartAt = "GoldOrders"
            States = {
              GoldOrders = {
                Type = "Task"
                Resource = "arn:aws:states:::glue:startJobRun.sync"
                Parameters = {
                  JobName = aws_glue_job.gold_orders[0].name
                }
                End = true
              }
            }
          }
        ]
        Next = "CrawlerGold"
      }
      CrawlerGold = {
        Type = "Task"
        Resource = "arn:aws:states:::aws-sdk:glue:startCrawler"
        Parameters = {
          Name = aws_glue_crawler.gold[0].name
        }
        End = true
      }
    }
  })

  depends_on = [
    aws_glue_job.raw_ingest,
    aws_glue_job.silver_customers,
    aws_glue_job.silver_products,
    aws_glue_job.silver_orders,
    aws_glue_job.gold_customers,
    aws_glue_job.gold_products,
    aws_glue_job.gold_orders,
    aws_glue_crawler.raw,
    aws_glue_crawler.bronze,
    aws_glue_crawler.silver,
    aws_glue_crawler.gold
  ]
}
