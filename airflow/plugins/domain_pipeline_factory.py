"""
domain_pipeline_factory.py
===========================
Builds a complete bronze → silver → gold → quality Airflow DAG for any domain.

Every domain pipeline DAG (dag_orders_pipeline, dag_erp_pipeline, etc.) is
just a thin wrapper that calls create_domain_pipeline() with its config.
All the actual task wiring lives here — in one place.

Task flow inside each generated DAG:
─────────────────────────────────────
  wait_for_raw            ExternalTaskSensor on dag_00_copy_raw
       │
  bronze_merge            Runs the domain's MERGE SQL file (incremental, watermarked)
       │
  resume_cdc_tasks        Resumes Snowflake Tasks (orders domain only)
       │
  silver_snapshots/       TaskGroup — one dbt snapshot task per snapshot name
    snp_*
       │
  gold_transform          dbt run stg→int→gold for this domain
       │
  quality_check           dbt test for this domain's models
       │
  row_count_gate          Asserts every Bronze table has at least 1 row

To add a new domain:
  1. Add a new entry to DOMAIN_CONFIGS in dag_config.py.
  2. Create the MERGE SQL under airflow/sql/bronze/.
  3. Copy any domain DAG file, change the domain_name argument. Done.
"""

from __future__ import annotations

import logging
import sys
from pathlib import Path
from datetime import datetime
from typing import Any

from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator
from airflow.sensors.external_task import ExternalTaskSensor
from airflow.utils.task_group import TaskGroup

sys.path.insert(0, "/opt/airflow/plugins")
from snowflake_client import get_hook, call_procedure, manage_task, assert_row_counts

log = logging.getLogger(__name__)

SQL_DIR = Path("/opt/airflow/sql/bronze")


# ---------------------------------------------------------------------------
# Internal task callables
# ---------------------------------------------------------------------------

def _make_merge_callable(merge_sql: str, conn_id: str, warehouse: str,
                         database: str, schema: str, role: str):
    """Return a callable that runs the domain's MERGE SQL file."""
    def run_merge():
        hook = get_hook(conn_id, warehouse, database, schema, role)
        sql_text = (SQL_DIR / merge_sql).read_text()
        statements = [
            s.strip() for s in sql_text.split(";")
            if s.strip() and not s.strip().startswith("--")
        ]
        for stmt in statements:
            log.info("Running MERGE statement:\n%s...", stmt[:100])
            hook.run(stmt)
    return run_merge


def _make_cdc_resume_callable(cdc_tasks: list[str], conn_id: str, warehouse: str,
                              database: str, schema: str, role: str):
    """Return a callable that resumes Snowflake Tasks (orders domain only)."""
    def resume():
        if not cdc_tasks:
            log.info("No CDC tasks configured for this domain — skipping.")
            return
        hook = get_hook(conn_id, warehouse, database, schema, role)
        for task_fqn in cdc_tasks:
            manage_task(hook, task_fqn, "RESUME")
    return resume


def _make_count_check_callable(bronze_tables: list[str], conn_id: str, warehouse: str,
                               database: str, schema: str, role: str):
    """Return a callable that asserts every domain Bronze table has >= 1 row."""
    def check():
        hook = get_hook(conn_id, warehouse, database, schema, role)
        assert_row_counts(hook, {t: 1 for t in bronze_tables})
    return check


def _dbt_run(task_id: str, selector: str, image: str,
             project_dir: str, profiles_dir: str) -> BashOperator:
    cmd = (
        f"docker run --rm "
        f"-v {project_dir}:/dbt "
        f"-v {profiles_dir}:/root/.dbt "
        f"{image} "
        f"dbt run --project-dir /dbt --profiles-dir /root/.dbt "
        f"--select {selector} --fail-fast"
    )
    return BashOperator(task_id=task_id, bash_command=cmd)


def _dbt_test(task_id: str, selector: str, image: str,
              project_dir: str, profiles_dir: str) -> BashOperator:
    cmd = (
        f"docker run --rm "
        f"-v {project_dir}:/dbt "
        f"-v {profiles_dir}:/root/.dbt "
        f"{image} "
        f"dbt test --project-dir /dbt --profiles-dir /root/.dbt "
        f"--select {selector}"
    )
    return BashOperator(task_id=task_id, bash_command=cmd)


