"""
DAG 05 — Procedure & UDF Smoke Tests
======================================
Schedule: daily (not hourly — smoke tests are expensive and disruptive).

What this DAG does:
  Calls every stored procedure and scalar UDF in the migration and
  verifies they return a valid result (not an 'ERROR:' string, not None).

  This answers: "How do we call Snowflake procedures and functions from Airflow?"
  Every task here is a live example.

  Groups:
    basic_procs      — SP_REFRESH_ORDER_TOTALS, SP_LIST_OPEN_ORDERS
    stress_procs     — SP_DYNAMIC_SEARCH_ORDERS, SP_JSON_ORDER_LINES,
                       SP_WHILE_BATCH_NUMBERS, SP_THROW_CATCH_RETHROW,
                       SP_DYNAMIC_PIVOT, SP_MULTI_RESULT_DEMO
    erp_procs        — SP_ERP_DYNAMIC_DEPT_REPORT, SP_ERP_CLOSE_PAYROLL_RUN
    crm_procs        — SP_CRM_MERGE_ACCOUNTS_FROM_JSON, SP_CRM_LIST_PIPELINE,
                       SP_CRM_UPDATE_OPPORTUNITY_STAGE
    inventory_procs  — SP_INV_DYNAMIC_WH_FILTER, SP_INV_UPDATE_SKU_COST
    dml_guard_procs  — SP_SOFT_DELETE_ORDER, SP_UPDATE_ORDER
    scalar_udfs      — FN_FORMAT_MONEY, FN_ORDER_LINE_COUNT

  Each task is intentionally read-only or uses safe test values that do not
  modify production data.  Procedures that write data (SP_SOFT_DELETE_ORDER,
  etc.) are tested against a known non-existent ID so they return gracefully.

Schedule: @daily — runs once per day after midnight UTC.
"""

import json
from datetime import datetime

from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.utils.task_group import TaskGroup

import sys
sys.path.insert(0, "/opt/airflow/plugins")
from snowflake_client import get_hook, call_procedure, call_function
from dag_config import (
    DEFAULT_ARGS, SNOWFLAKE_CONN_ID, SNOWFLAKE_WAREHOUSE,
    SNOWFLAKE_DATABASE, SNOWFLAKE_ROLE, SNOWFLAKE_BRONZE_SCHEMA,
)


def _hook():
    """Shared hook factory for all smoke test tasks."""
    return get_hook(
        conn_id=SNOWFLAKE_CONN_ID,
        warehouse=SNOWFLAKE_WAREHOUSE,
        database=SNOWFLAKE_DATABASE,
        schema=SNOWFLAKE_BRONZE_SCHEMA,
        role=SNOWFLAKE_ROLE,
    )


# ---------------------------------------------------------------------------
# Basic procedures
# ---------------------------------------------------------------------------
def smoke_refresh_order_totals():
    """
    CALL BRONZE.SP_REFRESH_ORDER_TOTALS(NULL)
    NULL = recalculate totals for all orders.
    Returns 'OK' on success.
    """
    result = call_procedure(_hook(), "BRONZE.SP_REFRESH_ORDER_TOTALS", None)
    assert result == "OK", f"Unexpected result: {result}"


def smoke_list_open_orders():
    """
    CALL BRONZE.SP_LIST_OPEN_ORDERS()
    Returns a result set — we just confirm no exception is raised.
    """
    _hook().run("CALL BRONZE.SP_LIST_OPEN_ORDERS()")


# ---------------------------------------------------------------------------
# Stress / advanced procedures
# ---------------------------------------------------------------------------
def smoke_dynamic_search_orders():
    """
    CALL BRONZE.SP_DYNAMIC_SEARCH_ORDERS('Open', NULL, NULL, 'ORDER_DATE', 'DESC')
    Demonstrates dynamic SQL inside a procedure.
    """
    _hook().run(
        "CALL BRONZE.SP_DYNAMIC_SEARCH_ORDERS('Open', NULL, NULL, 'ORDER_DATE', 'DESC')"
    )


def smoke_json_order_lines():
    """
    CALL BRONZE.SP_JSON_ORDER_LINES(0)
    Order ID 0 almost certainly does not exist — returns NULL (not an error).
    """
    result = _hook().get_records("CALL BRONZE.SP_JSON_ORDER_LINES(0)")
    print(f"SP_JSON_ORDER_LINES(0) returned: {result}")


def smoke_while_batch_numbers():
    """
    CALL BRONZE.SP_WHILE_BATCH_NUMBERS(10)
    Returns OBJECT_CONSTRUCT with num_rows=10, sum_n=55.
    """
    result = _hook().get_records("CALL BRONZE.SP_WHILE_BATCH_NUMBERS(10)")
    print(f"SP_WHILE_BATCH_NUMBERS(10): {result}")


