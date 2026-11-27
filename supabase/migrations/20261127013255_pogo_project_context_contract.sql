-- Public historical edition: no instance-specific contract or release decision.
insert into pogo_meta.technical_contracts(version,schema_version,body)
values ('0.4.0','0.3.0','Versioned project organization and context API. See docs/project-context.md. Configure all nine required keys and local chat roles before initialization. Validate and authorize locally before enabling writes.');
update pogo_meta.system_state set schema_version='0.3.0',contract_version='0.4.0',updated_at=now() where singleton and schema_version='0.2.2' and contract_version='0.3.2';
