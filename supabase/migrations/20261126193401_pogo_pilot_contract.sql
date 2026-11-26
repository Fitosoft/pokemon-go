-- Public historical edition. Omit backlog and instance-specific pilot authorization; keep building.
-- For a new disposable database only; never replay over an existing deployment.
insert into pogo_meta.technical_contracts(version,schema_version,body) values ('0.3.1','0.2.1','Write guards installed; pilot requires local approval.');
update pogo_meta.system_state set schema_version='0.2.1',contract_version='0.3.1',updated_at=now() where singleton;
