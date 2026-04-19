"""
DAG 02 — Silver Snapshots (SCD Type-2)
=======================================
Schedule: every hour, triggers after dag_01_ingest_bronze finishes.

What this DAG does:
  Runs dbt snapshot for every domain to maintain SCD Type-2 history in
  the SILVER schema.  When a customer changes their email, or a product
  changes price, dbt snapshot closes the old row (sets dbt_valid_to) and
  inserts a new current row.

  Snapshots by domain (run in parallel):
    orders_snapshots    → snp_customers, snp_products, snp_orders
    erp_snapshots       → snp_erp_employees
    crm_snapshots       → snp_crm_accounts, snp_crm_opportunities
    inventory_snapshots → snp_inv_sku

Upstream:  ExternalTaskSensor waits for dag_01_ingest_bronze → validate_bronze_counts
Downstream: dag_03_gold_transforms waits for this DAG's 'all_snapshots' group.
"""

from datetime import datetime

from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.sensors.external_task import ExternalTaskSensor
from airflow.utils.task_group import TaskGroup

from dag_config import DEFAULT_ARGS, DBT_IMAGE, DBT_PROJECT_DIR, DBT_PROFILES

# Base dbt snapshot command — selects by snapshot name pattern
DBT_SNAPSHOT_CMD = (
    f"docker run --rm "
    f"-v {DBT_PROJECT_DIR}:/dbt "
    f"-v {DBT_PROFILES}:/root/.dbt "
    f"{DBT_IMAGE} "
    f"dbt snapshot --project-dir /dbt --profiles-dir /root/.dbt "
    f"--select {{snapshot_selector}}"
)


def snapshot_task(task_id: str, selector: str) -> BashOperator:
    """Return a BashOperator that runs dbt snapshot for the given selector."""
    return BashOperator(
        task_id=task_id,
        bash_command=DBT_SNAPSHOT_CMD.format(snapshot_selector=selector),
    )


with DAG(
    dag_id="dag_02_silver_snapshots",
    description="Run dbt snapshot for all domains to build SCD2 SILVER history",
    default_args=DEFAULT_ARGS,
    start_date=datetime(2024, 1, 1),
    schedule_interval="@hourly",
    catchup=False,
    tags=["silver", "snapshots", "scd2", "mssql-migration"],
) as dag:

    # Wait for Bronze ingest to complete before snapshotting
    wait_for_bronze = ExternalTaskSensor(
        task_id="wait_for_bronze_ingest",
        external_dag_id="dag_01_ingest_bronze",
        external_task_id="validate_bronze_counts",
        timeout=3600,
        poke_interval=60,
        mode="reschedule",
    )

    # Run all domain snapshots in parallel
    with TaskGroup(group_id="all_snapshots") as all_snapshots:

        with TaskGroup(group_id="orders_snapshots"):
            snapshot_task("snp_customers", "snp_customers")
            snapshot_task("snp_products",  "snp_products")
            snapshot_task("snp_orders",    "snp_orders")

        with TaskGroup(group_id="erp_snapshots"):
            snapshot_task("snp_erp_employees", "snp_erp_employees")

        with TaskGroup(group_id="crm_snapshots"):
            snapshot_task("snp_crm_accounts",      "snp_crm_accounts")
            snapshot_task("snp_crm_opportunities", "snp_crm_opportunities")

        with TaskGroup(group_id="inventory_snapshots"):
            snapshot_task("snp_inv_sku", "snp_inv_sku")

    wait_for_bronze >> all_snapshots
