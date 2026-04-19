"""
DAG 01 — Ingest Bronze
======================
Schedule: every hour

What this DAG does:
  1. COPY new DMS Parquet files from S3 into the RAW variant table.
  2. MERGE each domain's tables from RAW into typed Bronze tables using
     incremental watermarks (_DMS_COMMIT_TS).  All four domains run in
     parallel after the COPY step finishes.
  3. Call SP_REFRESH_ORDER_TOTALS to sync ORDERS.TOTAL_AMOUNT with
     ORDER_ITEMS after the merge (replaces the SQL Server computed column).
  4. Resume the three CDC Tasks so they start watching for stream changes.

Domain task groups (run in parallel):
  orders_domain    → CATEGORIES, CUSTOMERS, PRODUCTS, ORDERS, ORDER_ITEMS
  erp_domain       → ERP_DEPARTMENTS, ERP_EMPLOYEES, ERP_PAYROLL_RUNS, ERP_PAYROLL_LINES
  crm_domain       → CRM_ACCOUNTS, CRM_CONTACTS, CRM_OPPORTUNITIES
  inventory_domain → INV_WAREHOUSES, INV_SKU, INV_STOCK_MOVEMENTS

Downstream: dag_02_silver_snapshots waits for 'merge_all_domains' via ExternalTaskSensor.
"""

import os
from datetime import datetime
from pathlib import Path

from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.providers.snowflake.operators.snowflake import SnowflakeOperator
from airflow.utils.task_group import TaskGroup

import sys
sys.path.insert(0, "/opt/airflow/plugins")
from snowflake_client import get_hook, call_procedure, manage_task, assert_row_counts
from dag_config import (
    DEFAULT_ARGS, SNOWFLAKE_CONN_ID, SNOWFLAKE_WAREHOUSE,
    SNOWFLAKE_DATABASE, SNOWFLAKE_ROLE, SNOWFLAKE_BRONZE_SCHEMA,
    SNOWFLAKE_RAW_SCHEMA, CDC_TASKS, BRONZE_TABLES,
)

# Directory where the SQL files for this DAG live
SQL_DIR = Path("/opt/airflow/sql/bronze")


# ---------------------------------------------------------------------------
# Helper: read a SQL file and run it through the Snowflake hook
# ---------------------------------------------------------------------------
def run_sql_file(sql_filename: str) -> None:
    hook = get_hook(
        conn_id=SNOWFLAKE_CONN_ID,
        warehouse=SNOWFLAKE_WAREHOUSE,
        database=SNOWFLAKE_DATABASE,
        schema=SNOWFLAKE_BRONZE_SCHEMA,
        role=SNOWFLAKE_ROLE,
    )
    sql_path = SQL_DIR / sql_filename
    sql_text = sql_path.read_text()

    # Split on semicolons and run each statement separately
    statements = [s.strip() for s in sql_text.split(";") if s.strip() and not s.strip().startswith("--")]
    for stmt in statements:
        hook.run(stmt)


# ---------------------------------------------------------------------------
# Post-merge: call the stored procedure that keeps ORDERS.TOTAL_AMOUNT in sync.
# This is how Airflow calls a Snowflake stored procedure.
# ---------------------------------------------------------------------------
def refresh_order_totals() -> None:
    """
    Calls SP_REFRESH_ORDER_TOTALS(NULL) — NULL means 'recalculate all orders'.
    Passing a specific ORDER_ID would recalculate just that order.

    How it works internally:
        Airflow sends: CALL BRONZE.SP_REFRESH_ORDER_TOTALS(NULL)
        The procedure runs: UPDATE ORDERS SET TOTAL_AMOUNT = SUM(LINE_TOTAL)...
    """
    hook = get_hook(
        conn_id=SNOWFLAKE_CONN_ID,
        warehouse=SNOWFLAKE_WAREHOUSE,
        database=SNOWFLAKE_DATABASE,
        schema=SNOWFLAKE_BRONZE_SCHEMA,
        role=SNOWFLAKE_ROLE,
    )
    result = call_procedure(hook, "BRONZE.SP_REFRESH_ORDER_TOTALS", None)
    print(f"SP_REFRESH_ORDER_TOTALS result: {result}")


