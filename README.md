# SQL Server to Snowflake Migration Lab

A complete, runnable migration from SQL Server to Snowflake — covering four source databases (e-commerce, ERP, CRM, inventory), two ingestion paths (AWS DMS and Airbyte), a four-stage Snowflake medallion architecture, Airflow orchestration, dbt transformations, and a live migration dashboard.

This is a training lab, not a production template. The goal is to show you every layer of a real migration so you can understand the decisions, not just copy the configs.

---

## What you're building

```
SQL Server (Docker or RDS)
        │
        ├── via AWS DMS ────────► S3 (Parquet) ──► Snowpipe ──► RAW_MSSQL.RAW_DMS_VARIANT
        │                                                                │
        └── via Airbyte ─────────────────────────────────────► MSSQL_MIGRATION_LAB.AIRBYTE_RAW
                                                                         │
                                                          BRONZE (typed, MERGE dedup)
                                                                         │
                                                          SILVER (SCD Type-2 via dbt snapshot)
                                                                         │
                                                          GOLD (facts + dims via dbt run)
                                                                         │
                                                          dbt test (bronze + silver + gold)
```

DMS takes the AWS-native route: it writes Parquet files to S3, Snowpipe picks them up automatically, and Airflow runs a MERGE to promote typed rows into Bronze. Airbyte skips S3 entirely and writes directly to Snowflake using a connector — less infrastructure but no Parquet archive. You can run both side by side and compare counts.

---

## Repository layout

```
sqlserver-to-snowflake-migration/
├── sqlserver/              Local SQL Server (Docker + DDL + seed data)
│   ├── docker-compose.yml
│   ├── sql/                01_create_database → 22_lab_inventory (all 4 source DBs)
│   └── scripts/            run_lab.sh, run_validation.sh, inspect_counts.sql
│
├── infra/
│   ├── aws-cdk/            CDK stacks: DataLanding (S3+SNS), DmsCdc, TerraformState
│   └── terraform/
│       ├── snowflake/      Warehouse, DB, schemas, Snowpipes, DDL tables, SPs, UDFs, streams, tasks
│       └── aws/            DMS replication instance, endpoint, task
│
├── dms/                    DMS task settings JSON + table mappings
├── airbyte/                Airbyte OSS docker-compose + setup + comparison script
│
├── airflow/
│   ├── docker-compose.yml
│   └── dags/               4 DAGs (bronze → silver → gold → quality)
│
├── dbt/
│   ├── dbt_project.yml
│   ├── profiles.yml.example
│   └── models/             customers / orders / products  (stg → int → gold)
│
├── snowflake_ddl/
│   ├── bronze/             Typed tables for all 4 source DBs
│   ├── silver/             SCD Type-2 surrogate-key tables
│   ├── gold/               Facts + dims + MIGRATION_METADATA audit
│   ├── iceberg/            Iceberg external tables for long-term audit
│   ├── procedures/         Snowflake SPs replacing SQL Server stored procs
│   ├── streams_tasks/      Snowflake Streams + Tasks replacing DML triggers
│   └── udfs/               Scalar UDFs + Snowpark Python for XML/TVP
│
└── .env.example            All required credentials (copy → .env, never commit .env)
```

---

## Prerequisites

You need these accounts and tools before running anything:

