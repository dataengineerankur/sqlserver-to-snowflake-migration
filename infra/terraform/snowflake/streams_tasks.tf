locals {
  stream_task_files = [
    "${path.module}/../../../snowflake_ddl/streams_tasks/01_stressdb_streams.sql",
    "${path.module}/../../../snowflake_ddl/streams_tasks/02_erp_streams.sql",
    "${path.module}/../../../snowflake_ddl/streams_tasks/03_crm_streams.sql",
    "${path.module}/../../../snowflake_ddl/streams_tasks/04_inventory_streams.sql",
  ]
}

resource "snowflake_execute" "streams_and_tasks" {
  for_each = { for idx, f in local.stream_task_files : basename(f) => f }

  execute = file(each.value)
  revert  = ""

  depends_on = [
    snowflake_execute.stress_supporting_tables,
    snowflake_warehouse.migration,
  ]
}
