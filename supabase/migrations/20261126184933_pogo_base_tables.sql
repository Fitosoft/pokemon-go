-- Public historical edition. Omit project backlog seed data.
-- For a new disposable database only; never replay over an existing deployment.
create schema pogo;
revoke all on schema pogo from public,anon,authenticated,service_role;
create table pogo.import_batches (
 id uuid primary key default gen_random_uuid(), batch_key text not null unique check(btrim(batch_key)<>''), source_type text not null, source_ref text not null, created_at timestamptz not null default now()
);
create table pogo.pokemon (
 id uuid primary key default gen_random_uuid(),
 pokedex_number integer check(pokedex_number>0), species_name text, form text, nickname text,
 cp integer check(cp>0), max_hp integer check(max_hp>0),
 iv_attack smallint check(iv_attack between 0 and 15), iv_defense smallint check(iv_defense between 0 and 15), iv_stamina smallint check(iv_stamina between 0 and 15),
 level numeric(4,1) check(level>=1 and level<=55 and mod(level*2,1)=0),
 is_shiny boolean, is_shadow boolean, is_purified boolean, is_lucky boolean, is_favorite boolean,
 max_type text check(max_type in ('none','dynamax','gigantamax')),
 max_attack_level smallint check(max_attack_level between 0 and 3), max_guard_level smallint check(max_guard_level between 0 and 3), max_spirit_level smallint check(max_spirit_level between 0 and 3),
 fast_move text, charged_move_1 text, charged_move_2 text,
 size_class text check(size_class in ('xxs','xs','normal','xl','xxl')), gender text check(gender in ('male','female','genderless')),
 costume_code text, background_code text, acquisition_method text, catch_location text,
 caught_on date, acquired_on date, egg_received_on date, hatched_on date, traded_on date,
 height_m numeric check(height_m>0), weight_kg numeric check(weight_kg>0), ball_type text,
 status text check(status in ('owned','transferred','traded','unknown')),
 version bigint not null default 1 check(version>0), created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check(not (is_shadow is true and is_purified is true)),
 check(max_type is distinct from 'none' or (coalesce(max_attack_level,0)=0 and coalesce(max_guard_level,0)=0 and coalesce(max_spirit_level,0)=0)),
 check(pokedex_number is not null or nullif(btrim(species_name),'') is not null)
);
create table pogo.operations (
 id uuid primary key default gen_random_uuid(), idempotency_key text not null unique check(btrim(idempotency_key)<>''), operation_type text not null,
 payload jsonb not null, result jsonb, created_at timestamptz not null default now(), completed_at timestamptz,
 check((result is null)=(completed_at is null))
);
create table pogo.import_items (
 batch_id uuid not null references pogo.import_batches(id), source_item_key text not null check(btrim(source_item_key)<>''), pokemon_id uuid not null references pogo.pokemon(id), primary key(batch_id,source_item_key)
);
create table pogo.pokemon_field_evidence (
 id uuid primary key default gen_random_uuid(), pokemon_id uuid not null references pogo.pokemon(id),
 field_name text not null, observed_value jsonb not null, source_type text not null check(source_type in ('user','screenshot','scanner','legacy_chat','derived','other','test')),
 source_ref text not null check(btrim(source_ref)<>''), verification_status text not null check(verification_status in ('unverified','verified','inferred','conflicting')),
 observed_at timestamptz, verified_at timestamptz, recorded_at timestamptz not null default now(),
 is_current boolean not null default false, operation_id uuid not null references pogo.operations(id),
 check(verification_status<>'verified' or verified_at is not null)
);
create unique index pokemon_current_evidence on pogo.pokemon_field_evidence(pokemon_id,field_name) where is_current;
create table pogo.change_log (
 id bigint generated always as identity primary key, pokemon_id uuid not null references pogo.pokemon(id), operation_id uuid not null references pogo.operations(id),
 action text not null check(action in ('insert','update','evidence')), before_data jsonb, after_data jsonb not null, changed_at timestamptz not null default now()
);
do $$ declare t text; begin foreach t in array array['import_batches','pokemon','operations','import_items','pokemon_field_evidence','change_log'] loop execute format('alter table pogo.%I enable row level security',t); end loop; end $$;
revoke all on all tables in schema pogo from public,anon,authenticated,service_role;
revoke all on all sequences in schema pogo from public,anon,authenticated,service_role;
