#!/usr/bin/env python3
"""
setup_connections.py
====================
Bootstraps an Airbyte workspace with:
  - Source:      Microsoft SQL Server  (all 4 lab databases)
  - Destination: Snowflake             (AIRBYTE_RAW schema in MSSQL_MIGRATION_LAB)
  - Connection:  Full refresh → Append (first run), then Incremental → Append Dedup

Run ONCE after `docker compose up -d` finishes:
    python setup_connections.py

Reads credentials from environment or a .env file.
Never hardcode credentials in this file.

Requirements:
    pip install requests python-dotenv
"""

import os
import sys
import json
import time
import requests
from pathlib import Path

# ── Load .env if present ──────────────────────────────────────────────────────
env_file = Path(__file__).parent.parent / ".env"
if env_file.exists():
    from dotenv import load_dotenv
    load_dotenv(env_file)

AIRBYTE_URL  = os.getenv("AIRBYTE_URL",      "http://localhost:8000")
AIRBYTE_USER = os.getenv("AIRBYTE_USERNAME", "airbyte")
AIRBYTE_PASS = os.getenv("AIRBYTE_PASSWORD", "password")

MSSQL_HOST   = os.getenv("MSSQL_HOST",     "host.docker.internal")  # points to host from Docker
MSSQL_PORT   = int(os.getenv("MSSQL_PORT", "1433"))
MSSQL_USER   = os.getenv("MSSQL_USER",     "sa")
MSSQL_PASS   = os.getenv("MSSQL_PASSWORD", "")
MSSQL_DB     = os.getenv("MSSQL_DB",       "SnowConvertStressDB")

SF_ACCOUNT   = os.getenv("SNOWFLAKE_ACCOUNT",   "")   # <org>-<account>
SF_USER      = os.getenv("SNOWFLAKE_USER",       "")
SF_PASS      = os.getenv("SNOWFLAKE_PASSWORD",   "")
SF_ROLE      = os.getenv("SNOWFLAKE_ROLE",       "ACCOUNTADMIN")
SF_WH        = os.getenv("SNOWFLAKE_WAREHOUSE",  "WH_MSSQL_MIGRATION")
SF_DB        = os.getenv("SNOWFLAKE_DATABASE",   "MSSQL_MIGRATION_LAB")
SF_SCHEMA    = "AIRBYTE_RAW"   # Airbyte writes here — separate from DMS Bronze


# ── API helpers ───────────────────────────────────────────────────────────────

class AirbyteAPI:
    def __init__(self, base_url: str, user: str, password: str):
        self.base = base_url.rstrip("/") + "/api/v1"
        self.auth = (user, password)
        self.headers = {"Content-Type": "application/json"}

    def _post(self, path: str, payload: dict) -> dict:
        resp = requests.post(
            f"{self.base}{path}",
            json=payload,
            headers=self.headers,
            auth=self.auth,
            timeout=30,
        )
        if not resp.ok:
            print(f"  ERROR {resp.status_code}: {resp.text[:300]}")
            resp.raise_for_status()
        return resp.json()

    def _get(self, path: str) -> dict:
        resp = requests.get(
            f"{self.base}{path}",
            headers=self.headers,
            auth=self.auth,
            timeout=30,
        )
        resp.raise_for_status()
        return resp.json()

    def get_workspace_id(self) -> str:
        data = self._post("/workspaces/list", {})
        return data["workspaces"][0]["workspaceId"]

    def list_source_definitions(self) -> list:
        return self._post("/source_definitions/list", {}).get("sourceDefinitions", [])

    def list_destination_definitions(self) -> list:
        return self._post("/destination_definitions/list", {}).get("destinationDefinitions", [])

    def find_definition_id(self, definitions: list, name_fragment: str) -> str:
        for d in definitions:
            if name_fragment.lower() in d.get("name", "").lower():
                return d["sourceDefinitionId"] if "sourceDefinitionId" in d else d["destinationDefinitionId"]
        raise ValueError(f"No connector found matching: {name_fragment}")

    def create_source(self, workspace_id: str, name: str, definition_id: str, config: dict) -> str:
        data = self._post("/sources/create", {
            "workspaceId": workspace_id,
            "name": name,
            "sourceDefinitionId": definition_id,
            "connectionConfiguration": config,
        })
        return data["sourceId"]

    def create_destination(self, workspace_id: str, name: str, definition_id: str, config: dict) -> str:
        data = self._post("/destinations/create", {
            "workspaceId": workspace_id,
            "name": name,
            "destinationDefinitionId": definition_id,
            "connectionConfiguration": config,
        })
        return data["destinationId"]

    def create_connection(self, source_id: str, dest_id: str, name: str) -> str:
        data = self._post("/connections/create", {
            "sourceId": source_id,
            "destinationId": dest_id,
            "name": name,
            "status": "active",
            "scheduleType": "manual",           # trigger manually or via Airflow
            "syncCatalog": {"streams": []},     # Airbyte discovers streams on first sync
            "nonBreakingChangesPreference": "ignore",
        })
        return data["connectionId"]

    def trigger_sync(self, connection_id: str) -> str:
        data = self._post("/connections/sync", {"connectionId": connection_id})
        return data["job"]["id"]

    def wait_for_job(self, job_id: str, timeout_s: int = 600) -> bool:
        """Poll until job completes. Returns True on success."""
        deadline = time.time() + timeout_s
        while time.time() < deadline:
            data = self._post("/jobs/get", {"id": job_id})
            status = data["job"]["status"]
            print(f"    Job {job_id}: {status}", end="\r")
            if status == "succeeded":
                print(f"    Job {job_id}: succeeded           ")
                return True
            if status in ("failed", "cancelled"):
                print(f"    Job {job_id}: {status}            ")
                return False
            time.sleep(10)
        print(f"    Job {job_id}: timed out after {timeout_s}s")
        return False


