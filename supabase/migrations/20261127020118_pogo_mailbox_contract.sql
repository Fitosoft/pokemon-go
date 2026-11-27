-- Public edition: no private contract content or backlog data.
insert into pogo_meta.technical_contracts(version,schema_version,body) values ('0.5.0','0.4.0','Mailbox API; see docs/mailbox.md. Local validation and authorization required.');
update pogo_meta.system_state set schema_version='0.4.0',contract_version='0.5.0',updated_at=now() where singleton and schema_version='0.3.0' and contract_version='0.4.0';
