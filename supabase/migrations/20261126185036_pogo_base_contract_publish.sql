-- Public historical edition. Replace instance-specific contract text.
-- For a new disposable database only; never replay over an existing deployment.
insert into pogo_meta.technical_contracts(version,schema_version,body) values ('0.3.0','0.2.0','Inventory base schema and controlled writes; see docs/technical-contract.md.');
update pogo_meta.system_state set schema_version='0.2.0',contract_version='0.3.0',updated_at=now() where singleton;