# ── Source / Destination configs ──────────────────────────────────────────────

def mssql_source_config() -> dict:
    """
    Microsoft SQL Server source connector config.
    Uses 'standard' replication (full-refresh on first run, incremental after).
    CDC requires SQL Server Agent + sysadmin perms — standard is simpler for a lab.
    """
    return {
        "host": MSSQL_HOST,
        "port": MSSQL_PORT,
        "database": MSSQL_DB,
        "username": MSSQL_USER,
        "password": MSSQL_PASS,
        "ssl_method": {"ssl_method": "unencrypted"},
        "replication_method": {
            "method": "CDC",   # use CDC if SQL Server Agent is running; else "STANDARD"
        },
        "schemas": ["dbo"],
    }


def snowflake_destination_config() -> dict:
    """
    Snowflake destination connector config.
    Airbyte writes to AIRBYTE_RAW schema — separate from DMS Bronze so you can compare both.
    """
    # Airbyte expects account in the format: <org>.<account> or just the locator
    # For accounts like "myorg-myaccount", use "myorg.myaccount"
    account_formatted = SF_ACCOUNT.replace("-", ".", 1) if "-" in SF_ACCOUNT else SF_ACCOUNT
    return {
        "host": f"{account_formatted}.snowflakecomputing.com",
        "role": SF_ROLE,
        "warehouse": SF_WH,
        "database": SF_DB,
        "schema": SF_SCHEMA,
        "username": SF_USER,
        "credentials": {
            "auth_type": "username_and_password",
            "password": SF_PASS,
        },
        "loading_method": {
            "method": "Standard",   # direct INSERT; use "S3 Staging" for production scale
        },
    }


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    print("=" * 60)
    print("Airbyte Connection Setup — SQL Server → Snowflake")
    print("=" * 60)

    if not all([SF_ACCOUNT, SF_USER, SF_PASS, MSSQL_PASS]):
        print("\nERROR: Missing required credentials.")
        print("Copy .env.example → .env and fill in MSSQL_PASSWORD, SNOWFLAKE_* vars.")
        sys.exit(1)

    api = AirbyteAPI(AIRBYTE_URL, AIRBYTE_USER, AIRBYTE_PASS)

    # Wait for Airbyte to be ready
    print("\n[1/5] Waiting for Airbyte to be ready...")
    for attempt in range(12):
        try:
            api._post("/workspaces/list", {})
            print("  Airbyte is up.")
            break
        except Exception:
            if attempt == 11:
                print("  Airbyte did not become ready in 2 minutes. Check: docker compose logs airbyte-server")
                sys.exit(1)
            print(f"  Waiting... ({attempt+1}/12)")
            time.sleep(10)

    print("\n[2/5] Getting workspace ID...")
    workspace_id = api.get_workspace_id()
    print(f"  Workspace: {workspace_id}")

    print("\n[3/5] Looking up connector IDs...")
    src_defs  = api.list_source_definitions()
    dest_defs = api.list_destination_definitions()

    mssql_def_id  = api.find_definition_id(src_defs,  "sql server")
    sf_def_id     = api.find_definition_id(dest_defs, "snowflake")
    print(f"  SQL Server connector : {mssql_def_id}")
    print(f"  Snowflake connector  : {sf_def_id}")

    print("\n[4/5] Creating source and destination...")
    source_id = api.create_source(
        workspace_id,
        name=f"MSSQL Lab — {MSSQL_HOST}/{MSSQL_DB}",
        definition_id=mssql_def_id,
        config=mssql_source_config(),
    )
    print(f"  Source created: {source_id}")

    dest_id = api.create_destination(
        workspace_id,
        name=f"Snowflake — {SF_DB}.{SF_SCHEMA}",
        definition_id=sf_def_id,
        config=snowflake_destination_config(),
    )
    print(f"  Destination created: {dest_id}")

    print("\n[5/5] Creating connection and triggering first sync...")
    conn_id = api.create_connection(
        source_id, dest_id,
        name="MSSQL Lab → Snowflake (Airbyte)",
    )
    print(f"  Connection created: {conn_id}")

    print("\n  Triggering initial full sync (this takes 2–5 minutes)...")
    job_id = api.trigger_sync(conn_id)
    success = api.wait_for_job(job_id, timeout_s=600)

    print("\n" + "=" * 60)
    if success:
        print("SUCCESS — data loaded into Snowflake schema:")
        print(f"  {SF_DB}.{SF_SCHEMA}.*")
        print("\nRun compare_dms_vs_airbyte.py to compare row counts with DMS Bronze.")
    else:
        print("SYNC FAILED — check Airbyte UI at http://localhost:8000")
        print("Common issues:")
        print("  - SQL Server not reachable from Docker (use host.docker.internal)")
        print("  - CDC not enabled on SQL Server (run sqlserver/sql/11_enable_cdc.sql)")
        print("  - Snowflake credentials wrong")

    print(f"\nAirbyte UI: {AIRBYTE_URL}")
    print(f"Connection ID (save this): {conn_id}")


if __name__ == "__main__":
    main()
