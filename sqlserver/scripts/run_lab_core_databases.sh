#!/usr/bin/env bash
# Apply only: 01 (master), 01a (master), 20–22 (lab DBs; scripts contain USE Lab*).
# Same Docker/sqlcmd setup as run_lab.sh but skips stress + validation.
#
#   bash sqlserver_migration_test/12_cli/run_lab_core_databases.sh
#
# Optional: SKIP_DOCKER_UP=1 if SQL Server is already running and reachable on MSSQL_HOST:MSSQL_PORT.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DOCKER_DIR="${LAB_ROOT}/11_docker"
REPORTS_DIR="${LAB_ROOT}/14_reports"
SQL_DIR="${LAB_ROOT}/sql"

mkdir -p "${REPORTS_DIR}"

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: Docker is not installed or not on PATH."
  exit 1
fi

ENV_FILE="${DOCKER_DIR}/.env"
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: Missing ${ENV_FILE}"
  echo "  Copy: cp ${DOCKER_DIR}/.env.example ${DOCKER_DIR}/.env"
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

: "${MSSQL_HOST:=localhost}"
: "${MSSQL_PORT:=1433}"
: "${MSSQL_USER:=sa}"
: "${MSSQL_DB:=SnowConvertStressDB}"
: "${MSSQL_SA_PASSWORD:?MSSQL_SA_PASSWORD must be set in 11_docker/.env}"

# shellcheck source=lab_sqlcmd.sh
source "${SCRIPT_DIR}/lab_sqlcmd.sh"
export LAB_ROOT

if [[ "${SKIP_DOCKER_UP:-0}" != "1" ]]; then
  if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker daemon is not running. Start Docker Desktop or set SKIP_DOCKER_UP=1."
    exit 1
  fi
  COMPOSE_FILE="${DOCKER_DIR}/docker-compose.yml"
  docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" up -d
  if ! bash "${SCRIPT_DIR}/check_ready.sh"; then
    echo "ERROR: SQL Server did not become ready."
    exit 1
  fi
fi

to_work() {
  local abs="$1"
  printf '/work/%s\n' "${abs#"${LAB_ROOT}/"}"
}

run_sql_file() {
  local label="$1"
  local path="$2"
  local use_master="${3:-0}"
  local logfile="${REPORTS_DIR}/sql_$(basename "${path}" .sql)_$(date +%Y%m%d_%H%M%S).log"
  echo "----------------------------------------------"
  echo "Executing: ${label} (${path})"
  if [[ "${use_master}" == "1" ]]; then
    lab_sqlcmd -d master -b -i "$(to_work "${path}")" -o "$(to_work "${logfile}")"
  else
    lab_sqlcmd -d "${MSSQL_DB}" -b -i "$(to_work "${path}")" -o "$(to_work "${logfile}")"
  fi
  local ec=$?
  if [[ ${ec} -ne 0 ]]; then
    echo "ERROR: sqlcmd failed (exit ${ec}) for ${path}. See ${logfile}"
    exit "${ec}"
  fi
  echo "OK — log: ${logfile}"
}

echo "Applying core lab databases (01, 01a, 20, 21, 22)..."
run_sql_file "01_create_database" "${SQL_DIR}/01_create_database.sql" 1
run_sql_file "01a_create_additional_lab_databases" "${SQL_DIR}/01a_create_additional_lab_databases.sql" 1
# Use master for login: scripts contain USE Lab*; avoids failure if MSSQL_DB points at a missing DB.
run_sql_file "20_lab_erp" "${SQL_DIR}/20_lab_erp.sql" 1
run_sql_file "21_lab_crm" "${SQL_DIR}/21_lab_crm.sql" 1
run_sql_file "22_lab_inventory" "${SQL_DIR}/22_lab_inventory.sql" 1
echo "Done. Databases: SnowConvertStressDB, LabERP_DB, LabCRM_DB, LabInventory_DB (20–22 objects in Lab* DBs)."
