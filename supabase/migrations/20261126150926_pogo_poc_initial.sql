-- Public historical edition. Original structural SQL; no production rows included.
-- For a new disposable database only; never replay over an existing deployment.
create schema pogo_poc;
revoke all on schema pogo_poc from public, anon, authenticated, service_role;
create table pogo_poc.pokemon (
 id uuid primary key default gen_random_uuid(),
 import_key text not null unique,
 pokedex_number integer not null check (pokedex_number > 0),
 name text not null,
 cp integer not null check (cp > 0),
 iv_attack smallint check (iv_attack between 0 and 15),
 iv_defense smallint check (iv_defense between 0 and 15),
 iv_stamina smallint check (iv_stamina between 0 and 15),
 is_shiny boolean,
 version integer not null default 1 check (version > 0),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 probe uuid not null default gen_random_uuid()
);
alter table pogo_poc.pokemon enable row level security;
revoke all on table pogo_poc.pokemon from public, anon, authenticated, service_role;
create function pogo_poc.touch_pokemon() returns trigger language plpgsql set search_path = '' as $$ begin new.version := old.version + 1; new.updated_at := clock_timestamp(); return new; end $$;
revoke all on function pogo_poc.touch_pokemon() from public, anon, authenticated, service_role;
create trigger touch_pokemon before update on pogo_poc.pokemon for each row execute function pogo_poc.touch_pokemon();
