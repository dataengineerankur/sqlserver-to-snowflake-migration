"""
DAG: dag_crm_pipeline
======================
Domain: CRM  (LabCRM_DB)
Tables: CRM_Accounts, CRM_Contacts, CRM_Opportunities
Schedule: every hour

Pipeline (built by domain_pipeline_factory):
  wait_for_raw     → waits for dag_00_copy_raw to finish
  bronze_merge     → MERGE 3 tables from RAW using 03_merge_crm.sql
  resume_cdc_tasks → (no CDC tasks for CRM — skipped automatically)
  silver_snapshots → dbt snapshot: snp_crm_accounts, snp_crm_opportunities
  gold_transform   → dbt run: crm.*
  quality_check    → dbt test: crm.*
  row_count_gate   → assert each CRM Bronze table has >= 1 row

To modify the CRM pipeline:
  - Change SQL:     edit airflow/sql/bronze/03_merge_crm.sql
  - Change models:  edit dbt/models/crm/
  - Change schedule: edit DOMAIN_CONFIGS['crm']['schedule'] in dag_config.py
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
    domain_name="crm",
    config=DOMAIN_CONFIGS["crm"],
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