# ---------------------------------------------------------------------------
# Post-merge: resume CDC tasks so Snowflake's scheduler picks up stream data.
# Airflow does NOT trigger Tasks directly — it only resumes/suspends them.
# ---------------------------------------------------------------------------
def resume_cdc_tasks() -> None:
    """
    Resumes the three Snowflake Tasks that audit CDC changes.

    How Snowflake Tasks work:
        Each task has SCHEDULE = '1 MINUTE' and a WHEN clause:
            WHEN SYSTEM$STREAM_HAS_DATA('BRONZE.STREAM_ORDERS_CHANGES')
        When the stream has new rows, Snowflake fires the task automatically.
        Airflow only manages lifecycle (RESUME / SUSPEND).
    """
    hook = get_hook(
        conn_id=SNOWFLAKE_CONN_ID,
        warehouse=SNOWFLAKE_WAREHOUSE,
        database=SNOWFLAKE_DATABASE,
        schema=SNOWFLAKE_BRONZE_SCHEMA,
        role=SNOWFLAKE_ROLE,
    )
    for task_fqn in CDC_TASKS:
        manage_task(hook, task_fqn, "RESUME")


# ---------------------------------------------------------------------------
# Row-count gate: fail the DAG if any core Bronze table is still empty
# ---------------------------------------------------------------------------
def validate_bronze_counts() -> None:
    hook = get_hook(
        conn_id=SNOWFLAKE_CONN_ID,
        warehouse=SNOWFLAKE_WAREHOUSE,
        database=SNOWFLAKE_DATABASE,
        schema=SNOWFLAKE_BRONZE_SCHEMA,
        role=SNOWFLAKE_ROLE,
    )
    # At least one row in every core table — catches a failed MERGE silently
    minimums = {t: 1 for domain_tables in BRONZE_TABLES.values() for t in domain_tables}
    assert_row_counts(hook, minimums)


# ---------------------------------------------------------------------------
# DAG definition
# ---------------------------------------------------------------------------
COPY_INTO_SQL = f"""
COPY INTO {SNOWFLAKE_DATABASE}.{SNOWFLAKE_RAW_SCHEMA}.RAW_DMS_VARIANT(V)
FROM @{SNOWFLAKE_DATABASE}.{SNOWFLAKE_RAW_SCHEMA}.STG_DMS_MSSQL
FILE_FORMAT = (TYPE = PARQUET)
FORCE = FALSE;
"""

with DAG(
    dag_id="dag_01_ingest_bronze",
    description="COPY DMS files from S3 → RAW, then MERGE into all Bronze domain tables",
    default_args=DEFAULT_ARGS,
    start_date=datetime(2024, 1, 1),
    schedule_interval="@hourly",
    catchup=False,
    tags=["bronze", "ingest", "mssql-migration"],
) as dag:

    # Step 1: load new Parquet files from S3 into the RAW variant table.
    # FORCE=FALSE means already-loaded files are skipped (idempotent).
    copy_into_raw = SnowflakeOperator(
        task_id="copy_into_raw",
        snowflake_conn_id=SNOWFLAKE_CONN_ID,
        sql=COPY_INTO_SQL,
        warehouse=SNOWFLAKE_WAREHOUSE,
        database=SNOWFLAKE_DATABASE,
        schema=SNOWFLAKE_RAW_SCHEMA,
        role=SNOWFLAKE_ROLE,
    )

    # Step 2: merge all four domains in parallel.
    with TaskGroup(group_id="merge_all_domains") as merge_all:

        with TaskGroup(group_id="orders_domain"):
            PythonOperator(
                task_id="merge_orders",
                python_callable=run_sql_file,
                op_args=["01_merge_orders.sql"],
            )

        with TaskGroup(group_id="erp_domain"):
            PythonOperator(
                task_id="merge_erp",
                python_callable=run_sql_file,
                op_args=["02_merge_erp.sql"],
            )

        with TaskGroup(group_id="crm_domain"):
            PythonOperator(
                task_id="merge_crm",
                python_callable=run_sql_file,
                op_args=["03_merge_crm.sql"],
            )

        with TaskGroup(group_id="inventory_domain"):
            PythonOperator(
                task_id="merge_inventory",
                python_callable=run_sql_file,
                op_args=["04_merge_inventory.sql"],
            )

    # Step 3: recalculate order totals (calls SP_REFRESH_ORDER_TOTALS stored procedure).
    recalc_totals = PythonOperator(
        task_id="refresh_order_totals",
        python_callable=refresh_order_totals,
    )

    # Step 4: resume the Snowflake CDC Tasks so they start processing new stream data.
    resume_tasks = PythonOperator(
        task_id="resume_cdc_tasks",
        python_callable=resume_cdc_tasks,
    )

    # Step 5: fail-fast check — every Bronze table must have at least one row.
    count_check = PythonOperator(
        task_id="validate_bronze_counts",
        python_callable=validate_bronze_counts,
    )

    # Pipeline order
    copy_into_raw >> merge_all >> recalc_totals >> resume_tasks >> count_check
