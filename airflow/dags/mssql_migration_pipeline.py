"""
Airflow DAG: MSSQL → S3 (DMS) → Snowflake RAW → medallion layers.

Pipeline:
  1. copy_into_raw    — COPY INTO RAW_MSSQL.RAW_DMS_VARIANT from S3 DMS stage
  2. check_raw        — verify rows landed in RAW
  3. flatten_bronze   — INSERT INTO BRONZE from VARIANT using lateral flatten
  4. report           — print row counts for all layers

Requires Airflow connection: snowflake_conn_id = "snowflake_default"
Set via Airflow UI → Admin → Connections or via env var AIRFLOW_CONN_SNOWFLAKE_DEFAULT.
"""
from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.bash import BashOperator

try:
    from airflow.providers.snowflake.operators.snowflake import SnowflakeOperator
    SNOWFLAKE_AVAILABLE = True
except ImportError:
    SNOWFLAKE_AVAILABLE = False

DEFAULT_ARGS = {
    "owner": "data-platform",
    "retries": 1,
    "retry_delay": timedelta(minutes=2),
}

# ── Snowflake config ──────────────────────────────────────────────────────────
SNOWFLAKE_CONN_ID = "snowflake_default"
DATABASE = "MSSQL_MIGRATION_LAB"
RAW_SCHEMA = "RAW_MSSQL"
BRONZE_SCHEMA = "BRONZE"

# ── SQL statements ────────────────────────────────────────────────────────────

COPY_INTO_SQL = f"""
COPY INTO {DATABASE}.{RAW_SCHEMA}.RAW_DMS_VARIANT(V)
FROM @{DATABASE}.{RAW_SCHEMA}.STG_DMS_MSSQL
FILE_FORMAT = (TYPE = PARQUET)
FORCE = FALSE;
"""

ROW_COUNT_SQL = f"""
SELECT COUNT(*) AS raw_rows FROM {DATABASE}.{RAW_SCHEMA}.RAW_DMS_VARIANT;
"""

BRONZE_FLATTEN_SQL = f"""
USE DATABASE {DATABASE};

CREATE OR REPLACE TABLE {BRONZE_SCHEMA}.CUSTOMERS AS
  SELECT
    v:CustomerId::INT       AS customer_id,
    v:FullName::STRING      AS full_name,
    v:Email::STRING         AS email,
    v:CustomerCode::STRING  AS customer_code,
    v:Country::STRING       AS country,
    v:CreatedAt::TIMESTAMP  AS created_at,
    v:DMS_COMMIT_TS::TIMESTAMP AS _dms_ts,
    CURRENT_TIMESTAMP()     AS _loaded_at
  FROM {DATABASE}.{RAW_SCHEMA}.RAW_DMS_VARIANT
  WHERE v:CustomerId IS NOT NULL AND v:Email IS NOT NULL;

CREATE OR REPLACE TABLE {BRONZE_SCHEMA}.ORDERS AS
  SELECT
    v:OrderId::INT          AS order_id,
    v:CustomerId::INT       AS customer_id,
    v:OrderDate::DATE       AS order_date,
    v:TotalAmount::FLOAT    AS total_amount,
    v:Status::STRING        AS status,
    v:Notes::STRING         AS notes,
    v:DMS_COMMIT_TS::TIMESTAMP AS _dms_ts,
    CURRENT_TIMESTAMP()     AS _loaded_at
  FROM {DATABASE}.{RAW_SCHEMA}.RAW_DMS_VARIANT
  WHERE v:OrderId IS NOT NULL AND v:TotalAmount IS NOT NULL;

CREATE OR REPLACE TABLE {BRONZE_SCHEMA}.PRODUCTS AS
  SELECT
    v:ProductId::INT        AS product_id,
    v:CategoryId::INT       AS category_id,
    v:ProductName::STRING   AS product_name,
    v:SKU::STRING           AS sku,
    v:ListPrice::FLOAT      AS list_price,
    v:IsActive::BOOLEAN     AS is_active,
    v:DMS_COMMIT_TS::TIMESTAMP AS _dms_ts,
    CURRENT_TIMESTAMP()     AS _loaded_at
  FROM {DATABASE}.{RAW_SCHEMA}.RAW_DMS_VARIANT
  WHERE v:ProductId IS NOT NULL AND v:SKU IS NOT NULL;

CREATE OR REPLACE TABLE {BRONZE_SCHEMA}.CATEGORIES AS
  SELECT
    v:CategoryId::INT       AS category_id,
    v:CategoryName::STRING  AS category_name,
    v:Description::STRING   AS description,
    v:DMS_COMMIT_TS::TIMESTAMP AS _dms_ts,
    CURRENT_TIMESTAMP()     AS _loaded_at
  FROM {DATABASE}.{RAW_SCHEMA}.RAW_DMS_VARIANT
  WHERE v:CategoryName IS NOT NULL AND v:Description IS NOT NULL;

CREATE OR REPLACE TABLE {BRONZE_SCHEMA}.ORDER_ITEMS AS
  SELECT
    v:OrderItemId::INT      AS order_item_id,
    v:OrderId::INT          AS order_id,
    v:ProductId::INT        AS product_id,
    v:Quantity::INT         AS quantity,
    v:UnitPrice::FLOAT      AS unit_price,
    v:LineTotal::FLOAT      AS line_total,
    v:DMS_COMMIT_TS::TIMESTAMP AS _dms_ts,
    CURRENT_TIMESTAMP()     AS _loaded_at
  FROM {DATABASE}.{RAW_SCHEMA}.RAW_DMS_VARIANT
  WHERE v:OrderItemId IS NOT NULL;
"""

