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
│       ├── snowflake/  # Warehouse, DB, schemas, stages, Snowpipes, DDL tables,
│       │               # procedures, UDFs, streams, tasks
│       └── aws/        # DMS replication instance, endpoint, task
│
├── dms/                # DMS task settings JSON + table mappings + helper scripts
├── glue/jobs/          # PySpark Glue jobs (raw ingest, silver/gold transform)
│
├── airflow/
│   ├── docker-compose.yml
│   └── dags/           # 4 focused DAGs (bronze → silver → gold → quality)
│
├── dbt/
│   ├── dbt_project.yml
│   ├── profiles.yml.example
│   ├── macros/
│   └── models/         # customers / orders / products  (stg → int → gold)
│
├── snowflake_ddl/
│   ├── bronze/         # Typed tables matching SQL Server schema (4 source DBs)
│   │                   # + 05_stress_supporting.sql (audit/queue/archive tables)
│   ├── silver/         # SCD Type-2 surrogate-key tables
│   ├── gold/           # Facts + dimensions + MIGRATION_METADATA audit table
│   ├── iceberg/        # Iceberg external tables for long-term audit retention
│   ├── procedures/     # Snowflake Scripting SPs replacing SQL Server procs
│   │   ├── 01_basic_procs.sql        # usp_RefreshOrderTotals, usp_ListOpenOrders
│   │   ├── 02_stress_procs.sql       # All usp_Stress_* (16 procs)
│   │   ├── 03_erp_procs.sql          # ERP dynamic report + payroll close
│   │   ├── 04_crm_procs.sql          # CRM merge + pipeline list + stage guard
│   │   ├── 05_inventory_procs.sql    # Inventory dynamic filter + stock insert + SKU cost
│   │   └── 06_dml_guard_procs.sql    # INSTEAD OF trigger replacements
│   ├── streams_tasks/  # Snowflake Streams + Tasks replacing DML triggers
│   │   ├── 01_stressdb_streams.sql   # Orders audit, OrderItems recalc, Products price audit
│   │   ├── 02_erp_streams.sql        # Employees audit, Payroll recalc
│   │   ├── 03_crm_streams.sql        # Accounts activity, Opportunities audit
│   │   └── 04_inventory_streams.sql  # SKU cost guard, Stock movements audit
│   └── udfs/
│       ├── 01_scalar_udfs.sql        # FN_FORMAT_MONEY, FN_ORDER_LINE_COUNT
│       └── 02_xml_snowpark.py        # SP_XML_ORDER_DOCUMENT, SP_INV_STOCK_XML (Snowpark)
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
                                    │ Airflow DAG 1 (mssql_01_ingest_bronze)
                                    ▼
                           BRONZE (typed, metadata cols)
                                    │ Airflow DAG 2 (mssql_02_silver_snapshots)
                                    ▼
                           SILVER (SCD Type-2 via dbt snapshot)
                                    │ Airflow DAG 3 (mssql_03_gold_transforms)
                                    ▼
                           GOLD (facts + dims + reports via dbt run)
                                    │ Airflow DAG 4 (mssql_04_data_quality)
                                    ▼
                           dbt test (bronze + silver + gold)
