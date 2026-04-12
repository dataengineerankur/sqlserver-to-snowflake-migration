#!/usr/bin/env bash
# Run validation SQL and inspect_counts; write results under 14_reports/.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DOCKER_DIR="${LAB_ROOT}/11_docker"
REPORTS_DIR="${LAB_ROOT}/14_reports"
SQL_DIR="${LAB_ROOT}/sql"

ENV_FILE="${DOCKER_DIR}/.env"
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: Missing ${ENV_FILE}. Copy 11_docker/.env.example to 11_docker/.env"
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

: "${MSSQL_PORT:=1433}"
: "${MSSQL_USER:=sa}"
: "${MSSQL_DB:=SnowConvertStressDB}"
: "${MSSQL_SA_PASSWORD:?MSSQL_SA_PASSWORD must be set in .env}"

# shellcheck source=lab_sqlcmd.sh
source "${SCRIPT_DIR}/lab_sqlcmd.sh"
export LAB_ROOT

to_work() {
  local abs="$1"
  printf '/work/%s\n' "${abs#"${LAB_ROOT}/"}"
}

mkdir -p "${REPORTS_DIR}"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT_TXT="${REPORTS_DIR}/validation_${STAMP}.txt"
OUT_CSV="${REPORTS_DIR}/validation_rowcounts_${STAMP}.csv"
INSPECT_TXT="${REPORTS_DIR}/inspect_counts_${STAMP}.txt"
INSPECT_CSV="${REPORTS_DIR}/inspect_counts_${STAMP}.csv"

echo "=== Running sql/10_validation.sql -> ${OUT_TXT}"
lab_sqlcmd -d "${MSSQL_DB}" -b -i "$(to_work "${SQL_DIR}/10_validation.sql")" -o "$(to_work "${OUT_TXT}")"

echo "=== Row counts (CSV) -> ${OUT_CSV}"
lab_sqlcmd -d "${MSSQL_DB}" -b -Q "SET NOCOUNT ON;
SELECT 'Categories' AS TableName, COUNT(*) AS RowCnt FROM dbo.Categories
UNION ALL SELECT 'Customers', COUNT(*) FROM dbo.Customers
UNION ALL SELECT 'Products', COUNT(*) FROM dbo.Products
UNION ALL SELECT 'Orders', COUNT(*) FROM dbo.Orders
UNION ALL SELECT 'OrderItems', COUNT(*) FROM dbo.OrderItems;" \
  -s"," -W -h-1 -w 65535 -o "$(to_work "${OUT_CSV}")"

echo "=== Running 12_cli/inspect_counts.sql -> ${INSPECT_TXT}"
lab_sqlcmd -d "${MSSQL_DB}" -b -i "$(to_work "${SCRIPT_DIR}/inspect_counts.sql")" -o "$(to_work "${INSPECT_TXT}")"

echo "=== Object + row summary (CSV) -> ${INSPECT_CSV}"
lab_sqlcmd -d "${MSSQL_DB}" -b -Q "SET NOCOUNT ON;
SELECT 'TABLES' AS Kind, CAST(COUNT(*) AS VARCHAR(20)) AS Cnt FROM sys.tables WHERE is_ms_shipped=0
UNION ALL SELECT 'VIEWS', CAST(COUNT(*) AS VARCHAR(20)) FROM sys.views WHERE is_ms_shipped=0
UNION ALL SELECT 'PROCEDURES', CAST(COUNT(*) AS VARCHAR(20)) FROM sys.procedures WHERE is_ms_shipped=0
UNION ALL SELECT 'FUNCTIONS', CAST(COUNT(*) AS VARCHAR(20)) FROM sys.objects WHERE type IN ('FN','IF','TF') AND is_ms_shipped=0
UNION ALL SELECT 'ROWS_Categories', CAST(COUNT_BIG(*) AS VARCHAR(20)) FROM dbo.Categories
UNION ALL SELECT 'ROWS_Customers', CAST(COUNT_BIG(*) AS VARCHAR(20)) FROM dbo.Customers
UNION ALL SELECT 'ROWS_Products', CAST(COUNT_BIG(*) AS VARCHAR(20)) FROM dbo.Products
UNION ALL SELECT 'ROWS_Orders', CAST(COUNT_BIG(*) AS VARCHAR(20)) FROM dbo.Orders
UNION ALL SELECT 'ROWS_OrderItems', CAST(COUNT_BIG(*) AS VARCHAR(20)) FROM dbo.OrderItems;" \
  -s"," -W -h-1 -w 65535 -o "$(to_work "${INSPECT_CSV}")"

echo "Validation complete. Artifacts:"
echo "  ${OUT_TXT}"
echo "  ${OUT_CSV}"
echo "  ${INSPECT_TXT}"
echo "  ${INSPECT_CSV}"
