"""
snowflake_client.py — Snowflake helper layer for all migration DAGs.

This module is the single place that explains and implements how each
Snowflake object type is called from Airflow:

  Stored Procedures  →  call_procedure()   uses CALL <proc>(<args>)
  Scalar UDFs        →  call_function()    uses SELECT <fn>(<args>)
  Snowflake Tasks    →  manage_task()      uses ALTER TASK ... RESUME/SUSPEND
                        (Tasks run on Snowflake's own scheduler.
                         Airflow only manages their lifecycle, never triggers them.)
  Regular SQL        →  execute_sql()      any DML or query

Import this in every DAG:
    from plugins.snowflake_client import get_hook, call_procedure, call_function
"""

from __future__ import annotations

import logging
import os
from pathlib import Path
from typing import Any

log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Hook factory
# ---------------------------------------------------------------------------

def get_hook(
    conn_id: str,
    warehouse: str,
    database: str,
    schema: str,
    role: str,
):
    """
    Return a SnowflakeHook configured for this pipeline.

    The hook reads credentials from the Airflow connection 'conn_id'.
    Set that connection in: Airflow UI → Admin → Connections → snowflake_default
    """
    from airflow.providers.snowflake.hooks.snowflake import SnowflakeHook

    return SnowflakeHook(
        snowflake_conn_id=conn_id,
        warehouse=warehouse,
        database=database,
        schema=schema,
        role=role,
    )


# ---------------------------------------------------------------------------
# General SQL execution
# ---------------------------------------------------------------------------

def execute_sql(hook, sql: str) -> list[tuple]:
    """Run any SQL statement and return all rows."""
    log.info("Executing SQL:\n%s", sql.strip())
    return hook.get_records(sql)


def execute_sql_file(hook, sql_file_path: str) -> None:
    """
    Read a .sql file and run each semicolon-delimited statement.
    Blank lines and comments-only blocks are skipped.
    """
    sql_text = Path(sql_file_path).read_text()
    statements = [s.strip() for s in sql_text.split(";") if s.strip()]
    for stmt in statements:
        if not stmt.startswith("--"):
            log.info("Running statement from %s:\n%s", sql_file_path, stmt[:120])
            hook.run(stmt)


# ---------------------------------------------------------------------------
# Stored Procedures
# ---------------------------------------------------------------------------

def call_procedure(hook, proc_fqn: str, *args: Any) -> str:
    """
    Call a Snowflake stored procedure and return its result as a string.

    How it works:
        Airflow sends:  CALL BRONZE.SP_REFRESH_ORDER_TOTALS(NULL)
        Snowflake runs the procedure body and returns a VARCHAR result.
        We check the result for the 'ERROR:' prefix our procedures use.

    Examples:
        # Recalculate all order totals (NULL = all orders)
        result = call_procedure(hook, "BRONZE.SP_REFRESH_ORDER_TOTALS", None)

        # Soft-delete a specific order
        result = call_procedure(hook, "BRONZE.SP_SOFT_DELETE_ORDER", 42)

        # Update an opportunity stage
        result = call_procedure(hook, "BRONZE.SP_CRM_UPDATE_OPPORTUNITY_STAGE", 7, "Won")

    Raises:
        ValueError if the procedure returns an 'ERROR:' prefixed string.
    """
    formatted_args = []
    for arg in args:
        if arg is None:
            formatted_args.append("NULL")
        elif isinstance(arg, str):
            safe = arg.replace("'", "''")
            formatted_args.append(f"'{safe}'")
        elif isinstance(arg, bool):
            formatted_args.append("TRUE" if arg else "FALSE")
        else:
            formatted_args.append(str(arg))

    sql = f"CALL {proc_fqn}({', '.join(formatted_args)})"
    log.info("Calling procedure: %s", sql)

    rows = hook.get_records(sql)
    result = str(rows[0][0]) if rows else ""
    log.info("Procedure %s returned: %s", proc_fqn, result)

    if result.startswith("ERROR:"):
        raise ValueError(f"{proc_fqn} returned an error: {result}")

    return result