REPORT_SQL = f"""
SELECT 'RAW_DMS_VARIANT'   AS layer, COUNT(*) AS row_count FROM {DATABASE}.{RAW_SCHEMA}.RAW_DMS_VARIANT
UNION ALL
SELECT 'BRONZE.CUSTOMERS', COUNT(*) FROM {DATABASE}.{BRONZE_SCHEMA}.CUSTOMERS;
"""


with DAG(
    dag_id="mssql_s3_snowflake_dbt_bronze_silver_gold",
    default_args=DEFAULT_ARGS,
    start_date=datetime(2024, 1, 1),
    schedule_interval="@hourly",
    catchup=False,
    tags=["sqlserver", "snowflake", "dbt", "mssql-migration"],
) as dag:

    if SNOWFLAKE_AVAILABLE:
        copy_into_raw = SnowflakeOperator(
            task_id="copy_into_raw",
            snowflake_conn_id=SNOWFLAKE_CONN_ID,
            sql=COPY_INTO_SQL,
            warehouse="WH_MSSQL_MIGRATION",
            database=DATABASE,
            schema=RAW_SCHEMA,
            role="ACCOUNTADMIN",
        )

        check_raw = SnowflakeOperator(
            task_id="check_raw_row_count",
            snowflake_conn_id=SNOWFLAKE_CONN_ID,
            sql=ROW_COUNT_SQL,
            warehouse="WH_MSSQL_MIGRATION",
            database=DATABASE,
            schema=RAW_SCHEMA,
        )

        flatten_bronze = SnowflakeOperator(
            task_id="flatten_bronze",
            snowflake_conn_id=SNOWFLAKE_CONN_ID,
            sql=BRONZE_FLATTEN_SQL,
            warehouse="WH_MSSQL_MIGRATION",
            database=DATABASE,
            schema=BRONZE_SCHEMA,
            role="ACCOUNTADMIN",
        )

        report = SnowflakeOperator(
            task_id="report_row_counts",
            snowflake_conn_id=SNOWFLAKE_CONN_ID,
            sql=REPORT_SQL,
            warehouse="WH_MSSQL_MIGRATION",
            database=DATABASE,
        )

        copy_into_raw >> check_raw >> flatten_bronze >> report

    else:
        BashOperator(
            task_id="snowflake_provider_missing",
            bash_command=(
                "echo 'ERROR: apache-airflow-providers-snowflake not installed. "
                "Install it to run this pipeline.'"
            ),
        )
