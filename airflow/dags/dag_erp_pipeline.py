"""
DAG: dag_erp_pipeline
======================
Domain: ERP  (LabERP_DB)
Tables: ERP_Departments, ERP_Employees, ERP_Payroll_Runs, ERP_Payroll_Lines
Schedule: every hour

Pipeline (built by domain_pipeline_factory):
  wait_for_raw     → waits for dag_00_copy_raw to finish
  bronze_merge     → MERGE 4 tables from RAW using 02_merge_erp.sql
  resume_cdc_tasks → (no CDC tasks for ERP — skipped automatically)
  silver_snapshots → dbt snapshot: snp_erp_employees
  gold_transform   → dbt run: erp.*
  quality_check    → dbt test: erp.*
  row_count_gate   → assert each ERP Bronze table has >= 1 row

To modify the ERP pipeline:
  - Change SQL:     edit airflow/sql/bronze/02_merge_erp.sql
  - Change models:  edit dbt/models/erp/
  - Change schedule: edit DOMAIN_CONFIGS['erp']['schedule'] in dag_config.py
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
    domain_name="erp",
    config=DOMAIN_CONFIGS["erp"],
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
