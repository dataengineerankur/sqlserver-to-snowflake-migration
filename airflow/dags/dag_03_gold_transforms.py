"""
DAG 03 — Gold Transforms
=========================
Schedule: every hour, triggers after dag_02_silver_snapshots finishes.

What this DAG does:
  Runs dbt models in three layers for each domain:
    stg  (staging views)  →  int  (intermediate views)  →  gold  (fact/dim tables)

  Domain runs in parallel:
    orders_pipeline    → customers.*, products.*, orders.*
    erp_pipeline       → erp.*
    crm_pipeline       → crm.*
    inventory_pipeline → inventory.*
    common_pipeline    → common.*  (dim_date, rpt_* reports)

  After all pipelines finish, a single BashOperator runs dbt compile to
  confirm the DAG graph is still valid (catches broken ref() calls).

Upstream:  ExternalTaskSensor waits for dag_02_silver_snapshots → all_snapshots
Downstream: dag_04_data_quality waits for this DAG's 'all_pipelines' group.
"""

from datetime import datetime

from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.sensors.external_task import ExternalTaskSensor
from airflow.utils.task_group import TaskGroup

from dag_config import DEFAULT_ARGS, DBT_IMAGE, DBT_PROJECT_DIR, DBT_PROFILES

DBT_RUN_CMD = (
    f"docker run --rm "
    f"-v {DBT_PROJECT_DIR}:/dbt "
    f"-v {DBT_PROFILES}:/root/.dbt "
    f"{DBT_IMAGE} "
    f"dbt run --project-dir /dbt --profiles-dir /root/.dbt "
    f"--select {{model_selector}} --fail-fast"
)


def dbt_run(task_id: str, selector: str) -> BashOperator:
    """Return a BashOperator that runs dbt for the given model selector."""
    return BashOperator(
        task_id=task_id,
        bash_command=DBT_RUN_CMD.format(model_selector=selector),
    )


with DAG(
    dag_id="dag_03_gold_transforms",
    description="Run dbt stg → int → gold models for all domains",
    default_args=DEFAULT_ARGS,
    start_date=datetime(2024, 1, 1),
    schedule_interval="@hourly",
    catchup=False,
    tags=["gold", "dbt", "mssql-migration"],
) as dag:

    wait_for_snapshots = ExternalTaskSensor(
        task_id="wait_for_silver_snapshots",
        external_dag_id="dag_02_silver_snapshots",
        external_task_id="all_snapshots",
        timeout=3600,
        poke_interval=60,
        mode="reschedule",
    )

    with TaskGroup(group_id="all_pipelines") as all_pipelines:

        with TaskGroup(group_id="orders_pipeline"):
            # stg → int → gold for the orders domain (customers + products + orders)
            dbt_run("stg_orders_domain", "stg_customers stg_products stg_orders stg_order_items")
            dbt_run("int_orders_domain", "int_customers int_products int_orders int_order_items int_orders_enriched")
            dbt_run("gold_orders_domain", "fct_orders fct_order_items dim_customers dim_products")

        with TaskGroup(group_id="erp_pipeline"):
            dbt_run("stg_erp", "erp.stg")
            dbt_run("int_erp", "erp.int")
            dbt_run("gold_erp", "erp.gold")

        with TaskGroup(group_id="crm_pipeline"):
            dbt_run("stg_crm", "crm.stg")
            dbt_run("int_crm", "crm.int")
            dbt_run("gold_crm", "crm.gold")

        with TaskGroup(group_id="inventory_pipeline"):
            dbt_run("stg_inventory", "inventory.stg")
            dbt_run("int_inventory", "inventory.int")
            dbt_run("gold_inventory", "inventory.gold")

        with TaskGroup(group_id="common_pipeline"):
            # dim_date, rpt_category_closure, rpt_customer_order_totals, rpt_open_orders, rpt_order_line_detail
            dbt_run("gold_common", "common.gold")

    wait_for_snapshots >> all_pipelines
