#!/usr/bin/env bash
# End-to-end SQL Server migration lab: Docker + sqlcmd deploy + validation reports.
# Run from repo root:
#   bash sqlserver_migration_test/12_cli/run_lab.sh
# Or from this folder:
#   bash ./run_lab.sh
#
# Uses classic sqlcmd inside mcr.microsoft.com/mssql-tools (see lab_sqlcmd.sh) so
# Apple Silicon + Azure SQL Edge + Homebrew go-sqlcmd cert issues do not break the lab.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DOCKER_DIR="${LAB_ROOT}/11_docker"
REPORTS_DIR="${LAB_ROOT}/14_reports"
SQL_DIR="${LAB_ROOT}/sql"

MAIN_LOG="${REPORTS_DIR}/run_lab_$(date +%Y%m%d_%H%M%S).log"

mkdir -p "${REPORTS_DIR}"

exec > >(tee -a "${MAIN_LOG}") 2>&1

echo "=============================================="
echo "SnowConvert SQL Server lab — run_lab.sh"
echo "LAB_ROOT=${LAB_ROOT}"
echo "Log file: ${MAIN_LOG}"
echo "=============================================="

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: Docker is not installed or not on PATH."
  exit 1
fi
echo "[1/7] Docker CLI: OK ($(command -v docker))"

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Docker daemon is not running. Start Docker Desktop."
  exit 1
fi
echo "[2/7] Docker daemon: OK"

ENV_FILE="${DOCKER_DIR}/.env"
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: Missing ${ENV_FILE}"
  echo "  Copy: cp ${DOCKER_DIR}/.env.example ${DOCKER_DIR}/.env"
  echo "  Edit MSSQL_SA_PASSWORD to meet SQL Server complexity rules."
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

echo "[3/7] SQL execution: classic sqlcmd via Docker (mcr.microsoft.com/mssql-tools) → host.docker.internal:${MSSQL_PORT}"

COMPOSE_FILE="${DOCKER_DIR}/docker-compose.yml"
echo "[4/7] Starting SQL Server (docker compose)..."
docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" up -d

echo "[5/7] Waiting for SQL Server readiness..."
if ! bash "${SCRIPT_DIR}/check_ready.sh"; then
  echo "ERROR: SQL Server did not become ready."
  exit 1
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

echo "[6/7] Applying SQL scripts (strict order)..."
run_sql_file "01_create_database" "${SQL_DIR}/01_create_database.sql" 1
run_sql_file "01a_additional_lab_databases" "${SQL_DIR}/01a_create_additional_lab_databases.sql" 1

for f in \
  "${SQL_DIR}/02_tables.sql" \
  "${SQL_DIR}/03_seed.sql" \
  "${SQL_DIR}/04_views.sql" \
  "${SQL_DIR}/05_functions.sql" \
  "${SQL_DIR}/06_procedures.sql" \
  "${SQL_DIR}/07_stress_ddl.sql" \
  "${SQL_DIR}/08_stress_procedures.sql" \
  "${SQL_DIR}/09_stress_triggers.sql"; do
  if [[ ! -f "${f}" ]]; then
    echo "ERROR: Missing required script ${f}"
    exit 1
  fi
  run_sql_file "$(basename "${f}")" "${f}" 0
done

for f in \
  "${SQL_DIR}/20_lab_erp.sql" \
  "${SQL_DIR}/21_lab_crm.sql" \
  "${SQL_DIR}/22_lab_inventory.sql"; do
  run_sql_file "$(basename "${f}")" "${f}" 1
done

echo "[7/7] Validation + inspect reports..."
bash "${SCRIPT_DIR}/run_validation.sh"

echo "=============================================="
echo "FINAL SUMMARY"
echo "=============================================="
echo "Database: ${MSSQL_DB}"
echo ""

SUMMARY_FILE="${REPORTS_DIR}/_run_lab_summary_$$.sql"
trap 'rm -f "${SUMMARY_FILE}"' EXIT
cat > "${SUMMARY_FILE}" <<'EOS'
SET NOCOUNT ON;
USE SnowConvertStressDB;
SELECT 'tables' AS metric, CAST(COUNT(*) AS VARCHAR(20)) AS value
FROM sys.tables WHERE is_ms_shipped = 0
UNION ALL SELECT 'views', CAST(COUNT(*) AS VARCHAR(20)) FROM sys.views WHERE is_ms_shipped = 0
UNION ALL SELECT 'procedures', CAST(COUNT(*) AS VARCHAR(20)) FROM sys.procedures WHERE is_ms_shipped = 0
UNION ALL SELECT 'functions', CAST(COUNT(*) AS VARCHAR(20))
FROM sys.objects WHERE type IN ('FN','IF','TF') AND is_ms_shipped = 0
UNION ALL SELECT 'rows_Categories', CAST(COUNT_BIG(*) AS VARCHAR(20)) FROM dbo.Categories
UNION ALL SELECT 'rows_Customers', CAST(COUNT_BIG(*) AS VARCHAR(20)) FROM dbo.Customers
UNION ALL SELECT 'rows_Products', CAST(COUNT_BIG(*) AS VARCHAR(20)) FROM dbo.Products
UNION ALL SELECT 'rows_Orders', CAST(COUNT_BIG(*) AS VARCHAR(20)) FROM dbo.Orders
UNION ALL SELECT 'rows_OrderItems', CAST(COUNT_BIG(*) AS VARCHAR(20)) FROM dbo.OrderItems;
EOS

lab_sqlcmd -d "${MSSQL_DB}" -b -i "$(to_work "${SUMMARY_FILE}")" -W -s"|" -h-1

echo ""
echo "Reports directory: ${REPORTS_DIR}"
echo "Connect in VS Code: see sqlserver_migration_test/13_vscode/README_VSCODE.md"
echo "Done."