def _dbt_snapshot(task_id: str, snapshot_name: str, image: str,
                  project_dir: str, profiles_dir: str) -> BashOperator:
    cmd = (
        f"docker run --rm "
        f"-v {project_dir}:/dbt "
        f"-v {profiles_dir}:/root/.dbt "
        f"{image} "
        f"dbt snapshot --project-dir /dbt --profiles-dir /root/.dbt "
        f"--select {snapshot_name}"
    )
    return BashOperator(task_id=task_id, bash_command=cmd)


# ---------------------------------------------------------------------------
# Public factory function
# ---------------------------------------------------------------------------

def create_domain_pipeline(
    domain_name: str,
    config: dict[str, Any],
    default_args: dict,
    snowflake_conn_id: str,
    snowflake_warehouse: str,
    snowflake_database: str,
    snowflake_role: str,
    snowflake_bronze_schema: str,
    dbt_image: str,
    dbt_project_dir: str,
    dbt_profiles_dir: str,
) -> DAG:
    """
    Build and return a complete end-to-end domain pipeline DAG.

    The generated DAG id is:  dag_<domain_name>_pipeline
    e.g. dag_orders_pipeline, dag_crm_pipeline

    Args:
        domain_name:  short name used in task/DAG IDs (orders, erp, crm, inventory)
        config:       entry from DOMAIN_CONFIGS in dag_config.py
        default_args: Airflow default_args dict
        snowflake_*:  Snowflake connection parameters
        dbt_*:        dbt Docker image and mount paths
    """
    dag_id = f"dag_{domain_name}_pipeline"
    sf_args = dict(
        conn_id=snowflake_conn_id,
        warehouse=snowflake_warehouse,
        database=snowflake_database,
        schema=snowflake_bronze_schema,
        role=snowflake_role,
    )

    with DAG(
        dag_id=dag_id,
        description=config["description"],
        default_args=default_args,
        start_date=datetime(2024, 1, 1),
        schedule_interval=config.get("schedule", "@hourly"),
        catchup=False,
        tags=[domain_name, "domain-pipeline", "mssql-migration"],
    ) as dag:

        # ── Step 1: wait for the shared COPY step to finish ──────────────────
        wait_for_raw = ExternalTaskSensor(
            task_id="wait_for_raw_copy",
            external_dag_id="dag_00_copy_raw",
            external_task_id="copy_into_raw",
            timeout=3600,
            poke_interval=60,
            mode="reschedule",
        )

        # ── Step 2: merge this domain's tables from RAW into Bronze ──────────
        bronze_merge = PythonOperator(
            task_id="bronze_merge",
            python_callable=_make_merge_callable(config["merge_sql"], **sf_args),
        )

        # ── Step 3: resume CDC Snowflake Tasks (orders domain only) ──────────
        resume_cdc = PythonOperator(
            task_id="resume_cdc_tasks",
            python_callable=_make_cdc_resume_callable(
                config.get("cdc_tasks", []), **sf_args
            ),
        )

        # ── Step 4: run dbt snapshots for this domain (SCD2) ─────────────────
        with TaskGroup(group_id="silver_snapshots") as silver_group:
            for snap in config["snapshots"]:
                _dbt_snapshot(
                    task_id=snap,
                    snapshot_name=snap,
                    image=dbt_image,
                    project_dir=dbt_project_dir,
                    profiles_dir=dbt_profiles_dir,
                )

        # ── Step 5: run dbt stg → int → gold models for this domain ──────────
        gold_transform = _dbt_run(
            task_id="gold_transform",
            selector=config["dbt_selector"],
            image=dbt_image,
            project_dir=dbt_project_dir,
            profiles_dir=dbt_profiles_dir,
        )

        # ── Step 6: run dbt tests for this domain's models ───────────────────
        quality_check = _dbt_test(
            task_id="quality_check",
            selector=config["dbt_selector"],
            image=dbt_image,
            project_dir=dbt_project_dir,
            profiles_dir=dbt_profiles_dir,
        )

        # ── Step 7: row-count gate — fail if any Bronze table is empty ────────
        row_count_gate = PythonOperator(
            task_id="row_count_gate",
            python_callable=_make_count_check_callable(
                config["bronze_tables"], **sf_args
            ),
        )

        # ── Wire the pipeline ─────────────────────────────────────────────────
        (
            wait_for_raw
            >> bronze_merge
            >> resume_cdc
            >> silver_group
            >> gold_transform
            >> quality_check
            >> row_count_gate
        )

    return dag