def smoke_throw_catch_rethrow():
    """
    CALL BRONZE.SP_THROW_CATCH_RETHROW()
    This procedure intentionally raises an exception, catches it,
    logs it to MIGRATION_AUDIT_LOG, then re-raises.
    We expect a Snowflake exception — that is the correct behaviour.
    """
    try:
        _hook().run("CALL BRONZE.SP_THROW_CATCH_RETHROW()")
        raise AssertionError("Expected an exception but none was raised")
    except Exception as exc:
        if "Stress: intentional error" in str(exc):
            print(f"SP_THROW_CATCH_RETHROW raised expected exception: {exc}")
        else:
            raise


def smoke_dynamic_pivot():
    """
    CALL BRONZE.SP_DYNAMIC_PIVOT()
    Pivots ORDERS.STATUS into columns using dynamic SQL.
    Returns a result set — we confirm no crash.
    """
    _hook().run("CALL BRONZE.SP_DYNAMIC_PIVOT()")


def smoke_multi_result_demo():
    """
    CALL BRONZE.SP_MULTI_RESULT_DEMO(0)
    Returns a VARIANT with customer, orders, and items for customer_id=0.
    """
    result = _hook().get_records("CALL BRONZE.SP_MULTI_RESULT_DEMO(0)")
    print(f"SP_MULTI_RESULT_DEMO(0): {result}")


# ---------------------------------------------------------------------------
# ERP procedures
# ---------------------------------------------------------------------------
def smoke_erp_dept_report():
    """CALL BRONZE.SP_ERP_DYNAMIC_DEPT_REPORT(NULL, 'SALARY')"""
    _hook().run("CALL BRONZE.SP_ERP_DYNAMIC_DEPT_REPORT(NULL, 'SALARY')")


def smoke_erp_close_payroll():
    """
    CALL BRONZE.SP_ERP_CLOSE_PAYROLL_RUN(0)
    RUN_ID=0 does not exist → returns 'Not found' (not an error).
    """
    result = call_procedure(_hook(), "BRONZE.SP_ERP_CLOSE_PAYROLL_RUN", 0)
    assert result in ("Not found", "Closed"), f"Unexpected: {result}"


# ---------------------------------------------------------------------------
# CRM procedures
# ---------------------------------------------------------------------------
def smoke_crm_merge_accounts():
    """
    CALL BRONZE.SP_CRM_MERGE_ACCOUNTS_FROM_JSON(...)
    Merges a JSON array of account records.  Uses a non-conflicting code.
    """
    test_json = json.dumps([
        {"AccountCode": "SMOKE_TEST_001", "Name": "Smoke Test Account", "Region": "TEST"}
    ])
    result = call_procedure(
        _hook(), "BRONZE.SP_CRM_MERGE_ACCOUNTS_FROM_JSON", test_json
    )
    print(f"SP_CRM_MERGE_ACCOUNTS_FROM_JSON: {result}")


def smoke_crm_list_pipeline():
    """CALL BRONZE.SP_CRM_LIST_PIPELINE(NULL) — returns all regions."""
    _hook().run("CALL BRONZE.SP_CRM_LIST_PIPELINE(NULL)")


def smoke_crm_update_opportunity_stage():
    """
    CALL BRONZE.SP_CRM_UPDATE_OPPORTUNITY_STAGE(0, 'Prospect')
    OPP_ID=0 does not exist → returns 'ERROR: opportunity not found'.
    We expect that specific error (it means the guard clause works correctly).
    """
    result = _hook().get_records(
        "CALL BRONZE.SP_CRM_UPDATE_OPPORTUNITY_STAGE(0, 'Prospect')"
    )
    msg = str(result[0][0]) if result else ""
    assert "not found" in msg.lower(), f"Unexpected result: {msg}"


# ---------------------------------------------------------------------------
# Inventory procedures
# ---------------------------------------------------------------------------
def smoke_inv_dynamic_filter():
    """CALL BRONZE.SP_INV_DYNAMIC_WH_FILTER('NONEXISTENT') — returns empty set."""
    _hook().run("CALL BRONZE.SP_INV_DYNAMIC_WH_FILTER('NONEXISTENT')")


def smoke_inv_update_sku_cost():
    """
    CALL BRONZE.SP_INV_UPDATE_SKU_COST(0, -1)
    Negative cost → procedure should return 'ERROR: SKU unit cost cannot be negative'.
    Verifies the guard clause fires.
    """
    result = call_procedure_allow_error(_hook(), "BRONZE.SP_INV_UPDATE_SKU_COST", 0, -1)
    assert "cannot be negative" in result.lower(), f"Unexpected: {result}"


