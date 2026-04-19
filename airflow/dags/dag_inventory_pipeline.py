"""
DAG: dag_inventory_pipeline
============================
Domain: Inventory  (LabInventory_DB)
Tables: INV_Warehouses, INV_SKU, INV_Stock_Movements
Schedule: every hour

Pipeline (built by domain_pipeline_factory):
  wait_for_raw     → waits for dag_00_copy_raw to finish
  bronze_merge     → MERGE 3 tables from RAW using 04_merge_inventory.sql
  resume_cdc_tasks → (no CDC tasks for Inventory — skipped automatically)
  silver_snapshots → dbt snapshot: snp_inv_sku
  gold_transform   → dbt run: inventory.*
  quality_check    → dbt test: inventory.*
  row_count_gate   → assert each Inventory Bronze table has >= 1 row

Note on stock movements:
  INV_STOCK_MOVEMENTS is an append-only journal — movements are never deleted
  in practice (a reversal creates a new negative-quantity row).  The MERGE
  handles D records for DMS compatibility but they rarely fire.

To modify the Inventory pipeline:
  - Change SQL:     edit airflow/sql/bronze/04_merge_inventory.sql
  - Change models:  edit dbt/models/inventory/
  - Change schedule: edit DOMAIN_CONFIGS['inventory']['schedule'] in dag_config.py
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
    domain_name="inventory",
    config=DOMAIN_CONFIGS["inventory"],
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
