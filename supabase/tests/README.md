# SQL tests

These are reconstructed, reusable versions of the checks performed during development. The original deployed checks passed, but these consolidated public files have not yet been executed against a fresh public reconstruction.

Run with PostgreSQL 17 psql against a disposable Supabase-compatible database initialized with ../schema.sql. Do not run inventory_integrity.sql against a real inventory. Use explicit host, database and user to avoid accidentally targeting production.

- inventory_integrity.sql: readiness, controlled insert/update, retry, duplicate import, stale version, invalid IV, evidence rollback, conflicting observation, direct write rejection and audit consistency.
- reader_permissions.sql: effective SELECT, DML, schema creation and function privileges for the mobile reader. This is not a network login test or a complete database security audit.

True concurrent multi-session tests remain deferred. The PG_CONTEXT guard is not a security boundary and must be retested after PostgreSQL upgrades.
