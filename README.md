# SQL Server → AWS → Snowflake Migration

End-to-end migration lab: SQL Server on Docker → AWS DMS full-load → S3 → Snowpipe → Snowflake medallion (Raw → Bronze → Silver → Gold) with Airflow orchestration and dbt transformations.

## Repository Layout

```
sqlserver-to-snowflake-migration/
├── sqlserver/          # Local SQL Server setup (Docker + DDL + seed data)
│   ├── docker-compose.yml
│   ├── sql/            # 01_create_database → 22_lab_inventory DDL scripts
│   └── scripts/        # run_lab.sh, run_validation.sh, inspect_counts.sql
│
├── infra/
│   ├── aws-cdk/        # CDK stacks: DataLanding (S3+SNS), DmsCdc, TerraformState
│   └── terraform/
│       ├── snowflake/  # Warehouse, DB, schemas, stages, Snowpipes, DDL tables
│       └── aws/        # DMS replication instance, endpoint, task
│
├── dms/                # DMS task settings JSON + table mappings + helper scripts
├── glue/jobs/          # PySpark Glue jobs (raw ingest, silver/gold transform)
│
├── airflow/
│   ├── docker-compose.yml
│   └── dags/
│       └── mssql_migration_pipeline.py   # Main DAG: COPY INTO → BRONZE flatten
│
├── dbt/
│   ├── dbt_project.yml
│   ├── profiles.yml.example
│   ├── macros/
│   └── models/         # customers / orders / products  (stg → int → gold)
│
├── snowflake_ddl/
│   ├── bronze/         # Typed tables matching SQL Server schema (4 source DBs)
│   ├── silver/         # SCD Type-2 surrogate-key tables
│   └── gold/           # Facts + dimensions + MIGRATION_METADATA audit table
│
└── docs/
    └── sct_assessment.md   # Type-mapping decisions (SCT output)
```

## Quick Start — Local SQL Server

```bash
cd sqlserver
cp .env.example .env          # set SA_PASSWORD
docker compose up -d
cd scripts && ./run_lab.sh    # creates all 4 lab DBs + seeds data
./run_validation.sh           # confirms row counts
```

## Quick Start — Airflow

```bash
cd airflow
# copy .env.example from sqlserver/ and add Snowflake creds
docker compose up -d
# open http://localhost:8080  (admin / admin)
```

## Quick Start — dbt

```bash
cd dbt
cp profiles.yml.example ~/.dbt/profiles.yml   # fill in your Snowflake creds
dbt deps
dbt run --target dev
dbt test
```

## CI/CD

GitHub Actions workflow at `.github/workflows/migration-cicd.yml`:

| Trigger | Jobs |
|---------|------|
| Pull Request → main | `validate-pr`: CDK synth + terraform validate + dbt parse |
| Push to main | `deploy-main`: CDK deploy + terraform apply (Snowflake + AWS DMS) |

### Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `AWS_ROLE_ARN` | OIDC IAM role ARN (`arn:aws:iam::<account>:role/github-actions-mssql-migration`) |
| `AWS_REGION` | `us-east-1` |
| `MSSQL_PROJECT_NAME` | CDK project prefix (e.g. `patchit-mssql-migration`) |
| `TF_STATE_BUCKET` | S3 bucket for Terraform remote state |
| `SNOWFLAKE_ACCOUNT` | Snowflake account identifier |
| `SNOWFLAKE_USER` | Snowflake service user |
| `DMS_BUCKET_NAME` | DMS landing S3 bucket name (CDK output) |
| `GLUE_BUCKET_NAME` | Glue landing S3 bucket name (CDK output) |
| `SNOWFLAKE_S3_ROLE_ARN` | IAM role ARN for Snowflake storage integration |

## Architecture

```
SQL Server (Docker / RDS)
        │  full-load
        ▼
    AWS DMS ──── Parquet ───▶ S3 DMS bucket
                                    │ Snowpipe
                                    ▼
                           RAW_MSSQL.RAW_DMS_VARIANT (VARIANT)
                                    │ Airflow DAG
                                    ▼
                           BRONZE (typed, metadata cols)
                                    │ dbt
                                    ▼
                           SILVER (SCD Type-2)
                                    │ dbt
                                    ▼
                           GOLD (facts + dims + audit)
```
