-- Public historical edition. Original structural SQL; no production rows included.
-- For a new disposable database only; never replay over an existing deployment.
create function pogo.guard_write() returns trigger language plpgsql security invoker set search_path='' as $$
declare ctx text;
begin
 get diagnostics ctx = PG_CONTEXT;
 if TG_OP in ('DELETE','TRUNCATE') or not exists (select 1 from regexp_split_to_table(ctx,chr(10)) as line where line ~ '^PL/pgSQL function (pogo\.)?(write_pokemon\(text,uuid,bigint,jsonb,jsonb,jsonb\)|record_observation\(text,uuid,bigint,text,jsonb,jsonb\)) line [0-9]+ at (SQL statement|EXECUTE)$') then
 raise exception using errcode='P0301',message='direct write blocked; use controlled pogo function';
 end if;
 return null;
end $$;
do $$ declare t text; begin
foreach t in array array['pokemon','pokemon_field_evidence','operations','change_log','import_batches','import_items'] loop
execute format('create trigger guard_write before insert or update or delete or truncate on pogo.%I for each statement execute function pogo.guard_write()',t);
end loop;
end $$;
revoke all on function pogo.guard_write() from public,anon,authenticated,service_role;
