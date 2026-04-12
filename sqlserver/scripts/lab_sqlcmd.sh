#!/usr/bin/env bash
# Run Microsoft's classic sqlcmd inside Docker so Mac/Homebrew go-sqlcmd TLS issues
# (e.g. x509 negative serial against Azure SQL Edge) do not break the lab.
# Requires: Docker, mcr.microsoft.com/mssql-tools:latest (pulled on first use).
# Repository root is mounted at /work so -i/-o paths use /work/...
#
# Connection strategy:
# 1) If the lab SQL container is running (snowconvert-sqlserver-lab), run mssql-tools with
#    `--network container:snowconvert-sqlserver-lab` and `-S 127.0.0.1,1433` (same network
#    namespace as the engine — most reliable on Docker Desktop / Colima / Linux).
# 2) Else: same Compose network as the SQL container + `sqlserver,1433` (Compose DNS).
# 3) Else: host.docker.internal + MSSQL_PORT (SQL published on the host only).
# Override: SQLCMD_SERVER=host,port

lab_sqlcmd() {
  local lab_root="${LAB_ROOT:?Set LAB_ROOT to sqlserver_migration_test directory}"
  : "${MSSQL_PORT:=1433}"
  : "${MSSQL_USER:=sa}"
  : "${MSSQL_SA_PASSWORD:?MSSQL_SA_PASSWORD must be set}"

  local sql_target
  local -a net_args=()
  local internal_port=1433

  if [[ -n "${SQLCMD_SERVER:-}" ]]; then
    sql_target="${SQLCMD_SERVER}"
  elif docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'snowconvert-sqlserver-lab'; then
    # Share SQL Server container's network — connect to loopback inside that namespace.
    net_args=(--network "container:snowconvert-sqlserver-lab")
    sql_target="127.0.0.1,${internal_port}"
  else
    sql_target="host.docker.internal,${MSSQL_PORT}"
    net_args=(--add-host=host.docker.internal:host-gateway)
  fi

  docker run --rm \
    --platform linux/amd64 \
    "${net_args[@]}" \
    -e "SQLCMDPASSWORD=${MSSQL_SA_PASSWORD}" \
    -v "${lab_root}:/work" \
    mcr.microsoft.com/mssql-tools:latest \
    /opt/mssql-tools/bin/sqlcmd \
    -S "${sql_target}" \
    -U "${MSSQL_USER}" \
    -C \
    -I \
    "$@"
}