```

## SQL Server Object Migration Map

SQL Server has triggers, procedures, and constraints that have no direct equivalent
in Snowflake. The table below shows what each object became and where the code lives.

### Constraints

| SQL Server | Snowflake | Notes |
|---|---|---|
| `OrderItems.Quantity CHECK (Quantity > 0)` | `NOT ENFORCED` constraint on `BRONZE.ORDER_ITEMS` | Enforced by `SP_TVP_APPEND_ORDER_LINES` validation |
| `Orders.Status DEFAULT 'Open'` | Column `DEFAULT 'Open'` | Supported natively |
| `Customers.Country DEFAULT 'US'` | Column `DEFAULT 'US'` | Supported natively |
| `OrderItems.LineTotal AS (Qty * UnitPrice) PERSISTED` | Computed at ingest time, stored as `LINE_TOTAL NUMBER(18,4)` | No computed columns in Snowflake; value set during MERGE |
| `Products.SKU UNIQUE` | `UNIQUE NOT ENFORCED` | Enforced by ingest MERGE logic |
| `Orders → Customers FK` | `FOREIGN KEY NOT ENFORCED` | Declared in DDL, not enforced at write time |
| `OrderItems → Orders FK` | `FOREIGN KEY NOT ENFORCED` | Same pattern |

### Stored Procedures

| SQL Server | Snowflake SP | Location | Notes |
|---|---|---|---|
| `usp_RefreshOrderTotals(@OrderId)` | `SP_REFRESH_ORDER_TOTALS(order_id)` | `01_basic_procs.sql` | Direct port |
| `usp_ListOpenOrders` | `SP_LIST_OPEN_ORDERS()` | `01_basic_procs.sql` | Returns RESULTSET |
| `usp_Stress_DynamicSearchOrders` | `SP_DYNAMIC_SEARCH_ORDERS(...)` | `02_stress_procs.sql` | `sp_executesql` → `EXECUTE IMMEDIATE` |
| `usp_Stress_CursorRepriceProductsByCategory` | `SP_REPRICE_PRODUCTS_BY_CATEGORY(...)` | `02_stress_procs.sql` | Cursor removed; set-based UPDATE |
| `usp_Stress_MergeUpsertCustomers(@json)` | `SP_MERGE_UPSERT_CUSTOMERS(variant)` | `02_stress_procs.sql` | `OPENJSON` → `FLATTEN` |
| `usp_Stress_XmlOrderDocument(@OrderId)` | `SP_XML_ORDER_DOCUMENT(order_id)` | `udfs/02_xml_snowpark.py` | Snowpark Python; no native XML type |
| `usp_Stress_JsonOrderLines(@OrderId)` | `SP_JSON_ORDER_LINES(order_id)` | `02_stress_procs.sql` | `FOR JSON PATH` → `ARRAY_AGG + OBJECT_CONSTRUCT` |
| `usp_Stress_ChainedA/B/C` | `SP_CHAINED_A/B/C` | `02_stress_procs.sql` | Nested `CALL` statements |
| `usp_Stress_RecursiveCategoryClosure` | `SP_BUILD_CATEGORY_CLOSURE()` | `02_stress_procs.sql` | `WITH RECURSIVE` CTE supported in Snowflake |
| `usp_Stress_SavePointPartialRollback` | No equivalent | N/A | Snowflake has no `SAVE TRANSACTION`; not ported |
| `usp_Stress_ThrowCatchAndRethrow` | `SP_THROW_CATCH_RETHROW()` | `02_stress_procs.sql` | `BEGIN TRY/CATCH` → `EXCEPTION WHEN OTHER THEN` |
| `usp_Stress_OutputMergePriceHistory` | `SP_UPDATE_PRICE_WITH_HISTORY(...)` | `02_stress_procs.sql` | `OUTPUT` clause → read old value before update |
| `usp_Stress_WhileBatchNumbers(@n)` | `SP_WHILE_BATCH_NUMBERS(n)` | `02_stress_procs.sql` | Temp table → variables; returns OBJECT |
| `usp_Stress_MultiResultSets` | `SP_MULTI_RESULT_DEMO(customer_id)` | `02_stress_procs.sql` | Multiple result sets → single VARIANT |
| `usp_Stress_WaitForShort` | `SP_WAITFOR_SHORT()` | `02_stress_procs.sql` | `WAITFOR DELAY` → `SYSTEM$WAIT` |
| `usp_Stress_TempTableDynamicPivot` | `SP_DYNAMIC_PIVOT()` | `02_stress_procs.sql` | `PIVOT` + `EXECUTE IMMEDIATE` |
| `usp_Stress_ScopedTempTableCaller/Callee` | Not ported | N/A | Snowflake temp tables don't cross SP call boundaries |
| `usp_Stress_TvpAppendOrderLines(@tvp)` | `SP_TVP_APPEND_ORDER_LINES(order_id, lines VARIANT)` | `02_stress_procs.sql` | TVP → VARIANT array + FLATTEN |
| `usp_Stress_OpenJsonApplyPatch` | `SP_PATCH_PRODUCTS_FROM_JSON(variant)` | `02_stress_procs.sql` | `OPENJSON` → `FLATTEN` |
| `usp_Erp_DynamicDeptReport` | `SP_ERP_DYNAMIC_DEPT_REPORT(...)` | `03_erp_procs.sql` | Dynamic ORDER BY with whitelist |
| `usp_Erp_ClosePayrollRun(@RunId)` | `SP_ERP_CLOSE_PAYROLL_RUN(run_id)` | `03_erp_procs.sql` | Direct port |
| `usp_Crm_MergeAccountsFromJson` | `SP_CRM_MERGE_ACCOUNTS_FROM_JSON(variant)` | `04_crm_procs.sql` | `OPENJSON` → `FLATTEN` |
| `usp_Crm_ListPipeline(@Region)` | `SP_CRM_LIST_PIPELINE(region)` | `04_crm_procs.sql` | Direct port |
| `usp_Inv_StockXml(@WhId)` | `SP_INV_STOCK_XML(wh_id)` | `udfs/02_xml_snowpark.py` | Snowpark Python |
| `usp_Inv_DynamicWhFilter` | `SP_INV_DYNAMIC_WH_FILTER(wh_code)` | `05_inventory_procs.sql` | `EXECUTE IMMEDIATE` with quote-escaped param |

### Triggers

Snowflake has no triggers. DML triggers split into two categories:

**Audit / side-effect triggers → Streams + Tasks** (async, fire within ~1 minute):

| SQL Server trigger | Snowflake stream | Snowflake task | File |
|---|---|---|---|
| `tr_Orders_Audit_IU` | `STREAM_ORDERS_CHANGES` | `TASK_ORDERS_AUDIT` | `01_stressdb_streams.sql` |
| `tr_OrderItems_RecalcAndQueue` | `STREAM_ORDER_ITEMS_CHANGES` | `TASK_ORDER_ITEMS_RECALC` | `01_stressdb_streams.sql` |
| `tr_Products_ListPriceAudit` | `STREAM_PRODUCTS_CHANGES` | `TASK_PRODUCTS_PRICE_AUDIT` | `01_stressdb_streams.sql` |
| `tr_Employees_Audit` | `STREAM_ERP_EMPLOYEES_CHANGES` | `TASK_ERP_EMPLOYEES_AUDIT` | `02_erp_streams.sql` |
| `tr_PayrollLines_Recalc` | `STREAM_ERP_PAYROLL_LINES_CHANGES` | `TASK_ERP_PAYROLL_RECALC` | `02_erp_streams.sql` |
| `tr_Accounts_Activity` | `STREAM_CRM_ACCOUNTS_CHANGES` | `TASK_CRM_ACCOUNTS_ACTIVITY` | `03_crm_streams.sql` |
| `tr_Sku_NoNegativeCost` (monitor only) | `STREAM_INV_SKU_CHANGES` | `TASK_INV_SKU_COST_GUARD` | `04_inventory_streams.sql` |

**INSTEAD OF triggers → Stored procedures** (callers must call the SP, not write directly):

| SQL Server trigger | Snowflake SP | File |
|---|---|---|
| `tr_vw_Orders_Dml_IOD` (INSTEAD OF DELETE) | `SP_SOFT_DELETE_ORDER(order_id)` | `06_dml_guard_procs.sql` |
| `tr_vw_Orders_Dml_IOU` (INSTEAD OF UPDATE) | `SP_UPDATE_ORDER(order_id, ...)` | `06_dml_guard_procs.sql` |
| `tr_vw_StockOrders_IOI` (INSTEAD OF INSERT) | `SP_INV_SOFT_INSERT_STOCK_ORDER(...)` | `05_inventory_procs.sql` |
| `tr_Opportunities_StageGuard` (AFTER UPDATE) | `SP_CRM_UPDATE_OPPORTUNITY_STAGE(opp_id, stage)` | `04_crm_procs.sql` |

### Functions

| SQL Server | Snowflake | Location |
|---|---|---|
| `fn_FormatMoney(@amount)` scalar UDF | `FN_FORMAT_MONEY(amount)` SQL UDF | `udfs/01_scalar_udfs.sql` + `udfs.tf` |
| `fn_OrderLineCount(@orderId)` inline TVF | `FN_ORDER_LINE_COUNT(order_id)` scalar UDF | `udfs/01_scalar_udfs.sql` + `udfs.tf` |

## Testing

Run after `terraform apply` completes:

```sql
-- Verify supporting tables exist
SELECT COUNT(*) FROM BRONZE.MIGRATION_AUDIT_LOG;
SELECT COUNT(*) FROM BRONZE.ORDER_EVENT_QUEUE;