# ---------------------------------------------------------------------------
# Scalar UDFs (User-Defined Functions)
# ---------------------------------------------------------------------------

def call_function(hook, func_fqn: str, *args: Any) -> Any:
    """
    Call a Snowflake scalar UDF and return its single value.

    How it works:
        Airflow sends:  SELECT BRONZE.FN_FORMAT_MONEY(1234.56)
        Snowflake evaluates the UDF body (written in SQL or JavaScript)
        and returns the scalar result. UDFs are called inside SQL — they
        are NOT called with CALL, only procedures are.

    Examples:
        # Format a number as a money string using FN_FORMAT_MONEY
        formatted = call_function(hook, "BRONZE.FN_FORMAT_MONEY", 9750.0)
        # returns '$9,750.00'

        # Count line items for order 101
        count = call_function(hook, "BRONZE.FN_ORDER_LINE_COUNT", 101)
        # returns 3
    """
    formatted_args = []
    for arg in args:
        if arg is None:
            formatted_args.append("NULL")
        elif isinstance(arg, str):
            safe = arg.replace("'", "''")
            formatted_args.append(f"'{safe}'")
        else:
            formatted_args.append(str(arg))

    sql = f"SELECT {func_fqn}({', '.join(formatted_args)})"
    log.info("Calling UDF: %s", sql)

    rows = hook.get_records(sql)
    result = rows[0][0] if rows else None
    log.info("UDF %s returned: %s", func_fqn, result)
    return result


# ---------------------------------------------------------------------------
# Snowflake Tasks
# ---------------------------------------------------------------------------

def manage_task(hook, task_fqn: str, action: str) -> None:
    """
    Resume or suspend a Snowflake Task.

    How Snowflake Tasks work vs. Airflow:
        Snowflake Tasks run on Snowflake's own internal scheduler
        (e.g., 'SCHEDULE = 1 MINUTE'). Airflow does NOT trigger them.
        Airflow only manages their lifecycle — resume after deployment,
        suspend for maintenance windows.

        The tasks in this project (TASK_ORDERS_AUDIT, TASK_ORDER_ITEMS_RECALC,
        TASK_PRODUCTS_PRICE_AUDIT) fire automatically whenever
        SYSTEM$STREAM_HAS_DATA() returns true. They audit CDC changes into
        MIGRATION_AUDIT_LOG and keep ORDER totals in sync.

    Examples:
        manage_task(hook, "BRONZE.TASK_ORDERS_AUDIT", "RESUME")
        manage_task(hook, "BRONZE.TASK_ORDERS_AUDIT", "SUSPEND")
    """
    action = action.upper()
    if action not in ("RESUME", "SUSPEND"):
        raise ValueError(f"Task action must be RESUME or SUSPEND, got: {action}")

    sql = f"ALTER TASK {task_fqn} {action}"
    log.info("Managing task: %s", sql)
    hook.run(sql)
    log.info("Task %s %sd", task_fqn, action.lower())


# ---------------------------------------------------------------------------
# Validation helpers
# ---------------------------------------------------------------------------

def assert_row_counts(hook, table_minimums: dict[str, int]) -> None:
    """
    Check that each table meets a minimum row count.

    Raises AssertionError listing every table that falls short.

    Example:
        assert_row_counts(hook, {
            "BRONZE.CUSTOMERS":  1,
            "BRONZE.ORDERS":     1,
            "BRONZE.PRODUCTS":   1,
        })
    """
    failures = []
    for table, minimum in table_minimums.items():
        count = hook.get_records(f"SELECT COUNT(*) FROM {table}")[0][0]
        log.info("Row count %s: %d (min=%d)", table, count, minimum)
        if count < minimum:
            failures.append(f"  {table}: {count} rows, expected >= {minimum}")

    if failures:
        raise AssertionError("Row count validation failed:\n" + "\n".join(failures))


def get_row_counts(hook, tables: list[str]) -> dict[str, int]:
    """Return a dict of table → row count for reporting."""
    counts = {}
    for table in tables:
        counts[table] = hook.get_records(f"SELECT COUNT(*) FROM {table}")[0][0]
        log.info("Count %s: %d", table, counts[table])
    return counts
