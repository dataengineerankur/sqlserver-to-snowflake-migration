"""
DAG 04 — Data Quality
======================
Schedule: every hour, triggers after dag_03_gold_transforms finishes.

What this DAG does:
  1. Runs dbt test for every layer (Bronze sources, Silver snapshots, Gold models).
     dbt test checks the not_null / unique / accepted_values / relationships
     constraints defined in schema.yml.
  2. Runs a custom Snowflake SQL validation report that counts rows across all
     15 Bronze tables and flags any that are empty.
  3. Logs the count report to the task log for easy review.

This DAG does NOT block on warnings — only test failures (dbt exit code != 0)
will cause a task failure and Airflow retry.

Upstream:  ExternalTaskSensor waits for dag_03_gold_transforms → all_pipelines
"""

import logging
from datetime import datetime

from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator
from airflow.sensors.external_task import ExternalTaskSensor
from airflow.utils.task_group import TaskGroup
from pathlib import Path

import sys
sys.path.insert(0, "/opt/airflow/plugins")
from snowflake_client import get_hook, execute_sql
from dag_config import (
    DEFAULT_ARGS, SNOWFLAKE_CONN_ID, SNOWFLAKE_WAREHOUSE,
    SNOWFLAKE_DATABASE, SNOWFLAKE_ROLE, SNOWFLAKE_BRONZE_SCHEMA,
    DBT_IMAGE, DBT_PROJECT_DIR, DBT_PROFILES,
)

log = logging.getLogger(__name__)

VALIDATION_SQL_PATH = Path("/opt/airflow/sql/validation/row_count_checks.sql")

DBT_TEST_CMD = (
    f"docker run --rm "
    f"-v {DBT_PROJECT_DIR}:/dbt "
    f"-v {DBT_PROFILES}:/root/.dbt "
    f"{DBT_IMAGE} "
    f"dbt test --project-dir /dbt --profiles-dir /root/.dbt "
    f"--select {{selector}}"
)


def dbt_test(task_id: str, selector: str) -> BashOperator:
    return BashOperator(
        task_id=task_id,
        bash_command=DBT_TEST_CMD.format(selector=selector),
    )


def run_row_count_report() -> None:
    """
    Executes the row_count_checks.sql file against Snowflake and logs results.
    Any table showing 'WARN: empty' is printed clearly so the on-call engineer
    knows immediately which domain's ingest failed.
    """
    hook = get_hook(
        conn_id=SNOWFLAKE_CONN_ID,
        warehouse=SNOWFLAKE_WAREHOUSE,
        database=SNOWFLAKE_DATABASE,
        schema=SNOWFLAKE_BRONZE_SCHEMA,
        role=SNOWFLAKE_ROLE,
    )
    sql = VALIDATION_SQL_PATH.read_text()
    rows = execute_sql(hook, sql)

    log.info("=" * 60)
    log.info("BRONZE ROW COUNT REPORT")
    log.info("=" * 60)
    warnings = []
    for layer, table, count, status in rows:
        log.info("  %-10s  %-30s  %8d rows  %s", layer, table, count, status)
        if "WARN" in status:
            warnings.append(f"{layer}.{table}: {count} rows")

    if warnings:
        log.warning("EMPTY TABLES DETECTED:\n%s", "\n".join(warnings))
        # Do not raise — empty tables on first run before DMS lands data are expected.
        # Change to `raise` if you want to block downstream DAGs on empty Bronze.


with DAG(
    dag_id="dag_04_data_quality",
    description="Run dbt tests and row-count validation across all layers",
    default_args=DEFAULT_ARGS,
    start_date=datetime(2024, 1, 1),
    schedule_interval="@hourly",
    catchup=False,
    tags=["quality", "dbt-test", "validation", "mssql-migration"],
) as dag:

    wait_for_gold = ExternalTaskSensor(
        task_id="wait_for_gold_transforms",
        external_dag_id="dag_03_gold_transforms",
        external_task_id="all_pipelines",
        timeout=3600,
        poke_interval=60,
        mode="reschedule",
    )

    with TaskGroup(group_id="dbt_tests") as dbt_tests:

        # Test Bronze source constraints (not_null, unique on PKs)
        dbt_test("test_bronze_sources", "source:bronze")

        with TaskGroup(group_id="domain_model_tests"):
            dbt_test("test_orders",    "customers.* products.* orders.*")
            dbt_test("test_erp",       "erp.*")
            dbt_test("test_crm",       "crm.*")
            dbt_test("test_inventory", "inventory.*")
            dbt_test("test_common",    "common.*")

    # Custom row-count validation across all Bronze tables
    row_count_report = PythonOperator(
        task_id="bronze_row_count_report",
        python_callable=run_row_count_report,
    )

    wait_for_gold >> dbt_tests >> row_count_report