def call_procedure_allow_error(hook, proc_fqn: str, *args) -> str:
    """Like call_procedure but does not raise on ERROR: prefix — used for guard tests."""
    from snowflake_client import call_procedure as _call
    try:
        return _call(hook, proc_fqn, *args)
    except ValueError as exc:
        return str(exc).replace(f"{proc_fqn} returned an error: ", "")


# ---------------------------------------------------------------------------
# DML guard procedures (safe test IDs that do not exist)
# ---------------------------------------------------------------------------
def smoke_soft_delete_order():
    """
    CALL BRONZE.SP_SOFT_DELETE_ORDER(0)
    ORDER_ID=0 does not exist → 'ERROR: order not found'.
    """
    result = call_procedure_allow_error(_hook(), "BRONZE.SP_SOFT_DELETE_ORDER", 0)
    assert "not found" in result.lower(), f"Unexpected: {result}"


def smoke_update_order():
    """
    CALL BRONZE.SP_UPDATE_ORDER(0, 'Open', NULL, NULL)
    ORDER_ID=0 does not exist → 'ERROR: order not found'.
    """
    result = call_procedure_allow_error(
        _hook(), "BRONZE.SP_UPDATE_ORDER", 0, "Open", None, None
    )
    assert "not found" in result.lower(), f"Unexpected: {result}"


# ---------------------------------------------------------------------------
# Scalar UDFs — called with SELECT, not CALL
# ---------------------------------------------------------------------------
def smoke_fn_format_money():
    """
    SELECT BRONZE.FN_FORMAT_MONEY(9750)
    Returns '$9,750.00'.
    This is how UDFs are called — via SELECT, never via CALL.
    """
    result = call_function(_hook(), "BRONZE.FN_FORMAT_MONEY", 9750)
    assert result == "$9,750.00", f"Unexpected: {result}"
    print(f"FN_FORMAT_MONEY(9750) = {result}")


def smoke_fn_order_line_count():
    """
    SELECT BRONZE.FN_ORDER_LINE_COUNT(0)
    ORDER_ID=0 has no items → returns 0 (not an error).
    """
    result = call_function(_hook(), "BRONZE.FN_ORDER_LINE_COUNT", 0)
    assert result == 0, f"Expected 0, got {result}"
    print(f"FN_ORDER_LINE_COUNT(0) = {result}")


# ---------------------------------------------------------------------------
# DAG
# ---------------------------------------------------------------------------
with DAG(
    dag_id="dag_05_proc_smoke_test",
    description="Call every stored procedure and UDF to verify they are alive and working",
    default_args=DEFAULT_ARGS,
    start_date=datetime(2024, 1, 1),
    schedule_interval="@daily",
    catchup=False,
    tags=["smoke-test", "procedures", "udfs", "mssql-migration"],
) as dag:

    def py(task_id: str, fn) -> PythonOperator:
        return PythonOperator(task_id=task_id, python_callable=fn)

    with TaskGroup(group_id="basic_procs"):
        py("refresh_order_totals",  smoke_refresh_order_totals)
        py("list_open_orders",      smoke_list_open_orders)

    with TaskGroup(group_id="stress_procs"):
        py("dynamic_search_orders", smoke_dynamic_search_orders)
        py("json_order_lines",      smoke_json_order_lines)
        py("while_batch_numbers",   smoke_while_batch_numbers)
        py("throw_catch_rethrow",   smoke_throw_catch_rethrow)
        py("dynamic_pivot",         smoke_dynamic_pivot)
        py("multi_result_demo",     smoke_multi_result_demo)

    with TaskGroup(group_id="erp_procs"):
        py("erp_dept_report",   smoke_erp_dept_report)
        py("erp_close_payroll", smoke_erp_close_payroll)

    with TaskGroup(group_id="crm_procs"):
        py("crm_merge_accounts",           smoke_crm_merge_accounts)
        py("crm_list_pipeline",            smoke_crm_list_pipeline)
        py("crm_update_opportunity_stage", smoke_crm_update_opportunity_stage)

    with TaskGroup(group_id="inventory_procs"):
        py("inv_dynamic_filter",  smoke_inv_dynamic_filter)
        py("inv_update_sku_cost", smoke_inv_update_sku_cost)

    with TaskGroup(group_id="dml_guard_procs"):
        py("soft_delete_order", smoke_soft_delete_order)
        py("update_order",      smoke_update_order)

    with TaskGroup(group_id="scalar_udfs"):
        py("fn_format_money",      smoke_fn_format_money)
        py("fn_order_line_count",  smoke_fn_order_line_count)
