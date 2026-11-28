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
\ir migrations/20261127013156_pogo_project_context.sql
\ir migrations/20261127013255_pogo_project_context_contract.sql
\ir migrations/20261127020047_pogo_chat_mailbox.sql
\ir migrations/20261127020100_pogo_mailbox_context.sql
\ir migrations/20261127020118_pogo_mailbox_contract.sql
\ir migrations/20261128113942_pogo_resource_ledger.sql
\ir migrations/20261128114022_pogo_resource_context.sql
\ir migrations/20261128114038_pogo_resource_contract.sql
\ir migrations/20261128114418_pogo_resource_catalog_delegation.sql
\ir migrations/20261128114431_pogo_resource_catalog_delegation_contract.sql
COMMIT;
