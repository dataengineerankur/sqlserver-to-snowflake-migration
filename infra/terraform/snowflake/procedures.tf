locals {
  proc_files = [
    "${path.module}/../../../snowflake_ddl/procedures/01_basic_procs.sql",
    "${path.module}/../../../snowflake_ddl/procedures/02_stress_procs.sql",
    "${path.module}/../../../snowflake_ddl/procedures/03_erp_procs.sql",
    "${path.module}/../../../snowflake_ddl/procedures/04_crm_procs.sql",
    "${path.module}/../../../snowflake_ddl/procedures/05_inventory_procs.sql",
    "${path.module}/../../../snowflake_ddl/procedures/06_dml_guard_procs.sql",
  ]

  supporting_tables_sql = file("${path.module}/../../../snowflake_ddl/bronze/05_stress_supporting.sql")
}

resource "snowflake_execute" "stress_supporting_tables" {
  execute = local.supporting_tables_sql
  revert  = ""
}

resource "snowflake_execute" "stored_procedures" {
  for_each = { for idx, f in local.proc_files : basename(f) => f }

  execute  = file(each.value)
  revert   = ""

  depends_on = [snowflake_execute.stress_supporting_tables]
}
