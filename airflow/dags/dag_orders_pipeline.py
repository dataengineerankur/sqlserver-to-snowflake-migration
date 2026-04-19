"""
DAG: dag_orders_pipeline
========================
Domain: Orders / StressTest  (SnowConvertStressDB)
Tables: Categories, Customers, Products, Orders, Order Items
Schedule: every hour

Pipeline (built by domain_pipeline_factory):
  wait_for_raw        → waits for dag_00_copy_raw to finish
  bronze_merge        → MERGE 5 tables from RAW using 01_merge_orders.sql
  resume_cdc_tasks    → RESUME TASK_ORDERS_AUDIT, TASK_ORDER_ITEMS_RECALC,
                         TASK_PRODUCTS_PRICE_AUDIT (Snowflake's internal scheduler
                         then fires them when stream data is available)
  silver_snapshots    → dbt snapshot: snp_customers, snp_products, snp_orders
  gold_transform      → dbt run: customers.* products.* orders.*
  quality_check       → dbt test: customers.* products.* orders.*
  row_count_gate      → assert each Bronze table has >= 1 row

To modify the Orders pipeline:
  - Change SQL:     edit airflow/sql/bronze/01_merge_orders.sql
  - Change models:  edit dbt/models/customers/ or dbt/models/orders/
  - Change schedule: edit DOMAIN_CONFIGS['orders']['schedule'] in dag_config.py
"""

import sys
sys.path.insert(0, "/opt/airflow/plugins")

from domain_pipeline_factory import create_domain_pipeline
from dag_config import (
    DEFAULT_ARGS, DOMAIN_CONFIGS,
    SNOWFLAKE_CONN_ID, SNOWFLAKE_WAREHOUSE, SNOWFLAKE_DATABASE,
    SNOWFLAKE_ROLE, SNOWFLAKE_BRONZE_SCHEMA,
    DBT_IMAGE, DBT_PROJECT_DIR, DBT_PROFILES,
)

dag = create_domain_pipeline(
    domain_name="orders",
    config=DOMAIN_CONFIGS["orders"],
    default_args=DEFAULT_ARGS,
    snowflake_conn_id=SNOWFLAKE_CONN_ID,
    snowflake_warehouse=SNOWFLAKE_WAREHOUSE,
    snowflake_database=SNOWFLAKE_DATABASE,
    snowflake_role=SNOWFLAKE_ROLE,
    snowflake_bronze_schema=SNOWFLAKE_BRONZE_SCHEMA,
    dbt_image=DBT_IMAGE,
    dbt_project_dir=DBT_PROJECT_DIR,
    dbt_profiles_dir=DBT_PROFILES,
)
