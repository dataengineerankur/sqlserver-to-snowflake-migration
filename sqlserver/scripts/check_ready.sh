#!/usr/bin/env bash
# Repeatedly verify SQL Server accepts connections (host sqlcmd or docker exec fallback).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DOCKER_DIR="${LAB_ROOT}/11_docker"

ENV_FILE="${DOCKER_DIR}/.env"
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: Missing ${ENV_FILE}. Copy 11_docker/.env.example to 11_docker/.env"
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

: "${MSSQL_HOST:=localhost}"
: "${MSSQL_PORT:=1433}"
: "${MSSQL_USER:=sa}"
: "${MSSQL_SA_PASSWORD:?MSSQL_SA_PASSWORD must be set in .env}"

TIMEOUT_SEC="${CHECK_READY_TIMEOUT:-180}"
INTERVAL_SEC="${CHECK_READY_INTERVAL:-3}"

# shellcheck source=lab_sqlcmd.sh
source "${SCRIPT_DIR}/lab_sqlcmd.sh"
export LAB_ROOT

echo "check_ready: waiting for SQL Server (Docker lab container → same-network sqlserver:1433, else host.docker.internal:${MSSQL_PORT}; timeout ${TIMEOUT_SEC}s)..."

deadline=$((SECONDS + TIMEOUT_SEC))

sqlcmd_docker_ok() {
  lab_sqlcmd -d master -Q "SET NOCOUNT ON; SELECT 1;" -b -o /dev/null 2>/dev/null
}

while (( SECONDS < deadline )); do
  if sqlcmd_docker_ok; then
    echo "check_ready: OK — classic sqlcmd (Docker mssql-tools) connected to the server."
    exit 0
  fi
  echo "check_ready: not ready yet; retrying in ${INTERVAL_SEC}s..."
  sleep "${INTERVAL_SEC}"
done

echo "check_ready: TIMEOUT after ${TIMEOUT_SEC}s — SQL Server did not become ready."
echo "  Hint: docker compose -f ${DOCKER_DIR}/docker-compose.yml logs --tail 80 sqlserver"
exit 1
