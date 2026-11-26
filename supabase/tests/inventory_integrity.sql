-- Run only against a fresh, disposable public reconstruction.
-- All test records and readiness changes are rolled back; identity sequence
-- values may advance. Never use a production inventory as a test database.
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
  a jsonb; b jsonb; pid uuid;
  k text := 'test:' || gen_random_uuid()::text;
  e jsonb := '{"source_type":"test","source_ref":"synthetic-fixture","verification_status":"unverified"}';
  v jsonb := jsonb_build_object('source_type','test','source_ref','synthetic-confirmation','verification_status','verified','verified_at',now());
  f jsonb := '{"pokedex_number":25,"cp":500,"iv_attack":0}';
  ev jsonb; batch jsonb;
BEGIN
  IF EXISTS (SELECT 1 FROM pogo.pokemon) THEN
    RAISE EXCEPTION 'Refusing to test nonempty inventory';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pogo_meta.system_state WHERE singleton AND project_ref='replace-with-your-project-ref' AND readiness='building') THEN
    RAISE EXCEPTION 'Expected fresh public reconstruction in building status';
  END IF;
  ev := jsonb_build_object('pokedex_number',e,'cp',e,'iv_attack',e);
  batch := jsonb_build_object('batch_key',k,'source_item_key','fixture-1','source_type','test','source_ref','synthetic-fixture');
  BEGIN
    PERFORM pogo.write_pokemon(k,NULL,NULL,f,ev,batch);
    RAISE EXCEPTION USING ERRCODE='P9902',MESSAGE='Readiness gate failed';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'writes not released' THEN RAISE; END IF;
  END;
  UPDATE pogo_meta.system_state SET readiness='pilot' WHERE singleton;
  BEGIN
    INSERT INTO pogo.pokemon(pokedex_number) VALUES(25);
    RAISE EXCEPTION USING ERRCODE='P9902',MESSAGE='Direct insert accepted';
  EXCEPTION WHEN SQLSTATE 'P0301' THEN NULL;
  END;
  a := pogo.write_pokemon(k,NULL,NULL,f,ev,batch);
  pid := (a->>'pokemon_id')::uuid;
  b := pogo.write_pokemon(k,NULL,NULL,f,ev,batch);
  IF a IS DISTINCT FROM b THEN RAISE EXCEPTION 'Retry mismatch'; END IF;
  BEGIN
    PERFORM pogo.write_pokemon(k,NULL,NULL,f||'{"cp":501}',ev,batch);
    RAISE EXCEPTION USING ERRCODE='P9902',MESSAGE='Changed payload accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'idempotency conflict' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM pogo.write_pokemon(k||':duplicate',NULL,NULL,f,ev,batch);
    RAISE EXCEPTION USING ERRCODE='P9902',MESSAGE='Duplicate import accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'import item already processed%' THEN RAISE; END IF;
  END;
  a := pogo.write_pokemon(k||':update',pid,1,'{"cp":550}',jsonb_build_object('cp',v));
  IF (a->>'version')::int <> 2 THEN RAISE EXCEPTION 'Version mismatch'; END IF;
  BEGIN
    PERFORM pogo.write_pokemon(k||':stale',pid,1,'{"cp":600}',jsonb_build_object('cp',e));
    RAISE EXCEPTION USING ERRCODE='P9902',MESSAGE='Stale update accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'version conflict%' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM pogo.write_pokemon(k||':invalid',pid,2,'{"iv_attack":16}',jsonb_build_object('iv_attack',e));
    RAISE EXCEPTION USING ERRCODE='P9902',MESSAGE='Invalid IV accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    PERFORM pogo.write_pokemon(k||':bad-evidence',pid,2,'{"cp":650}',jsonb_build_object('cp',e||'{"verification_status":"verified"}'));
    RAISE EXCEPTION USING ERRCODE='P9902',MESSAGE='Missing verification timestamp accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  b := pogo.record_observation(k||':observation',pid,2,'cp','600',e||'{"verification_status":"conflicting"}');
  IF pogo.record_observation(k||':observation',pid,2,'cp','600',e||'{"verification_status":"conflicting"}') IS DISTINCT FROM b THEN RAISE EXCEPTION 'Observation retry mismatch'; END IF;
  BEGIN
    UPDATE pogo.pokemon SET cp=999 WHERE id=pid;
    RAISE EXCEPTION USING ERRCODE='P9902',MESSAGE='Direct update accepted';
  EXCEPTION WHEN SQLSTATE 'P0301' THEN NULL;
  END;
  BEGIN
    DELETE FROM pogo.pokemon WHERE id=pid;
    RAISE EXCEPTION USING ERRCODE='P9902',MESSAGE='Direct delete accepted';
  EXCEPTION WHEN SQLSTATE 'P0301' THEN NULL;
  END;
  IF (SELECT cp FROM pogo.pokemon WHERE id=pid) IS DISTINCT FROM 550
     OR (SELECT version FROM pogo.pokemon WHERE id=pid) IS DISTINCT FROM 2::bigint
     OR (SELECT iv_attack FROM pogo.pokemon WHERE id=pid) IS DISTINCT FROM 0::smallint
     OR (SELECT count(*) FROM pogo.change_log WHERE pokemon_id=pid) <> 3
     OR (SELECT count(*) FROM pogo.operations WHERE idempotency_key LIKE k||'%') <> 3
     OR (SELECT verification_status FROM pogo.pokemon_field_evidence WHERE pokemon_id=pid AND field_name='iv_attack' AND is_current) IS DISTINCT FROM 'unverified'
     OR (SELECT verification_status FROM pogo.pokemon_field_evidence WHERE pokemon_id=pid AND field_name='cp' AND is_current) IS DISTINCT FROM 'verified'
  THEN RAISE EXCEPTION 'Inventory integrity assertion failed'; END IF;
  IF EXISTS (SELECT 1 FROM pogo.pokemon_field_evidence x JOIN pogo.pokemon p ON p.id=x.pokemon_id WHERE x.is_current AND x.observed_value IS DISTINCT FROM to_jsonb(p)->x.field_name) THEN RAISE EXCEPTION 'Evidence mismatch'; END IF;
  RAISE NOTICE 'Inventory integrity assertions passed; rollback follows';
END $$;
ROLLBACK;
