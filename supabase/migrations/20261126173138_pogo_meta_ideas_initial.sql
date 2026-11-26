-- Public historical edition. Omit project backlog seed data.
-- For a new disposable database only; never replay over an existing deployment.
create schema pogo_meta;
revoke all on schema pogo_meta from public, anon, authenticated, service_role;
create table pogo_meta.ideas (
 code text primary key,
 title text not null,
 description text not null,
 status text not null default 'idea' check(status in ('idea','planned','implemented','rejected')),
 created_at timestamptz not null default now()
);
alter table pogo_meta.ideas enable row level security;
revoke all on table pogo_meta.ideas from public, anon, authenticated, service_role;
