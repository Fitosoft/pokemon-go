-- Public historical edition. Omit private pilot observations, IDs, backlog and release authorization; keep building.
-- For a new disposable database only; never replay over an existing deployment.
insert into pogo_meta.technical_contracts(version,schema_version,body) values ('0.3.2','0.2.2','Reader role and inventory release contract; see docs/technical-contract.md. Local release requires validation.');
update pogo_meta.system_state set schema_version='0.2.2',contract_version='0.3.2',updated_at=now() where singleton;
