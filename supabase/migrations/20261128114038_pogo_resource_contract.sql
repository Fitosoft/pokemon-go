-- Public edition: omit deployment-specific contract and backlog content.
insert into pogo_meta.technical_contracts(version,schema_version,body) values ('0.6.0','0.5.0','Resource ledger API; see docs/resources.md. Local validation and authorization required.');
update pogo_meta.system_state set schema_version='0.5.0',contract_version='0.6.0',updated_at=now() where singleton and schema_version='0.4.0' and contract_version='0.5.0';
