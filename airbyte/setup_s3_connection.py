#!/usr/bin/env python3
"""
setup_s3_connection.py
======================
Bootstraps an Airbyte workspace with:
  - Source:      Microsoft SQL Server  (local Docker, reachable via host.docker.internal)
  - Destination: S3                    (writes Parquet to your DMS bucket prefix)
  - Connection:  Full refresh on first run

This lets you replace AWS DMS entirely for local dev. Once Parquet files land in S3,
your existing Snowpipe picks them up automatically — same as the DMS path.

Run ONCE after `docker compose up -d` finishes:
    python setup_s3_connection.py

Reads credentials from environment or a .env file at the repo root.
Never hardcode credentials in this file.

Requirements:
    pip install requests python-dotenv
"""

import os
import sys
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

MSSQL_HOST   = os.getenv("MSSQL_HOST",     "host.docker.internal")
MSSQL_PORT   = int(os.getenv("MSSQL_PORT", "1433"))
MSSQL_USER   = os.getenv("MSSQL_USER",     "sa")
MSSQL_PASS   = os.getenv("MSSQL_PASSWORD", "")
MSSQL_DB     = os.getenv("MSSQL_DB",       "SnowConvertStressDB")

AWS_REGION         = os.getenv("AWS_REGION",         "us-east-1")
AWS_ACCESS_KEY_ID  = os.getenv("AWS_ACCESS_KEY_ID",  "")
AWS_SECRET_KEY     = os.getenv("AWS_SECRET_ACCESS_KEY", "")
S3_BUCKET          = os.getenv("DMS_BUCKET",         "")   # reuse your DMS bucket
S3_PATH_PREFIX     = "airbyte-raw"                         # lands under s3://<bucket>/airbyte-raw/


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
            print(f"  ERROR {resp.status_code}: {resp.text[:400]}")
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
                return d.get("sourceDefinitionId") or d.get("destinationDefinitionId")
        raise ValueError(f"No connector found matching: {name_fragment!r}")

    def create_source(self, workspace_id: str, name: str, def_id: str, config: dict) -> str:
        data = self._post("/sources/create", {
            "workspaceId": workspace_id,
            "name": name,
            "sourceDefinitionId": def_id,
            "connectionConfiguration": config,
        })
        return data["sourceId"]

    def create_destination(self, workspace_id: str, name: str, def_id: str, config: dict) -> str:
        data = self._post("/destinations/create", {
            "workspaceId": workspace_id,
            "name": name,
            "destinationDefinitionId": def_id,
            "connectionConfiguration": config,
        })
        return data["destinationId"]

    def create_connection(self, source_id: str, dest_id: str, name: str) -> str:
        data = self._post("/connections/create", {
            "sourceId": source_id,
            "destinationId": dest_id,
            "name": name,
            "status": "active",
            "scheduleType": "manual",
            "syncCatalog": {"streams": []},
            "nonBreakingChangesPreference": "ignore",
        })
        return data["connectionId"]

    def trigger_sync(self, connection_id: str) -> str:
        data = self._post("/connections/sync", {"connectionId": connection_id})
        return data["job"]["id"]

    def wait_for_job(self, job_id: str, timeout_s: int = 600) -> bool:
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


# ── Connector configs ─────────────────────────────────────────────────────────

def mssql_source_config() -> dict:
    """
    SQL Server source using STANDARD replication (full-refresh).
    CDC requires SQL Server Agent + sysadmin; STANDARD works with just sa access.
    Switch method to "CDC" if you have Agent running.
    """
    return {
        "host": MSSQL_HOST,
        "port": MSSQL_PORT,
        "database": MSSQL_DB,
        "username": MSSQL_USER,
        "password": MSSQL_PASS,
        "ssl_method": {"ssl_method": "unencrypted"},
        "replication_method": {"method": "STANDARD"},
        "schemas": ["dbo"],
    }


