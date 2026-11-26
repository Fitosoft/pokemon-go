-- Public historical edition. Replace instance binding and private contract body with generic initialization.
-- For a new disposable database only; never replay over an existing deployment.
create table pogo_meta.technical_contracts (
 version text primary key check(version ~ '^[0-9]+\.[0-9]+\.[0-9]+$'),
 schema_version text not null,
 body text not null,
 published_at timestamptz not null default now()
);
create table pogo_meta.system_state (
 singleton boolean primary key default true check(singleton),
 project_ref text not null check(btrim(project_ref)<>''),
 schema_version text not null,
 contract_version text not null references pogo_meta.technical_contracts(version),
 readiness text not null check(readiness in ('building','pilot','released','maintenance')),
 updated_at timestamptz not null default now()
);
alter table pogo_meta.technical_contracts enable row level security;
alter table pogo_meta.system_state enable row level security;
revoke all on pogo_meta.technical_contracts,pogo_meta.system_state from public,anon,authenticated,service_role;

-- Initialize with a local project reference, not a deployed project ID.
insert into pogo_meta.technical_contracts(version,schema_version,body) values ('0.2.1','0.1.0','Initial metadata contract; building only.');
insert into pogo_meta.system_state(project_ref,schema_version,contract_version,readiness) values ('replace-with-your-project-ref','0.1.0','0.2.1','building');
