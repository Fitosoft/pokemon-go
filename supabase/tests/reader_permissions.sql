-- Read-only checks of effective application privileges.
\set ON_ERROR_STOP on
DO $$
DECLARE t record; f record;
BEGIN
  FOR t IN SELECT c.oid,n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relkind='r' AND n.nspname IN ('pogo','pogo_meta','pogo_poc','pogo_poc_restore') LOOP
    IF NOT has_table_privilege('pogo_reader',t.oid,'SELECT')
       OR has_table_privilege('pogo_reader',t.oid,'INSERT,UPDATE,DELETE,TRUNCATE')
       OR has_schema_privilege('pogo_reader',t.nspname,'CREATE')
    THEN RAISE EXCEPTION 'Unexpected reader privilege on %.%',t.nspname,t.relname; END IF;
  END LOOP;
  FOR f IN SELECT p.oid,p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('pogo','pogo_meta','pogo_poc','pogo_poc_restore') LOOP
    IF has_function_privilege('pogo_reader',f.oid,'EXECUTE') THEN RAISE EXCEPTION 'Unexpected function access: %',f.proname; END IF;
  END LOOP;
  RAISE NOTICE 'Reader privilege assertions passed';
END $$;