def s3_destination_config() -> dict:
    """
    S3 destination writes Parquet files under s3://<bucket>/airbyte-raw/<table>/*.parquet
    Snowpipe can ingest these if you point it at the airbyte-raw/ prefix.

    Format options: "Parquet", "CSV", "JSONL"
    Parquet is preferred — smaller files, schema preserved, Snowpipe handles it natively.
    """
    return {
        "s3_bucket_name": S3_BUCKET,
        "s3_bucket_path": S3_PATH_PREFIX,
        "s3_bucket_region": AWS_REGION,
        "access_key_id": AWS_ACCESS_KEY_ID,
        "secret_access_key": AWS_SECRET_KEY,
        "format": {
            "format_type": "Parquet",
            "compression_codec": "SNAPPY",
        },
    }


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    print("=" * 65)
    print("Airbyte Setup — SQL Server (local) → S3")
    print(f"  Source : {MSSQL_HOST}:{MSSQL_PORT}/{MSSQL_DB}")
    print(f"  Dest   : s3://{S3_BUCKET}/{S3_PATH_PREFIX}/")
    print("=" * 65)

    missing = [v for v, k in [
        (MSSQL_PASS, "MSSQL_PASSWORD"),
        (AWS_ACCESS_KEY_ID, "AWS_ACCESS_KEY_ID"),
        (AWS_SECRET_KEY, "AWS_SECRET_ACCESS_KEY"),
        (S3_BUCKET, "DMS_BUCKET"),
    ] if not v]
    if missing:
        print(f"\nERROR: Missing required env vars: {missing}")
        print("Copy .env.example → .env and fill in the missing values.")
        sys.exit(1)

    api = AirbyteAPI(AIRBYTE_URL, AIRBYTE_USER, AIRBYTE_PASS)

    print("\n[1/5] Waiting for Airbyte...")
    for attempt in range(12):
        try:
            api._post("/workspaces/list", {})
            print("  Airbyte is up.")
            break
        except Exception:
            if attempt == 11:
                print("  Timed out. Check: docker compose logs airbyte-server")
                sys.exit(1)
            print(f"  Waiting... ({attempt + 1}/12)")
            time.sleep(10)

    print("\n[2/5] Workspace ID...")
    workspace_id = api.get_workspace_id()
    print(f"  {workspace_id}")

    print("\n[3/5] Connector IDs...")
    src_defs  = api.list_source_definitions()
    dest_defs = api.list_destination_definitions()
    mssql_def_id = api.find_definition_id(src_defs,  "sql server")
    s3_def_id    = api.find_definition_id(dest_defs, "s3")
    print(f"  SQL Server : {mssql_def_id}")
    print(f"  S3         : {s3_def_id}")

    print("\n[4/5] Creating source and destination...")
    source_id = api.create_source(
        workspace_id,
        name=f"MSSQL Local — {MSSQL_HOST}/{MSSQL_DB}",
        def_id=mssql_def_id,
        config=mssql_source_config(),
    )
    print(f"  Source created: {source_id}")

    dest_id = api.create_destination(
        workspace_id,
        name=f"S3 — {S3_BUCKET}/{S3_PATH_PREFIX}",
        def_id=s3_def_id,
        config=s3_destination_config(),
    )
    print(f"  Destination created: {dest_id}")

    print("\n[5/5] Creating connection and triggering sync...")
    conn_id = api.create_connection(
        source_id, dest_id,
        name="MSSQL Local → S3 (Airbyte)",
    )
    print(f"  Connection: {conn_id}")

    print("\n  Syncing (2–5 min for ~5k rows)...")
    job_id = api.trigger_sync(conn_id)
    success = api.wait_for_job(job_id, timeout_s=600)

    print("\n" + "=" * 65)
    if success:
        print("SUCCESS — Parquet files landed at:")
        print(f"  s3://{S3_BUCKET}/{S3_PATH_PREFIX}/<table>/*.parquet")
        print()
        print("Next steps:")
        print("  1. Verify files in S3 console under the airbyte-raw/ prefix")
        print("  2. If you want Snowpipe to pick them up, create a pipe pointing")
        print("     at s3://<bucket>/airbyte-raw/ or copy files into your DMS prefix")
        print("  3. Or just query the Parquet files directly with an external stage:")
        print("     SELECT $1 FROM @MSSQL_MIGRATION_LAB.RAW_MSSQL.STAGE_DMS_S3")
        print("     (FILES => ('airbyte-raw/dbo_CUSTOMERS/*.parquet'))")
    else:
        print("SYNC FAILED — check Airbyte UI at http://localhost:8000")
        print()
        print("Common issues:")
        print("  - SQL Server not reachable: is Docker running? try pinging host.docker.internal")
        print("  - S3 access denied: check AWS_ACCESS_KEY_ID has s3:PutObject on your bucket")
        print("  - Wrong S3 region: DMS_BUCKET region must match AWS_REGION in .env")

    print(f"\nAirbyte UI  : {AIRBYTE_URL}")
    print(f"Connection ID: {conn_id}")


if __name__ == "__main__":
    main()
