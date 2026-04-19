"""
dag_config.py — shared settings for all MSSQL → Snowflake migration DAGs.

All five DAGs import from here. Change a value once; it applies everywhere.
"""

from datetime import timedelta

# ---------------------------------------------------------------------------
# Snowflake connection
# Set up in Airflow UI: Admin → Connections → Add → conn_id = snowflake_default
# Or as env var: AIRFLOW_CONN_SNOWFLAKE_DEFAULT (see docker-compose.yml)
# ---------------------------------------------------------------------------
SNOWFLAKE_CONN_ID       = "snowflake_default"
SNOWFLAKE_WAREHOUSE     = "WH_MSSQL_MIGRATION"
SNOWFLAKE_DATABASE      = "MSSQL_MIGRATION_LAB"
SNOWFLAKE_ROLE          = "ACCOUNTADMIN"
SNOWFLAKE_RAW_SCHEMA    = "RAW_MSSQL"
SNOWFLAKE_BRONZE_SCHEMA = "BRONZE"

# ---------------------------------------------------------------------------
# dbt — the Docker image built from dbt/Dockerfile
# ---------------------------------------------------------------------------
DBT_IMAGE       = "dbt-migration:latest"
DBT_PROFILES    = "/opt/airflow/dbt_profiles"   # volume-mounted directory
DBT_PROJECT_DIR = "/opt/airflow/dbt"            # volume-mounted dbt project

# ---------------------------------------------------------------------------
# Airflow DAG defaults applied to every task
# ---------------------------------------------------------------------------
DEFAULT_ARGS = {
    "owner": "data-platform",
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
    "email_on_failure": False,
}

# ---------------------------------------------------------------------------
# Snowflake CDC Tasks managed by this pipeline.
# These run on Snowflake's internal scheduler — Airflow does not trigger them.
# DAG 1 resumes them after a successful ingest; maintenance jobs suspend them.
# ---------------------------------------------------------------------------
CDC_TASKS = [
    "BRONZE.TASK_ORDERS_AUDIT",         # audits INSERT/UPDATE on ORDERS
    "BRONZE.TASK_ORDER_ITEMS_RECALC",   # recalculates order totals on line changes
    "BRONZE.TASK_PRODUCTS_PRICE_AUDIT", # logs price changes on PRODUCTS
]

# ---------------------------------------------------------------------------
# Bronze tables by domain — used for row-count validation
# ---------------------------------------------------------------------------
BRONZE_TABLES = {
    "orders": [
        f"{SNOWFLAKE_DATABASE}.{SNOWFLAKE_BRONZE_SCHEMA}.CATEGORIES",
        f"{SNOWFLAKE_DATABASE}.{SNOWFLAKE_BRONZE_SCHEMA}.CUSTOMERS",
        f"{SNOWFLAKE_DATABASE}.{SNOWFLAKE_BRONZE_SCHEMA}.PRODUCTS",
        f"{SNOWFLAKE_DATABASE}.{SNOWFLAKE_BRONZE_SCHEMA}.ORDERS",
        f"{SNOWFLAKE_DATABASE}.{SNOWFLAKE_BRONZE_SCHEMA}.ORDER_ITEMS",
    ],
    "erp": [
        f"{SNOWFLAKE_DATABASE}.{SNOWFLAKE_BRONZE_SCHEMA}.ERP_DEPARTMENTS",
        f"{SNOWFLAKE_DATABASE}.{SNOWFLAKE_BRONZE_SCHEMA}.ERP_EMPLOYEES",
        f"{SNOWFLAKE_DATABASE}.{SNOWFLAKE_BRONZE_SCHEMA}.ERP_PAYROLL_RUNS",
        f"{SNOWFLAKE_DATABASE}.{SNOWFLAKE_BRONZE_SCHEMA}.ERP_PAYROLL_LINES",
    ],
    "crm": [
        f"{SNOWFLAKE_DATABASE}.{SNOWFLAKE_BRONZE_SCHEMA}.CRM_ACCOUNTS",
        f"{SNOWFLAKE_DATABASE}.{SNOWFLAKE_BRONZE_SCHEMA}.CRM_CONTACTS",
        f"{SNOWFLAKE_DATABASE}.{SNOWFLAKE_BRONZE_SCHEMA}.CRM_OPPORTUNITIES",
    ],
    "inventory": [
        f"{SNOWFLAKE_DATABASE}.{SNOWFLAKE_BRONZE_SCHEMA}.INV_WAREHOUSES",
        f"{SNOWFLAKE_DATABASE}.{SNOWFLAKE_BRONZE_SCHEMA}.INV_SKU",
        f"{SNOWFLAKE_DATABASE}.{SNOWFLAKE_BRONZE_SCHEMA}.INV_STOCK_MOVEMENTS",
    ],
}