-- Basic procedure smoke tests
CALL BRONZE.SP_LIST_OPEN_ORDERS();
CALL BRONZE.SP_REFRESH_ORDER_TOTALS(NULL);
CALL BRONZE.SP_DYNAMIC_SEARCH_ORDERS('Open', NULL, NULL, 'ORDER_DATE', 'DESC');
CALL BRONZE.FN_FORMAT_MONEY(12345.678);

-- Chained proc test (should append [C][B][A] to Notes)
CALL BRONZE.SP_CHAINED_A_OUTER(1);
SELECT NOTES FROM BRONZE.ORDERS WHERE ORDER_ID = 1;

-- MERGE upsert test
CALL BRONZE.SP_MERGE_UPSERT_CUSTOMERS(
    PARSE_JSON('[{"CustomerCode":"TST99","FullName":"Test User","Email":"t@t.com","Country":"CA"}]')
);
SELECT * FROM BRONZE.CUSTOMERS WHERE CUSTOMER_CODE = 'TST99';

-- Trigger replacement test: soft delete
CALL BRONZE.SP_SOFT_DELETE_ORDER(999);

-- Stream check (after any INSERT/UPDATE to BRONZE.ORDERS)
SELECT SYSTEM$STREAM_HAS_DATA('BRONZE.STREAM_ORDERS_CHANGES');

-- Task run history
SELECT NAME, STATE, COMPLETED_TIME, ERROR_MESSAGE
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
    SCHEDULED_TIME_RANGE_START => DATEADD('hour', -1, CURRENT_TIMESTAMP()),
    TASK_NAME => 'TASK_ORDERS_AUDIT'
));
```
