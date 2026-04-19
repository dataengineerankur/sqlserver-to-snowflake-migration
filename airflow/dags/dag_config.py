"""
dag_config.py — shared settings for all MSSQL → Snowflake migration DAGs.

All DAGs and the domain pipeline factory import from here.
Change a value once; it applies to every domain pipeline automatically.
"""

from datetime import timedelta

# ---------------------------------------------------------------------------
# Snowflake connection
# Set via Airflow UI: Admin → Connections → snowflake_default
# Or override with env var AIRFLOW_CONN_SNOWFLAKE_DEFAULT in docker-compose.yml
# ---------------------------------------------------------------------------
SNOWFLAKE_CONN_ID       = "snowflake_default"
SNOWFLAKE_WAREHOUSE     = "WH_MSSQL_MIGRATION"
SNOWFLAKE_DATABASE      = "MSSQL_MIGRATION_LAB"
SNOWFLAKE_ROLE          = "ACCOUNTADMIN"
SNOWFLAKE_RAW_SCHEMA    = "RAW_MSSQL"
SNOWFLAKE_BRONZE_SCHEMA = "BRONZE"

# ---------------------------------------------------------------------------
# dbt — Docker image built from dbt/Dockerfile
# ---------------------------------------------------------------------------
DBT_IMAGE       = "dbt-migration:latest"
DBT_PROJECT_DIR = "/opt/airflow/dbt"
DBT_PROFILES    = "/opt/airflow/dbt_profiles"

# ---------------------------------------------------------------------------
# Default task settings applied to every task in every domain DAG
# ---------------------------------------------------------------------------
DEFAULT_ARGS = {
    "owner": "data-platform",
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
    "email_on_failure": False,
}

# ---------------------------------------------------------------------------
# CDC Tasks managed by the Orders pipeline.
# Snowflake runs these on its own 1-minute scheduler — Airflow only
# resumes them after a successful Bronze ingest.
# ---------------------------------------------------------------------------
CDC_TASKS = [
    "BRONZE.TASK_ORDERS_AUDIT",
    "BRONZE.TASK_ORDER_ITEMS_RECALC",
    "BRONZE.TASK_PRODUCTS_PRICE_AUDIT",
]

# ---------------------------------------------------------------------------
# Domain pipeline configuration
#
# Each entry drives the domain_pipeline_factory to build a complete DAG:
#   dag_<domain_name>_pipeline
#
# Fields:
#   merge_sql       — SQL file under airflow/sql/bronze/ that MERGEs this domain
#   snapshots       — list of dbt snapshot names (run after Bronze merge)
#   dbt_selector    — dbt --select string for stg + int + gold models
#   bronze_tables   — Bronze tables to row-count-check after merge
#   cdc_tasks       — Snowflake Tasks to RESUME after merge (optional)
#   schedule        — cron or @hourly / @daily (default: @hourly)
# ---------------------------------------------------------------------------
DOMAIN_CONFIGS = {
    "orders": {
        "description": "End-to-end pipeline for the Orders / StressTest domain "
                       "(Customers, Products, Orders, Order Items, Categories).",
        "merge_sql":   "01_merge_orders.sql",
        "snapshots":   ["snp_customers", "snp_products", "snp_orders"],
        "dbt_selector": "customers.* products.* orders.*",
        "bronze_tables": [
            f"{SNOWFLAKE_DATABASE}.{SNOWFLAKE_BRONZE_SCHEMA}.CATEGORIES",
            f"{SNOWFLAKE_DATABASE}.{SNOWFLAKE_BRONZE_SCHEMA}.CUSTOMERS",
            f"{SNOWFLAKE_DATABASE}.{SNOWFLAKE_BRONZE_SCHEMA}.PRODUCTS",
            f"{SNOWFLAKE_DATABASE}.{SNOWFLAKE_BRONZE_SCHEMA}.ORDERS",
            f"{SNOWFLAKE_DATABASE}.{SNOWFLAKE_BRONZE_SCHEMA}.ORDER_ITEMS",
        ],
        "cdc_tasks": CDC_TASKS,
        "schedule": "@hourly",
    },

    "erp": {
        "description": "End-to-end pipeline for the ERP domain "
                       "(Departments, Employees, Payroll Runs, Payroll Lines).",
        "merge_sql":   "02_merge_erp.sql",
        "snapshots":   ["snp_erp_employees"],
        "dbt_selector": "erp.*",
        "bronze_tables": [
            f"{SNOWFLAKE_DATABASE}.{SNOWFLAKE_BRONZE_SCHEMA}.ERP_DEPARTMENTS",
            f"{SNOWFLAKE_DATABASE}.{SNOWFLAKE_BRONZE_SCHEMA}.ERP_EMPLOYEES",
            f"{SNOWFLAKE_DATABASE}.{SNOWFLAKE_BRONZE_SCHEMA}.ERP_PAYROLL_RUNS",
            f"{SNOWFLAKE_DATABASE}.{SNOWFLAKE_BRONZE_SCHEMA}.ERP_PAYROLL_LINES",
        ],
        "cdc_tasks": [],
        "schedule": "@hourly",
    },

    "crm": {
        "description": "End-to-end pipeline for the CRM domain "
                       "(Accounts, Contacts, Opportunities).",
        "merge_sql":   "03_merge_crm.sql",
        "snapshots":   ["snp_crm_accounts", "snp_crm_opportunities"],
        "dbt_selector": "crm.*",
        "bronze_tables": [
            f"{SNOWFLAKE_DATABASE}.{SNOWFLAKE_BRONZE_SCHEMA}.CRM_ACCOUNTS",
            f"{SNOWFLAKE_DATABASE}.{SNOWFLAKE_BRONZE_SCHEMA}.CRM_CONTACTS",
            f"{SNOWFLAKE_DATABASE}.{SNOWFLAKE_BRONZE_SCHEMA}.CRM_OPPORTUNITIES",
        ],
        "cdc_tasks": [],
        "schedule": "@hourly",
    },

    "inventory": {
        "description": "End-to-end pipeline for the Inventory domain "
                       "(Warehouses, SKU catalogue, Stock Movements).",
        "merge_sql":   "04_merge_inventory.sql",
        "snapshots":   ["snp_inv_sku"],
        "dbt_selector": "inventory.*",
        "bronze_tables": [
            f"{SNOWFLAKE_DATABASE}.{SNOWFLAKE_BRONZE_SCHEMA}.INV_WAREHOUSES",
            f"{SNOWFLAKE_DATABASE}.{SNOWFLAKE_BRONZE_SCHEMA}.INV_SKU",
            f"{SNOWFLAKE_DATABASE}.{SNOWFLAKE_BRONZE_SCHEMA}.INV_STOCK_MOVEMENTS",
        ],
        "cdc_tasks": [],
        "schedule": "@hourly",
    },
}
