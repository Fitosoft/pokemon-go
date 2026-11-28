CREATE OR REPLACE FUNCTION pogo_meta.get_chat_context(p_chat_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare own jsonb; st jsonb; ct jsonb; cfg jsonb; directory jsonb;
begin
 select to_jsonb(c) into own from pogo_meta.project_chats c where chat_id=p_chat_id and is_current;
 if own is null then raise exception 'unknown chat identity'; end if;
 if own->>'status'='retired' then raise exception 'retired chat identity'; end if;
 select to_jsonb(s),to_jsonb(t) into st,ct from pogo_meta.system_state s join pogo_meta.technical_contracts t on t.version=s.contract_version and t.schema_version=s.schema_version where s.singleton;
 if st is null then raise exception 'missing or inconsistent contract'; end if;
 select jsonb_object_agg(config_key,to_jsonb(c)) into cfg from pogo_meta.project_config c where is_current;
 if cfg is null or not (cfg ?& array['collaboration_rules','responsibility_matrix','initialization_matrix','playing_strategy','player_preferences','strategic_guidelines','decision_rules','research_rules','communication_rules']) then raise exception 'incomplete project configuration'; end if;
 select jsonb_agg(to_jsonb(c) order by chat_id) into directory from pogo_meta.project_chats c where is_current;
 return jsonb_build_object('system_state',st,'technical_contract',ct,'own_chat',own,'project_chats',directory,'project_config',cfg,'loaded_at',statement_timestamp(),'mailbox',jsonb_build_object('incoming',coalesce((select jsonb_agg(to_jsonb(m) order by case m.priority when 'urgent' then 1 when 'high' then 2 when 'normal' then 3 else 4 end,m.created_at) from pogo_meta.chat_messages m where recipient=p_chat_id and ((kind='message' and read_at is null) or (kind='task' and status in ('open','in_progress')))),'[]'::jsonb),'outgoing_open',coalesce((select jsonb_agg(to_jsonb(m) order by created_at) from pogo_meta.chat_messages m where sender=p_chat_id and kind='task' and status in ('open','in_progress')),'[]'::jsonb),'outgoing_results',coalesce((select jsonb_agg(to_jsonb(m) order by updated_at) from pogo_meta.chat_messages m where sender=p_chat_id and kind='task' and status in ('completed','cancelled') and sender_seen_version<version),'[]'::jsonb)), 'available_modules',jsonb_build_array('inventory','project_context','mailbox','resources'),'unavailable_modules',jsonb_build_array('strategic_goals','planned_actions','decisions','assessments','research','events','teams','pokedex','mega'));
end $function$
;
