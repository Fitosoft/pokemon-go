-- Public historical edition. Original structural SQL; no production rows included.
-- For a new disposable database only; never replay over an existing deployment.
create function pogo.write_pokemon(p_key text,p_id uuid,p_expected bigint,p_fields jsonb,p_evidence jsonb,p_batch jsonb default null) returns jsonb language plpgsql security invoker set search_path='' as $$
declare op pogo.operations%rowtype; oldrow pogo.pokemon%rowtype; newrow pogo.pokemon%rowtype; payload jsonb; f text; ev jsonb; bid uuid; target uuid; answer jsonb; cols text; vals text; readiness_value text;
begin
 if p_key is null or btrim(p_key)='' or jsonb_typeof(p_fields) is distinct from 'object' or jsonb_typeof(p_evidence) is distinct from 'object' then raise exception 'invalid request'; end if;
 select readiness into readiness_value from pogo_meta.system_state where singleton;
 if readiness_value is null or readiness_value not in ('pilot','released') then raise exception 'writes not released'; end if;
 payload:=jsonb_build_object('id',p_id,'expected',p_expected,'fields',p_fields,'evidence',p_evidence,'batch',p_batch);
 insert into pogo.operations(idempotency_key,operation_type,payload) values(p_key,'write_pokemon',payload) on conflict(idempotency_key) do nothing;
 select * into op from pogo.operations where idempotency_key=p_key for update;
 if op.operation_type <> 'write_pokemon' or op.payload is distinct from payload then raise exception 'idempotency conflict'; end if;
 if op.result is not null then return op.result; end if;
 if p_fields='{}'::jsonb then raise exception 'empty fields'; end if;
 for f in select jsonb_object_keys(p_fields) loop
 if f not in ('pokedex_number','species_name','form','nickname','cp','max_hp','iv_attack','iv_defense','iv_stamina','level','is_shiny','is_shadow','is_purified','is_lucky','is_favorite','max_type','max_attack_level','max_guard_level','max_spirit_level','fast_move','charged_move_1','charged_move_2','size_class','gender','costume_code','background_code','acquisition_method','catch_location','caught_on','acquired_on','egg_received_on','hatched_on','traded_on','height_m','weight_kg','ball_type','status') then raise exception 'unknown or protected field %',f; end if;
 ev:=p_evidence->f;
 if jsonb_typeof(ev) is distinct from 'object' or coalesce(ev->>'source_ref','')='' or coalesce(ev->>'source_type','')='' or coalesce(ev->>'verification_status','')='' then raise exception 'missing evidence for %',f; end if;
 if ev->>'verification_status'='conflicting' then raise exception 'conflicting value must use observation function'; end if;
 end loop;
 if exists(select 1 from jsonb_object_keys(p_evidence) k where not p_fields ? k) then raise exception 'evidence without field'; end if;
 if p_batch is not null then
 if jsonb_typeof(p_batch) is distinct from 'object' or coalesce(p_batch->>'batch_key','')='' or coalesce(p_batch->>'source_item_key','')='' or coalesce(p_batch->>'source_type','')='' or coalesce(p_batch->>'source_ref','')='' then raise exception 'invalid batch'; end if;
 insert into pogo.import_batches(batch_key,source_type,source_ref) values(p_batch->>'batch_key',p_batch->>'source_type',p_batch->>'source_ref') on conflict(batch_key) do nothing;
 select id into bid from pogo.import_batches where batch_key=p_batch->>'batch_key' and source_type=p_batch->>'source_type' and source_ref=p_batch->>'source_ref' for update;
 if bid is null then raise exception 'batch identity conflict'; end if;
 select pokemon_id into target from pogo.import_items where batch_id=bid and source_item_key=p_batch->>'source_item_key';
 if target is not null then raise exception 'import item already processed; inspect existing mapping'; end if;
 end if;
 if p_id is null then
 if p_expected is not null then raise exception 'new record must not have expected version'; end if;
 newrow:=jsonb_populate_record(null::pogo.pokemon,p_fields);
 newrow.id:=gen_random_uuid();newrow.version:=1;newrow.created_at:=now();newrow.updated_at:=now();
 insert into pogo.pokemon select newrow.* returning * into newrow;
 else
 select * into oldrow from pogo.pokemon where id=p_id for update;
 if not found or p_expected is null or oldrow.version<>p_expected then raise exception 'version conflict or missing pokemon'; end if;
 newrow:=jsonb_populate_record(oldrow,p_fields);
 select string_agg(format('%I',k),',' order by k),string_agg(format('($1).%I',k),',' order by k) into cols,vals from jsonb_object_keys(p_fields) k;
 execute format('update pogo.pokemon set (%s,version,updated_at)=(%s,version+1,clock_timestamp()) where id=$2 returning *',cols,vals) into newrow using newrow,p_id;
 end if;
 for f in select jsonb_object_keys(p_fields) loop
 ev:=p_evidence->f;
 update pogo.pokemon_field_evidence set is_current=false where pokemon_id=newrow.id and field_name=f and is_current;
 insert into pogo.pokemon_field_evidence(pokemon_id,field_name,observed_value,source_type,source_ref,verification_status,observed_at,verified_at,is_current,operation_id)
 values(newrow.id,f,to_jsonb(newrow)->f,ev->>'source_type',ev->>'source_ref',ev->>'verification_status',(ev->>'observed_at')::timestamptz,(ev->>'verified_at')::timestamptz,true,op.id);
 end loop;
 if bid is not null then insert into pogo.import_items values(bid,p_batch->>'source_item_key',newrow.id); end if;
 insert into pogo.change_log(pokemon_id,operation_id,action,before_data,after_data) values(newrow.id,op.id,case when p_id is null then 'insert' else 'update' end,case when p_id is null then null else to_jsonb(oldrow) end,to_jsonb(newrow));
 answer:=jsonb_build_object('pokemon_id',newrow.id,'version',newrow.version,'operation_id',op.id);
 update pogo.operations set result=answer,completed_at=now() where id=op.id;
 return answer;