- Docker Desktop (for local SQL Server and Airflow)
- AWS account with permissions to create S3, DMS, IAM, VPC resources
- Snowflake account (trial works — you'll create everything via Terraform)
- Python 3.10+ with pip
- AWS CDK v2: `npm install -g aws-cdk`
- Terraform 1.5+
- dbt Core 1.7+: `pip install dbt-snowflake`

Copy `.env.example` to `.env` at the repo root and fill in your values. Every script in this repo reads from that file. Nothing is hardcoded.

---

## Step 1 — Stand up SQL Server locally

The lab uses four SQL Server databases to simulate a realistic mixed-workload migration: a stress/e-commerce DB (orders, customers, products), an ERP DB (employees, payroll, departments), a CRM DB (accounts, contacts, opportunities), and an inventory DB (warehouses, SKUs, stock movements).

```bash
cd sqlserver
cp .env.example .env          # set SA_PASSWORD to something complex (SQL Server requires it)
docker compose up -d
```

Wait about 30 seconds for SQL Server to initialize, then seed all four databases:

```bash
cd scripts
./run_lab.sh
```

This runs all DDL scripts in order (`01_create_database.sql` through `22_lab_inventory.sql`), creates stored procedures, triggers, views, and inserts seed rows. After it finishes:

```bash
./run_validation.sh           # prints row counts per table
```

You should see roughly 100-500 rows per table depending on the seed script. If any count is 0, check `docker logs sqlserver_mssql_1` — the most common issue is the SA password not meeting SQL Server's complexity rules.

**CDC note**: Some scripts enable Change Data Capture on the stress DB. This requires SQL Server Agent to be running. The Docker image in this lab includes Agent. If you're using your own SQL Server image and Agent isn't running, CDC setup will fail silently — check with `SELECT * FROM sys.dm_cdc_log_scan_sessions`.

---

## Step 2 — Deploy AWS infrastructure

DMS needs to reach SQL Server. It cannot connect to `localhost` on your machine — it runs inside AWS VPC and needs a resolvable endpoint. You have two options:

**Option A (recommended for this lab)**: Use SQL Server on RDS. Deploy a small `db.t3.medium` RDS MSSQL instance, restore the seed data there, and point DMS at the RDS endpoint. RDS lives in the same VPC as your DMS replication instance so latency is low and you avoid VPN/firewall issues entirely.

**Option B**: Run SQL Server on an EC2 instance and expose it via private IP within the VPC. More complex, not covered here.

### Deploy with CDK

```bash
cd infra/aws-cdk
pip install -r requirements.txt
cp ../../.env .env

cdk bootstrap aws://<your-account-id>/<region>   # once per account/region
cdk deploy DataLandingStack     # creates S3 DMS bucket + SNS notification
cdk deploy TerraformStateStack  # creates S3 bucket for Terraform state
```

The `DataLandingStack` output includes the S3 bucket name. Add it to your `.env` as `DMS_BUCKET`.

### Deploy RDS SQL Server (if using Option A)

```bash
cd infra/terraform/aws
terraform init -backend-config="bucket=${TF_STATE_BUCKET}" \
               -backend-config="key=mssql-migration/aws/terraform.tfstate" \
               -backend-config="region=${AWS_REGION}"
terraform apply
```

This creates a DMS replication instance, source endpoint (pointing at RDS), target endpoint (S3), and a full-load task for all 15 tables across the four databases. After `apply`:

```bash
terraform output dms_task_arn   # save this, you'll start the task next
```

After RDS is up, load the same seed data you ran locally. The simplest way is to run `run_lab.sh` against the RDS endpoint:

```bash
# install sqlcmd or use the MSSQL Docker container as a client
MSSQL_HOST=<rds-endpoint> MSSQL_USER=admin MSSQL_PASSWORD=<your-rds-pass> ./run_lab.sh
```

---

### Already have an RDS SQL Server? Just deploy DMS

If you created an RDS SQL Server instance yourself — through the console, CLI, or your own Terraform — you don't need this repo to provision RDS again. You can skip the RDS creation and use Terraform only to set up the DMS replication instance, endpoints, and task.

Here's how to do it.

**1. Tell Terraform not to create a new RDS instance**

Open (or create) `infra/terraform/aws/terraform.tfvars` and set `use_rds = false`. Then provide the connection details for your existing instance:

```hcl
use_rds        = false
mssql_host     = "your-existing-instance.xxxxxx.us-east-1.rds.amazonaws.com"
mssql_port     = 1433
mssql_db       = "SnowConvertStressDB"   # or whatever your source DB is named
mssql_user     = "sa"
mssql_password = "your-password"
```

When `use_rds = false`, Terraform skips creating the RDS subnet group, parameter group, security group, and DB instance entirely. It only creates the DMS replication instance, the source endpoint pointing at your host, the S3 target endpoint, and the replication task.

**2. Make sure DMS can actually reach your RDS instance**

This is the step people most often forget. DMS runs inside your VPC, so your existing RDS security group needs to allow inbound TCP on port 1433 from the DMS replication instance's security group. The easiest way to do this is to add an inbound rule on your RDS security group that allows traffic from the DMS security group. Terraform outputs the DMS security group ID after apply — you can add the rule manually in the console or reference it in your own Terraform config.

If your RDS instance is in a different VPC than where DMS will run, you'll need VPC peering or a Transit Gateway — that's beyond the scope of this lab. The simplest setup is to let Terraform use your default VPC (leave `dms_vpc_id = null` and `dms_subnet_ids = []`) and make sure your RDS instance is also in that default VPC.

**3. Run Terraform**

```bash
cd infra/terraform/aws
terraform init -backend-config="bucket=${TF_STATE_BUCKET}" \
               -backend-config="key=mssql-migration/aws/terraform.tfstate" \
               -backend-config="region=${AWS_REGION}"
terraform plan   # review — you should see DMS resources only, no aws_db_instance
terraform apply
```

After apply you'll get outputs like `dms_replication_instance_arn` and `dms_replication_task_arn`. Save the task ARN — you'll use it to start the migration.

**4. Enable CDC on your existing RDS SQL Server**

Before starting DMS in CDC mode, CDC needs to be turned on at the database and table level. On RDS SQL Server, you do this through stored procedures rather than directly — Microsoft SQL Server on RDS uses a wrapper SP instead of the native `sys.sp_cdc_enable_db`:

```sql
-- Connect to your RDS instance as the master user
USE SnowConvertStressDB
GO

-- Enable CDC on the database (RDS-specific wrapper)
EXEC msdb.dbo.rds_cdc_enable_db 'SnowConvertStressDB'
GO

-- Enable CDC on each table you want to replicate
EXEC sys.sp_cdc_enable_table
    @source_schema = 'dbo',
    @source_name   = 'Orders',
    @role_name     = NULL
GO
-- Repeat for each table (Customers, Products, OrderItems, etc.)
```

If you're only doing a one-time full load (no ongoing CDC), you can skip this step — DMS full-load mode doesn't require CDC to be enabled.

**5. Start the DMS task**

```bash
aws dms start-replication-task \
    --replication-task-arn $(terraform output -raw dms_replication_task_arn) \
    --start-replication-task-type start-replication
```

Watch progress in the AWS console under Database Migration Service → Replication tasks, or poll via CLI:

```bash
aws dms describe-replication-tasks \
    --filters Name=replication-task-arn,Values=$(terraform output -raw dms_replication_task_arn) \
    --query 'ReplicationTasks[0].{Status:Status,Progress:ReplicationTaskStats.FullLoadProgressPercent}'
```

Once the task shows `Load complete`, your Parquet files are in S3 and Snowpipe will pick them up automatically. Continue from Step 3 (Snowflake setup) from here.

---

## Step 3 — Set up Snowflake

```bash
cd infra/terraform/snowflake
terraform init -backend-config="bucket=${TF_STATE_BUCKET}" \
               -backend-config="key=mssql-migration/snowflake/terraform.tfstate" \
               -backend-config="region=${AWS_REGION}"
terraform apply
```

Set these environment variables before running (Terraform picks them up automatically):

```bash
export SNOWFLAKE_ORGANIZATION_NAME=<your-org>
export SNOWFLAKE_ACCOUNT_NAME=<your-account>
export SNOWFLAKE_USER=<your-user>
export SNOWFLAKE_PASSWORD=<your-password>
```

Terraform creates:

- Database `MSSQL_MIGRATION_LAB` with schemas `RAW_MSSQL`, `BRONZE`, `SILVER`, `GOLD`, `AIRBYTE_RAW`
- Warehouse `WH_MSSQL_MIGRATION` (X-SMALL, auto-suspend 60s)
- External stage pointing at your S3 DMS bucket with a storage integration
- Snowpipe `PIPE_RAW_DMS_VARIANT` — auto-ingests Parquet files from S3 into `RAW_MSSQL.RAW_DMS_VARIANT`
- All Bronze, Silver, and Gold DDL tables
- All stored procedures, UDFs, streams, and tasks from `snowflake_ddl/`

After apply, the Snowpipe is live. When DMS writes a Parquet file to S3, the SNS notification triggers Snowpipe and the row lands in `RAW_DMS_VARIANT` within seconds.

---

## Step 4 — Run DMS full-load

Start the DMS task from the console or CLI:

```bash
aws dms start-replication-task \
    --replication-task-arn $(terraform -chdir=infra/terraform/aws output -raw dms_task_arn) \
    --start-replication-task-type start-replication
```

Monitor progress in the AWS console under Database Migration Service → Replication tasks. A full load of ~5,000 seed rows typically completes in under 5 minutes.

When it finishes, check Snowflake:

```sql
SELECT COUNT(*) FROM MSSQL_MIGRATION_LAB.RAW_MSSQL.RAW_DMS_VARIANT;
```

You should see rows. If the count is 0, check:
1. S3 bucket — do Parquet files exist under the DMS prefix?
2. Snowpipe history: `SELECT * FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(TABLE_NAME=>'RAW_DMS_VARIANT', START_TIME=>DATEADD('hour',-1,CURRENT_TIMESTAMP())))`
3. Storage integration IAM trust policy — the most common setup mistake is the Snowflake AWS account not having permission to read your S3 bucket

---

## Step 5 — Airbyte alternative (optional)

Airbyte is a good comparison to DMS. It connects directly from Docker to SQL Server, runs discovery, and writes to `MSSQL_MIGRATION_LAB.AIRBYTE_RAW` without any S3 involvement. The tradeoff: you lose the Parquet archive on S3, but you gain a much simpler setup and no AWS cost.

```bash
cd airbyte
docker compose up -d
```

Wait for Airbyte to initialize (about 2 minutes). Then run the setup script:

```bash
pip install requests python-dotenv
python setup_connections.py
```

This creates a SQL Server source connector, a Snowflake destination connector, creates a connection between them, and triggers the first full sync. The script polls until the sync completes and prints a summary.

**Important**: The Airbyte Docker containers reach SQL Server at `host.docker.internal`, not `localhost`. This is already set in the config. If you're on Linux, `host.docker.internal` requires `--add-host=host.docker.internal:host-gateway` in your Docker run command — the `docker-compose.yml` handles this automatically.

After the sync, compare row counts between DMS Bronze and Airbyte RAW:

```bash
python compare_dms_vs_airbyte.py
```

Airbyte row counts should be greater than or equal to Bronze counts. Bronze uses MERGE (dedup by primary key, latest wins). Airbyte in append-dedup mode keeps one row per PK per sync cycle, so it can accumulate more rows if you ran multiple syncs.

Airbyte UI: http://localhost:8000 (user: `airbyte`, password: `password`)

---

## Step 6 — Run the Airflow pipeline

Airflow orchestrates four DAGs that move data from RAW through Bronze, Silver, and Gold, then run quality checks.

```bash
cd airflow
docker compose up -d
```

Open http://localhost:8080. Log in with `admin` / `admin`. You'll see four DAGs:

### DAG 1: mssql_01_ingest_bronze

Reads from `RAW_DMS_VARIANT` and runs a MERGE into each of the 15 Bronze tables. The MERGE deduplicates by primary key using `QUALIFY ROW_NUMBER() OVER (PARTITION BY <pk>) = 1` — this is necessary because `SELECT DISTINCT` doesn't deduplicate when computed columns like `CURRENT_TIMESTAMP()` produce different values for identical rows.

Before MERGE, this DAG also resumes the Snowflake Streams + Tasks (CDC equivalents for triggers). After MERGE, it suspends them. This prevents tasks from running on partial data.

Tasks: `check_raw_counts` → `resume_sf_tasks` → `merge_bronze_stress` + `merge_bronze_erp` + `merge_bronze_crm` + `merge_bronze_inv` (parallel) → `suspend_sf_tasks` → `report_bronze_counts`

### DAG 2: mssql_02_silver_snapshots

Waits for DAG 1 to complete, then runs `dbt snapshot` for all 15 tables. Each snapshot builds an SCD Type-2 history in Silver — adding `dbt_scd_id`, `dbt_valid_from`, `dbt_valid_to`, and `dbt_updated_at` columns. The current record for any row is where `dbt_valid_to IS NULL`.

### DAG 3: mssql_03_gold_transforms

Waits for DAG 2, then runs `dbt run` for the staging, intermediate, and gold models. Gold produces three fact/dimension tables: `CUSTOMERS_DIM`, `ORDERS_FACT`, `PRODUCTS_DIM`. These are what you'd expose to BI tools.

### DAG 4: mssql_04_data_quality

Waits for DAG 3, then runs `dbt test` across all three layers. Expected result: 27 PASS, 3 WARN. The warnings are for nullable columns where data quality is expected to improve once CDC is fully running.

### Running the pipeline

Trigger DAG 1 first. After it completes successfully, trigger DAGs 2, 3, and 4 — they will wait on the sensor and then proceed automatically. If you're running them manually, trigger each one with the same `--exec-date` as DAG 1:

```bash
# get DAG 1's execution date from the Airflow UI, then:
airflow dags trigger mssql_02_silver_snapshots --exec-date "2026-04-19T15:27:15+00:00"
airflow dags trigger mssql_03_gold_transforms  --exec-date "2026-04-19T15:27:15+00:00"
airflow dags trigger mssql_04_data_quality     --exec-date "2026-04-19T15:27:15+00:00"
```

The ExternalTaskSensor matches by exact `execution_date`, not by "most recent successful run." If the downstream DAGs are triggered at a different time, the sensor will poll forever. The `--exec-date` flag is how you tell Airflow these runs belong to the same logical batch.

---

## Step 7 — Live migration dashboard

```bash
cd airflow/dashboard
docker compose up -d
```

Open http://localhost:8050. The dashboard shows:

- DAG status cards (running / success / failed) polled from the Airflow REST API
- Row counts per table across RAW, Bronze, Silver, and Gold
- Coverage percentages (how many of the 15 tables have at least 1 row in each layer)
- A CDC events table showing the last 50 rows landed in RAW (useful for watching live DMS streaming)

The dashboard refreshes every 30 seconds in a background thread. You can force a refresh by clicking the "Refresh Now" button or POSTing to `http://localhost:8050/api/refresh`.

---

## SQL Server object migration map

SQL Server has objects that don't exist in Snowflake. Here's what each became.

### Stored procedures

| SQL Server | Snowflake | Notes |
|---|---|---|
| `usp_RefreshOrderTotals(@OrderId)` | `SP_REFRESH_ORDER_TOTALS(order_id)` | Direct port |
| `usp_ListOpenOrders` | `SP_LIST_OPEN_ORDERS()` | Returns RESULTSET |
| `usp_Stress_DynamicSearchOrders` | `SP_DYNAMIC_SEARCH_ORDERS(...)` | `sp_executesql` → `EXECUTE IMMEDIATE` |
| `usp_Stress_CursorRepriceProductsByCategory` | `SP_REPRICE_PRODUCTS_BY_CATEGORY(...)` | Cursor removed; set-based UPDATE |
| `usp_Stress_MergeUpsertCustomers(@json)` | `SP_MERGE_UPSERT_CUSTOMERS(variant)` | `OPENJSON` → `FLATTEN` |
| `usp_Stress_XmlOrderDocument(@OrderId)` | `SP_XML_ORDER_DOCUMENT(order_id)` | Snowpark Python — no native XML type in Snowflake |
| `usp_Stress_JsonOrderLines(@OrderId)` | `SP_JSON_ORDER_LINES(order_id)` | `FOR JSON PATH` → `ARRAY_AGG + OBJECT_CONSTRUCT` |
| `usp_Stress_ChainedA/B/C` | `SP_CHAINED_A/B/C` | Nested `CALL` statements |
| `usp_Stress_RecursiveCategoryClosure` | `SP_BUILD_CATEGORY_CLOSURE()` | `WITH RECURSIVE` CTE — Snowflake supports this natively |
| `usp_Stress_SavePointPartialRollback` | Not ported | Snowflake has no `SAVE TRANSACTION` |
| `usp_Stress_ThrowCatchAndRethrow` | `SP_THROW_CATCH_RETHROW()` | `BEGIN TRY/CATCH` → `EXCEPTION WHEN OTHER THEN` |
| `usp_Stress_OutputMergePriceHistory` | `SP_UPDATE_PRICE_WITH_HISTORY(...)` | `OUTPUT` clause → read old value before update |
| `usp_Stress_WhileBatchNumbers(@n)` | `SP_WHILE_BATCH_NUMBERS(n)` | Temp table → variables; returns OBJECT |
| `usp_Stress_MultiResultSets` | `SP_MULTI_RESULT_DEMO(customer_id)` | Multiple result sets → single VARIANT |
| `usp_Stress_WaitForShort` | `SP_WAITFOR_SHORT()` | `WAITFOR DELAY` → `SYSTEM$WAIT` |
| `usp_Stress_TempTableDynamicPivot` | `SP_DYNAMIC_PIVOT()` | `PIVOT` + `EXECUTE IMMEDIATE` |
| `usp_Stress_ScopedTempTableCaller/Callee` | Not ported | Snowflake temp tables don't cross SP call boundaries |
| `usp_Stress_TvpAppendOrderLines(@tvp)` | `SP_TVP_APPEND_ORDER_LINES(order_id, lines VARIANT)` | TVP → VARIANT array + FLATTEN |
| `usp_Stress_OpenJsonApplyPatch` | `SP_PATCH_PRODUCTS_FROM_JSON(variant)` | `OPENJSON` → `FLATTEN` |
| `usp_Erp_DynamicDeptReport` | `SP_ERP_DYNAMIC_DEPT_REPORT(...)` | Dynamic ORDER BY with whitelist |
| `usp_Erp_ClosePayrollRun(@RunId)` | `SP_ERP_CLOSE_PAYROLL_RUN(run_id)` | Direct port |
| `usp_Crm_MergeAccountsFromJson` | `SP_CRM_MERGE_ACCOUNTS_FROM_JSON(variant)` | `OPENJSON` → `FLATTEN` |
| `usp_Crm_ListPipeline(@Region)` | `SP_CRM_LIST_PIPELINE(region)` | Direct port |
| `usp_Inv_StockXml(@WhId)` | `SP_INV_STOCK_XML(wh_id)` | Snowpark Python |
| `usp_Inv_DynamicWhFilter` | `SP_INV_DYNAMIC_WH_FILTER(wh_code)` | `EXECUTE IMMEDIATE` with quote-escaped param |

### Triggers

Snowflake has no triggers. The lab handles this two ways depending on what the trigger was doing.

**Audit and side-effect triggers become Streams + Tasks** (async, fire within about 1 minute):

| SQL Server | Snowflake stream | Snowflake task | File |
|---|---|---|---|
| `tr_Orders_Audit_IU` | `STREAM_ORDERS_CHANGES` | `TASK_ORDERS_AUDIT` | `01_stressdb_streams.sql` |
| `tr_OrderItems_RecalcAndQueue` | `STREAM_ORDER_ITEMS_CHANGES` | `TASK_ORDER_ITEMS_RECALC` | `01_stressdb_streams.sql` |
| `tr_Products_ListPriceAudit` | `STREAM_PRODUCTS_CHANGES` | `TASK_PRODUCTS_PRICE_AUDIT` | `01_stressdb_streams.sql` |
| `tr_Employees_Audit` | `STREAM_ERP_EMPLOYEES_CHANGES` | `TASK_ERP_EMPLOYEES_AUDIT` | `02_erp_streams.sql` |
| `tr_PayrollLines_Recalc` | `STREAM_ERP_PAYROLL_LINES_CHANGES` | `TASK_ERP_PAYROLL_RECALC` | `02_erp_streams.sql` |
| `tr_Accounts_Activity` | `STREAM_CRM_ACCOUNTS_CHANGES` | `TASK_CRM_ACCOUNTS_ACTIVITY` | `03_crm_streams.sql` |
| `tr_Sku_NoNegativeCost` | `STREAM_INV_SKU_CHANGES` | `TASK_INV_SKU_COST_GUARD` | `04_inventory_streams.sql` |

One thing to know: Snowflake Tasks are suspended by default. Airflow DAG 1 resumes them before the Bronze MERGE and suspends them after. This is intentional — you don't want tasks firing while a MERGE is in progress.

**INSTEAD OF triggers become stored procedures** (callers must use the SP, not write directly to the table):

| SQL Server trigger | Snowflake SP | File |
|---|---|---|
| `tr_vw_Orders_Dml_IOD` (INSTEAD OF DELETE) | `SP_SOFT_DELETE_ORDER(order_id)` | `06_dml_guard_procs.sql` |
| `tr_vw_Orders_Dml_IOU` (INSTEAD OF UPDATE) | `SP_UPDATE_ORDER(order_id, ...)` | `06_dml_guard_procs.sql` |
| `tr_vw_StockOrders_IOI` (INSTEAD OF INSERT) | `SP_INV_SOFT_INSERT_STOCK_ORDER(...)` | `05_inventory_procs.sql` |
| `tr_Opportunities_StageGuard` (AFTER UPDATE) | `SP_CRM_UPDATE_OPPORTUNITY_STAGE(opp_id, stage)` | `04_crm_procs.sql` |

### Constraints

| SQL Server | Snowflake | Notes |
|---|---|---|
| `OrderItems.Quantity CHECK (Quantity > 0)` | `NOT ENFORCED` constraint | Enforced inside `SP_TVP_APPEND_ORDER_LINES` |
| `Orders.Status DEFAULT 'Open'` | Column `DEFAULT 'Open'` | Supported natively |
| `Customers.Country DEFAULT 'US'` | Column `DEFAULT 'US'` | Supported natively |
| `OrderItems.LineTotal PERSISTED computed` | Stored as `LINE_TOTAL NUMBER(18,4)` | Computed during MERGE, no computed columns in Snowflake |
| `Products.SKU UNIQUE` | `UNIQUE NOT ENFORCED` | Enforced by MERGE dedup logic |
| `Orders → Customers FK` | `FOREIGN KEY NOT ENFORCED` | Declared but not enforced at write time |

### Functions

| SQL Server | Snowflake | Location |
|---|---|---|
| `fn_FormatMoney(@amount)` scalar UDF | `FN_FORMAT_MONEY(amount)` SQL UDF | `udfs/01_scalar_udfs.sql` |
| `fn_OrderLineCount(@orderId)` inline TVF | `FN_ORDER_LINE_COUNT(order_id)` scalar UDF | `udfs/01_scalar_udfs.sql` |

---

## DMS vs Airbyte — which to use

This lab supports both. Here's an honest comparison:

| | AWS DMS | Airbyte |
|---|---|---|
| Setup complexity | High — IAM, VPC, DMS instance, replication task, Snowpipe, S3 | Low — one `docker compose up` |
| Data durability | Parquet files in S3 (retain forever) | No intermediate storage |
| Source support | SQL Server, Oracle, MySQL, PostgreSQL, MongoDB, and more | 300+ connectors including SaaS APIs |
| CDC support | Yes, via native CDC | Yes, via CDC or STANDARD mode |
| Cost | DMS replication instance runs 24/7 even when idle | Free OSS; Airbyte Cloud has usage pricing |
| Best for | AWS-native shops, regulated environments needing audit trail | Faster setup, many heterogeneous sources |

If your company is already on AWS and you need an audit trail of raw source data, DMS is the better choice. If you need to pull from Salesforce, Hubspot, and SQL Server into the same warehouse, Airbyte covers all of them without extra plumbing.

---

## Credential security

Your `.env` file contains real credentials and must never be committed to git. It is in `.gitignore` — verify with:

```bash
git check-ignore -v .env
```

If it's not listed, add `.env` to `.gitignore` immediately and rotate any credentials that were already committed.

The `.env.example` file shows every variable this lab needs. Copy it to `.env` and fill in your values:

```bash
cp .env.example .env
```

For production, use a secret manager (AWS Secrets Manager, HashiCorp Vault) instead of `.env` files. Terraform supports Vault and SSM Parameter Store natively.

---

## Smoke tests after setup

After Terraform apply and a successful DMS load, run these in Snowflake to verify the migration:

```sql
-- Basic counts
SELECT COUNT(*) FROM BRONZE.CUSTOMERS;
SELECT COUNT(*) FROM BRONZE.ORDERS;

-- Procedure smoke test
CALL BRONZE.SP_LIST_OPEN_ORDERS();
CALL BRONZE.SP_DYNAMIC_SEARCH_ORDERS('Open', NULL, NULL, 'ORDER_DATE', 'DESC');

-- UDF
SELECT BRONZE.FN_FORMAT_MONEY(12345.678);

-- Chained proc (appends [C][B][A] to notes)
CALL BRONZE.SP_CHAINED_A_OUTER(1);
SELECT NOTES FROM BRONZE.ORDERS WHERE ORDER_ID = 1;

-- Stream check (needs a row in BRONZE.ORDERS first)
SELECT SYSTEM$STREAM_HAS_DATA('BRONZE.STREAM_ORDERS_CHANGES');

-- Task history
SELECT NAME, STATE, COMPLETED_TIME, ERROR_MESSAGE
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
    SCHEDULED_TIME_RANGE_START => DATEADD('hour', -1, CURRENT_TIMESTAMP()),
    TASK_NAME => 'TASK_ORDERS_AUDIT'
));

-- dbt test results (run via Airflow DAG 4 or directly)
-- Should show 27 PASS, 3 WARN
```

---

## Cost estimate

Running this lab for one day on AWS:

| Component | Approximate cost |
|---|---|
| DMS replication instance (dms.t3.medium) | $0.12/hr ≈ $3/day |
| RDS SQL Server SE (db.t3.medium) | $0.10/hr ≈ $2.40/day |
| S3 storage for Parquet files | < $0.01 |
| Snowflake X-SMALL warehouse (auto-suspend 60s) | ~$1-2/day depending on query volume |

Tear down when done:

```bash
terraform destroy -chdir=infra/terraform/aws
terraform destroy -chdir=infra/terraform/snowflake
docker compose down -v   # in sqlserver/, airflow/, airbyte/
```

---

## Troubleshooting

**DMS task shows "Load complete" but RAW_DMS_VARIANT is empty**
Check Snowpipe: `SELECT * FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(...))`. If errors show, it's usually the storage integration — the IAM trust relationship between Snowflake and your S3 bucket needs the Snowflake AWS account ID and external ID that Terraform output after `apply`.

**Airflow Bronze MERGE fails with `Duplicate row detected during DML action`**
This happens when the source subquery returns two rows with the same primary key. The root cause is usually `SELECT DISTINCT` not deduplicating rows with different computed column values (`CURRENT_TIMESTAMP()` differs per row). The fix is `QUALIFY ROW_NUMBER() OVER (PARTITION BY <pk>) = 1` in the MERGE source query.

**ExternalTaskSensor polls forever and never succeeds**
The sensor matches by exact `execution_date`. Trigger downstream DAGs with `--exec-date` equal to the upstream DAG's execution_date. You can find it in the Airflow UI under the upstream DAG run's details.

**dbt fails with `--profiles-dir is not a valid option`**
This is a dbt 1.x breaking change. The flag `--profiles-dir` is not valid as a global pre-command flag. Set `ENV DBT_PROFILES_DIR=/opt/dbt` in the Dockerfile and use `ENTRYPOINT ["dbt"]` without arguments.

**Airbyte sync fails with `Cannot connect to host.docker.internal`**
On Linux, `host.docker.internal` isn't automatically available. Add `--add-host=host.docker.internal:host-gateway` to your Docker run, or add it under `extra_hosts` in the docker-compose service definition.

---

## CI/CD

GitHub Actions at `.github/workflows/migration-cicd.yml`:

| Trigger | Jobs |
|---|---|
| PR to main | CDK synth + terraform validate + dbt parse |
| Push to main | CDK deploy + terraform apply (Snowflake + AWS DMS) |

Required GitHub Secrets:

| Secret | Description |
|---|---|
| `AWS_ROLE_ARN` | OIDC IAM role ARN |
| `AWS_REGION` | e.g. `us-east-1` |
| `TF_STATE_BUCKET` | S3 bucket for Terraform state |
| `SNOWFLAKE_ACCOUNT` | Snowflake account identifier |
| `SNOWFLAKE_USER` | Snowflake service user |
| `DMS_BUCKET_NAME` | DMS landing S3 bucket |
| `SNOWFLAKE_S3_ROLE_ARN` | IAM role ARN for Snowflake storage integration |
