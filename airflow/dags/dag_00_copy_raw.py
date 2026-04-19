"""
DAG 00 — Copy Raw
==================
Schedule: every hour

This is the entry point for the entire pipeline.  It runs once per hour
and does one thing: COPY new DMS Parquet files from S3 into the shared
RAW_DMS_VARIANT table.

Why is COPY shared across domains?
    AWS DMS writes CDC events for ALL tables (orders, ERP, CRM, inventory)
    into a single S3 prefix.  Splitting COPY by domain would mean four
    separate jobs all scanning the same S3 path.  Running it once and
    letting all four domain pipelines read from the same RAW table is
    cheaper and correct.

After this DAG's 'copy_into_raw' task succeeds, all four domain pipelines
unblock simultaneously via their ExternalTaskSensors:
    dag_orders_pipeline    → picks up orders / customers / products data
    dag_erp_pipeline       → picks up ERP employees / payroll data
    dag_crm_pipeline       → picks up CRM accounts / opportunities data
    dag_inventory_pipeline → picks up warehouse / SKU / stock movement data
"""

from datetime import datetime

from airflow import DAG
from airflow.providers.snowflake.operators.snowflake import SnowflakeOperator

from dag_config import (
    DEFAULT_ARGS,
    SNOWFLAKE_CONN_ID,
    SNOWFLAKE_WAREHOUSE,
    SNOWFLAKE_DATABASE,
    SNOWFLAKE_ROLE,
    SNOWFLAKE_RAW_SCHEMA,
)

COPY_INTO_SQL = f"""
COPY INTO {SNOWFLAKE_DATABASE}.{SNOWFLAKE_RAW_SCHEMA}.RAW_DMS_VARIANT(V)
FROM @{SNOWFLAKE_DATABASE}.{SNOWFLAKE_RAW_SCHEMA}.STG_DMS_MSSQL
FILE_FORMAT = (TYPE = PARQUET)
FORCE = FALSE;
"""

with DAG(
    dag_id="dag_00_copy_raw",
    description="COPY new DMS Parquet files from S3 into RAW_DMS_VARIANT. "
                "All four domain pipelines wait for this DAG before merging.",
    default_args=DEFAULT_ARGS,
    start_date=datetime(2024, 1, 1),
    schedule_interval="@hourly",
    catchup=False,
    tags=["raw", "ingest", "shared", "mssql-migration"],
) as dag:

    copy_into_raw = SnowflakeOperator(
        task_id="copy_into_raw",
        snowflake_conn_id=SNOWFLAKE_CONN_ID,
        sql=COPY_INTO_SQL,
        warehouse=SNOWFLAKE_WAREHOUSE,
        database=SNOWFLAKE_DATABASE,
        schema=SNOWFLAKE_RAW_SCHEMA,
        role=SNOWFLAKE_ROLE,
    )
