# SCT Assessment Report — SQL Server → Snowflake
Generated: 2026-04-12 | Source: SQL Server 2019 Express | Target: Snowflake

## Summary
| Category | Count | Auto-converted | Needs review |
|----------|-------|----------------|--------------|
| Tables | 22 | 22 | 0 |
| Computed columns | 3 | 3 (materialized at load) | 0 |
| Identity columns | 18 | 18 (AUTOINCREMENT) | 0 |
| Foreign keys | 10 | documented only (not enforced) | 0 |
| Check constraints | 1 | documented only (not enforced) | 0 |
| ROWVERSION columns | 1 | BINARY(8) — flagged, low value | 1 |
| Procedures/Triggers | 12 | 0 — **manual rewrite required** | 12 |

## Databases Covered
- `SnowConvertStressDB` → schemas: BRONZE.STRESS, SILVER.STRESS, GOLD
- `LabERP_DB`           → schemas: BRONZE.ERP,    SILVER.ERP
- `LabCRM_DB`           → schemas: BRONZE.CRM,    SILVER.CRM
- `LabInventory_DB`     → schemas: BRONZE.INV,    SILVER.INV

## Key Decisions
1. **No IDENTITY enforcement in Snowflake** — surrogate keys use AUTOINCREMENT but
   values are not guaranteed sequential after CDC merges. Silver layer adds proper SK.
2. **Computed columns** (LineTotal, NetPay) — stored as regular NUMBER columns in Bronze,
   recomputed in Silver via transformation.
3. **ROWVERSION** (Employees.RowVer) — kept as BINARY(8) in Bronze, dropped in Silver.
4. **NVARCHAR(MAX)** → VARCHAR (Snowflake VARCHAR = 16MB, no explicit MAX needed).
5. **Foreign keys** — documented as comments in DDL, not enforced. Snowflake uses them
   as hints for query optimization only when manually declared as NOT ENFORCED.
