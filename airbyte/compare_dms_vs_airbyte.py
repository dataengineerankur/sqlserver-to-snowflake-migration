#!/usr/bin/env python3
"""
compare_dms_vs_airbyte.py
=========================
Compares row counts between:
  - DMS path:     MSSQL_MIGRATION_LAB.BRONZE.*   (typed tables, after MERGE)
  - Airbyte path: MSSQL_MIGRATION_LAB.AIRBYTE_RAW.*  (raw tables written by Airbyte)

Prints a comparison table. A mismatch doesn't necessarily mean an error —
Airbyte may land more rows because it keeps historical versions, while DMS
MERGE de-duplicates by primary key. Row counts should be >= Bronze counts.

Usage:
    python compare_dms_vs_airbyte.py

Requirements:
    pip install snowflake-connector-python python-dotenv tabulate
"""

import os
from pathlib import Path
import snowflake.connector

try:
    from tabulate import tabulate
    HAS_TABULATE = True
except ImportError:
    HAS_TABULATE = False

# ── Load .env ─────────────────────────────────────────────────────────────────
env_file = Path(__file__).parent.parent / ".env"
if env_file.exists():
    from dotenv import load_dotenv
    load_dotenv(env_file)

SF_ACCOUNT  = os.getenv("SNOWFLAKE_ACCOUNT",  "")
SF_USER     = os.getenv("SNOWFLAKE_USER",      "")
SF_PASSWORD = os.getenv("SNOWFLAKE_PASSWORD",  "")
SF_ROLE     = os.getenv("SNOWFLAKE_ROLE",      "ACCOUNTADMIN")
SF_WH       = os.getenv("SNOWFLAKE_WAREHOUSE", "WH_MSSQL_MIGRATION")
SF_DB       = os.getenv("SNOWFLAKE_DATABASE",  "MSSQL_MIGRATION_LAB")

# Table mapping: BRONZE table → expected Airbyte table name
# Airbyte lowercases table names and prefixes with the schema name from SQL Server
TABLE_MAP = {
    # DMS Bronze table           Airbyte RAW table (Airbyte uses lowercase + source schema prefix)
    "BRONZE.CUSTOMERS":          "AIRBYTE_RAW.CUSTOMERS",
    "BRONZE.PRODUCTS":           "AIRBYTE_RAW.PRODUCTS",
    "BRONZE.CATEGORIES":         "AIRBYTE_RAW.CATEGORIES",
    "BRONZE.ORDERS":             "AIRBYTE_RAW.ORDERS",
    "BRONZE.ORDER_ITEMS":        "AIRBYTE_RAW.ORDER_ITEMS",
    "BRONZE.ERP_DEPARTMENTS":    "AIRBYTE_RAW.ERP_DEPARTMENTS",
    "BRONZE.ERP_EMPLOYEES":      "AIRBYTE_RAW.ERP_EMPLOYEES",
    "BRONZE.ERP_PAYROLL_RUNS":   "AIRBYTE_RAW.ERP_PAYROLL_RUNS",
    "BRONZE.ERP_PAYROLL_LINES":  "AIRBYTE_RAW.ERP_PAYROLL_LINES",
    "BRONZE.CRM_ACCOUNTS":       "AIRBYTE_RAW.CRM_ACCOUNTS",
    "BRONZE.CRM_CONTACTS":       "AIRBYTE_RAW.CRM_CONTACTS",
    "BRONZE.CRM_OPPORTUNITIES":  "AIRBYTE_RAW.CRM_OPPORTUNITIES",
    "BRONZE.INV_WAREHOUSES":     "AIRBYTE_RAW.INV_WAREHOUSES",
    "BRONZE.INV_SKU":            "AIRBYTE_RAW.INV_SKU",
    "BRONZE.INV_STOCK_MOVEMENTS":"AIRBYTE_RAW.INV_STOCK_MOVEMENTS",
}


def count_table(cur, full_table: str) -> int | None:
    try:
        cur.execute(f"SELECT COUNT(*) FROM {full_table}")
        return cur.fetchone()[0]
    except Exception as e:
        return None


def main():
    print("=" * 70)
    print("DMS vs Airbyte — Row Count Comparison")
    print(f"Database: {SF_DB}")
    print("=" * 70)

    con = snowflake.connector.connect(
        account=SF_ACCOUNT,
        user=SF_USER,
        password=SF_PASSWORD,
        role=SF_ROLE,
        warehouse=SF_WH,
        database=SF_DB,
    )
    cur = con.cursor()

    rows = []
    total_dms = 0
    total_airbyte = 0
    mismatches = 0

    for dms_table, airbyte_table in TABLE_MAP.items():
        dms_count      = count_table(cur, dms_table)
        airbyte_count  = count_table(cur, airbyte_table)

        if dms_count is None:
            dms_str = "MISSING"
        else:
            dms_str = f"{dms_count:,}"
            total_dms += dms_count

        if airbyte_count is None:
            ab_str = "MISSING"
        else:
            ab_str = f"{airbyte_count:,}"
            total_airbyte += airbyte_count

        if dms_count is not None and airbyte_count is not None:
            # Airbyte may have >= DMS count (it keeps raw history)
            if airbyte_count >= dms_count:
                status = "OK"
            else:
                status = "UNDER"
                mismatches += 1
        elif dms_count is None or airbyte_count is None:
            status = "MISSING"
            mismatches += 1
        else:
            status = "OK"

        short_name = dms_table.replace("BRONZE.", "")
        rows.append([short_name, dms_str, ab_str, status])

    # Summary row
    rows.append(["─" * 25, "─" * 10, "─" * 10, "─" * 8])
    rows.append(["TOTAL", f"{total_dms:,}", f"{total_airbyte:,}", ""])

    headers = ["Table", "DMS Bronze", "Airbyte RAW", "Status"]
    if HAS_TABULATE:
        print(tabulate(rows, headers=headers, tablefmt="rounded_outline"))
    else:
        # Fallback plain print
        header_line = f"{'Table':<28} {'DMS Bronze':>12} {'Airbyte RAW':>12} {'Status':<8}"
        print(header_line)
        print("-" * len(header_line))
        for row in rows:
            print(f"{row[0]:<28} {row[1]:>12} {row[2]:>12} {row[3]:<8}")

    print()
    if mismatches == 0:
        print("All tables accounted for in both paths.")
    else:
        print(f"{mismatches} table(s) have missing or under-count in Airbyte path.")
        print("Expected: Airbyte count >= DMS count (Airbyte keeps raw history).")

    print()
    print("Notes:")
    print("  DMS path   : SQL Server → S3 Parquet → RAW_DMS_VARIANT → MERGE → Bronze")
    print("  Airbyte path: SQL Server → Snowflake AIRBYTE_RAW (direct, no dedup)")
    print()
    print("Airbyte tables may have MORE rows than Bronze because:")
    print("  - Bronze MERGE de-duplicates by primary key (latest wins)")
    print("  - Airbyte append-dedup mode keeps one row per PK per sync cycle")
    print("  - Airbyte full-refresh keeps all historical inserts if you ran multiple syncs")

    cur.close()
    con.close()


if __name__ == "__main__":
    main()
