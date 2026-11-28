CREATE OR REPLACE FUNCTION pogo.publish_resource_catalog(p_key text, p_actor text, p_entries jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare op pogo.resource_operations%rowtype; entry jsonb; c pogo.resource_catalog%rowtype; payload jsonb; out_rows jsonb:='[]'; answer jsonb;
begin
 if nullif(btrim(p_key),'') is null or (p_actor is null or p_actor not in ('00','99')) or jsonb_typeof(p_entries) is distinct from 'array' or jsonb_array_length(p_entries)=0 then raise exception 'invalid catalog request'; end if;
 if not exists(select 1 from pogo_meta.system_state where singleton and readiness in ('pilot','released')) then raise exception 'writes not released'; end if;
 perform pg_advisory_xact_lock(730030,2);
 payload:=jsonb_build_object('actor',p_actor,'kind','catalog','entries',p_entries);
 select * into op from pogo.resource_operations where operation_key=p_key;
 if found then if op.payload is distinct from payload then raise exception 'idempotency conflict';end if;return op.result;end if;
 insert into pogo.resource_operations(operation_key,actor,kind,payload) values(p_key,p_actor,'catalog',payload) returning * into op;
 for entry in select value from jsonb_array_elements(p_entries) loop
 if jsonb_typeof(entry) is distinct from 'object' or not(entry ?& array['code','resource_type','label','category','unit','scope_key','measure','source_ref']) or exists(select 1 from jsonb_object_keys(entry) k where k not in ('code','resource_type','label','category','unit','scope_key','measure','periodic','source_ref','rules')) or exists(select 1 from jsonb_each(entry) e where e.key not in ('periodic','rules') and jsonb_typeof(e.value)<>'string') or (entry?'periodic' and jsonb_typeof(entry->'periodic')<>'boolean') or (entry?'rules' and jsonb_typeof(entry->'rules')<>'object') then raise exception 'invalid catalog entry';end if;
 if p_actor='00' and (entry->>'scope_key' is distinct from 'global' or entry->>'category' is distinct from 'item' or entry->>'measure' is distinct from 'stock' or entry->>'unit' is distinct from 'units' or coalesce((entry->>'periodic')::boolean,false) or coalesce(entry->'rules','{}'::jsonb)<>'{}'::jsonb or entry->>'code' is distinct from entry->>'resource_type' or entry->>'code' !~ '^[a-z][a-z0-9_]*
 values(entry->>'code',entry->>'resource_type',entry->>'label',entry->>'category',entry->>'unit',entry->>'scope_key',entry->>'measure',coalesce((entry->>'periodic')::boolean,false),entry->>'source_ref',coalesce(entry->'rules','{}')) returning * into c;
 out_rows:=out_rows||jsonb_build_array(to_jsonb(c));
 end loop;
 answer:=jsonb_build_object('operation_id',op.id,'entries',out_rows);
 update pogo.resource_operations set result=answer,completed_at=clock_timestamp() where id=op.id;
 return answer;
end $function$
) then raise exception '00 may add only nonperiodic global item stock definitions';end if;
 insert into pogo.resource_catalog(code,resource_type,label,category,unit,scope_key,measure,periodic,source_ref,rules)
 values(entry->>'code',entry->>'resource_type',entry->>'label',entry->>'category',entry->>'unit',entry->>'scope_key',entry->>'measure',coalesce((entry->>'periodic')::boolean,false),entry->>'source_ref',coalesce(entry->'rules','{}')) returning * into c;
 out_rows:=out_rows||jsonb_build_array(to_jsonb(c));
 end loop;
 answer:=jsonb_build_object('operation_id',op.id,'entries',out_rows);
 update pogo.resource_operations set result=answer,completed_at=clock_timestamp() where id=op.id;
 return answer;
end $function$
;
