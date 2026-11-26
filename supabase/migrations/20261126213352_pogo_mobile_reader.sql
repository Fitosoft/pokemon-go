-- Public historical edition. Original structural SQL; no production rows included.
-- For a new disposable database only; never replay over an existing deployment.
create role pogo_reader login noinherit nosuperuser nocreatedb nocreaterole noreplication nobypassrls password null;
alter role pogo_reader set default_transaction_read_only=on;
grant connect on database postgres to pogo_reader;
grant usage on schema pogo,pogo_meta,pogo_poc,pogo_poc_restore to pogo_reader;
grant select on all tables in schema pogo,pogo_meta,pogo_poc,pogo_poc_restore to pogo_reader;
do $$ declare t record; begin for t in select schemaname,tablename from pg_tables where schemaname in ('pogo','pogo_meta','pogo_poc','pogo_poc_restore') loop execute format('create policy mobile_reader_select on %I.%I for select to pogo_reader using (true)',t.schemaname,t.tablename); end loop; end $$;
alter default privileges for role postgres in schema pogo,pogo_meta,pogo_poc,pogo_poc_restore grant select on tables to pogo_reader;
