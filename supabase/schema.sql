-- Public schema reconstruction (psql, fresh Supabase-compatible database).
-- Contains no production rows. See migrations/README.md.
\set ON_ERROR_STOP on
BEGIN;
\ir migrations/20261126150926_pogo_poc_initial.sql
\ir migrations/20261126161055_pogo_poc_restore_test.sql
\ir migrations/20261126173138_pogo_meta_ideas_initial.sql
\ir migrations/20261126183542_pogo_meta_contract_initial.sql
\ir migrations/20261126184933_pogo_base_tables.sql
\ir migrations/20261126184956_pogo_controlled_write_functions.sql
\ir migrations/20261126185036_pogo_base_contract_publish.sql
\ir migrations/20261126193330_pogo_guard_write_context.sql
\ir migrations/20261126193401_pogo_pilot_contract.sql
\ir migrations/20261126213352_pogo_mobile_reader.sql
\ir migrations/20261126213416_pogo_pilot_release_and_backlog.sql
COMMIT;