end $$;
create function pogo.record_observation(p_key text,p_id uuid,p_expected bigint,p_field text,p_value jsonb,p_evidence jsonb) returns jsonb language plpgsql security invoker set search_path='' as $$
declare op pogo.operations%rowtype; r pogo.pokemon%rowtype; payload jsonb; answer jsonb; eid uuid;
begin
 if p_key is null or btrim(p_key)='' or p_value is null or jsonb_typeof(p_evidence) is distinct from 'object' then raise exception 'invalid observation'; end if;
 if not exists(select 1 from pogo_meta.system_state where singleton and readiness in ('pilot','released')) then raise exception 'writes not released'; end if;
 payload:=jsonb_build_object('id',p_id,'expected',p_expected,'field',p_field,'value',p_value,'evidence',p_evidence);
 insert into pogo.operations(idempotency_key,operation_type,payload) values(p_key,'record_observation',payload) on conflict(idempotency_key) do nothing;
 select * into op from pogo.operations where idempotency_key=p_key for update;
 if op.operation_type<>'record_observation' or op.payload is distinct from payload then raise exception 'idempotency conflict'; end if;
 if op.result is not null then return op.result; end if;
 select * into r from pogo.pokemon where id=p_id for update;
 if not found or p_expected is null or r.version<>p_expected then raise exception 'version conflict or missing pokemon'; end if;
 if p_field is null or not (to_jsonb(r) ? p_field) or p_field in ('id','version','created_at','updated_at') then raise exception 'unknown field'; end if;
 insert into pogo.pokemon_field_evidence(pokemon_id,field_name,observed_value,source_type,source_ref,verification_status,observed_at,verified_at,is_current,operation_id)
 values(p_id,p_field,p_value,p_evidence->>'source_type',p_evidence->>'source_ref',p_evidence->>'verification_status',(p_evidence->>'observed_at')::timestamptz,(p_evidence->>'verified_at')::timestamptz,false,op.id) returning id into eid;
 insert into pogo.change_log(pokemon_id,operation_id,action,before_data,after_data) values(p_id,op.id,'evidence',to_jsonb(r),jsonb_build_object('evidence_id',eid,'field',p_field,'value',p_value));
 answer:=jsonb_build_object('pokemon_id',p_id,'version',r.version,'evidence_id',eid,'operation_id',op.id);
 update pogo.operations set result=answer,completed_at=now() where id=op.id;
 return answer;
end $$;
revoke all on all functions in schema pogo from public,anon,authenticated,service_role;
