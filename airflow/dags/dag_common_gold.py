"""
DAG: dag_common_gold
=====================
Cross-domain Gold layer — reports and calendar dimension.
Schedule: every hour, runs after the Orders pipeline finishes.

What this DAG does:
  Builds the Gold models that join across multiple domains.
  These cannot run inside any single domain pipeline because they
  depend on data from more than one domain.

  Models:
    dim_date                — calendar dimension 2020-2034 (no upstream deps)
    rpt_order_line_detail   — orders + customers + products + categories
    rpt_open_orders         — open orders with customer name and days-open counter
    rpt_customer_order_totals — one row per customer with spend aggregates
    rpt_category_closure    — recursive category hierarchy closure table

Why waits on Orders (not all domains)?
  All five common models use orders / customers / products data.
  ERP/CRM/Inventory data is not needed for these reports.
  If you add a cross-domain report that needs CRM, add an extra
  ExternalTaskSensor for dag_crm_pipeline here.

Upstream:  dag_orders_pipeline → row_count_gate
"""

from datetime import datetime

from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.sensors.external_task import ExternalTaskSensor
from airflow.utils.task_group import TaskGroup

from dag_config import (
    DEFAULT_ARGS,
    DBT_IMAGE, DBT_PROJECT_DIR, DBT_PROFILES,
)

DBT_RUN_CMD = (
    f"docker run --rm "
    f"-v {DBT_PROJECT_DIR}:/dbt "
    f"-v {DBT_PROFILES}:/root/.dbt "
    f"{DBT_IMAGE} "
    f"dbt run --project-dir /dbt --profiles-dir /root/.dbt "
    f"--select {{selector}} --fail-fast"
)

DBT_TEST_CMD = (
    f"docker run --rm "
    f"-v {DBT_PROJECT_DIR}:/dbt "
    f"-v {DBT_PROFILES}:/root/.dbt "
    f"{DBT_IMAGE} "
    f"dbt test --project-dir /dbt --profiles-dir /root/.dbt "
    f"--select {{selector}}"
)


def dbt_run(task_id: str, selector: str) -> BashOperator:
    return BashOperator(
        task_id=task_id,
        bash_command=DBT_RUN_CMD.format(selector=selector),
    )


def dbt_test(task_id: str, selector: str) -> BashOperator:
    return BashOperator(
        task_id=task_id,
        bash_command=DBT_TEST_CMD.format(selector=selector),
    )


with DAG(
    dag_id="dag_common_gold",
    description="Build cross-domain Gold reports (dim_date, rpt_*) after Orders pipeline finishes.",
    default_args=DEFAULT_ARGS,
    start_date=datetime(2024, 1, 1),
    schedule_interval="@hourly",
    catchup=False,
    tags=["gold", "common", "reports", "mssql-migration"],
) as dag:

    # Wait for the Orders pipeline to complete — all rpt_* models need order data.
    wait_for_orders = ExternalTaskSensor(
        task_id="wait_for_orders_pipeline",
        external_dag_id="dag_orders_pipeline",
        external_task_id="row_count_gate",
        timeout=3600,
        poke_interval=60,
        mode="reschedule",
    )

    with TaskGroup(group_id="common_gold_models") as gold_group:
        # Calendar dimension — no upstream data dependency, always safe to run
        dbt_run("dim_date",                  "dim_date")
        dbt_run("rpt_order_line_detail",     "rpt_order_line_detail")
        dbt_run("rpt_open_orders",           "rpt_open_orders")
        dbt_run("rpt_customer_order_totals", "rpt_customer_order_totals")
        dbt_run("rpt_category_closure",      "rpt_category_closure")

    with TaskGroup(group_id="common_gold_tests") as test_group:
        dbt_test("test_dim_date",                  "dim_date")
        dbt_test("test_rpt_order_line_detail",     "rpt_order_line_detail")
        dbt_test("test_rpt_open_orders",           "rpt_open_orders")
        dbt_test("test_rpt_customer_order_totals", "rpt_customer_order_totals")
        dbt_test("test_rpt_category_closure",      "rpt_category_closure")

    wait_for_orders >> gold_group >> test_group
