-- Public edition: omit deployment-specific contract content.
insert into pogo_meta.technical_contracts(version,schema_version,body) values ('0.6.1','0.5.1','Limited resource catalog delegation; see docs/resources.md. Local validation and authorization required.');
update pogo_meta.system_state set schema_version='0.5.1',contract_version='0.6.1',updated_at=now() where singleton and schema_version='0.5.0' and contract_version='0.6.0';
