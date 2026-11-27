-- Approved structural migration; pending deployment and validation.
create table pogo_meta.project_chats (
 chat_id text not null check(chat_id ~ '^[0-9]{2}$'), version integer not null check(version>0),
 display_name text not null check(btrim(display_name)<>''), status text not null check(status in ('planned','active','temporary','retired')),
 purpose text not null, responsibilities text not null, boundaries text not null, initial_tasks text not null,
 is_current boolean not null default true, changed_at timestamptz not null default now(), changed_by text not null check(changed_by in ('00','99')), change_reason text not null check(btrim(change_reason)<>''), operation_key text not null unique check(btrim(operation_key)<>''), primary key(chat_id,version)
);
create unique index project_chats_current on pogo_meta.project_chats(chat_id) where is_current;
create table pogo_meta.project_config (
 config_key text not null check(config_key ~ '^[a-z][a-z0-9_]*$'), version integer not null check(version>0),
 title text not null check(btrim(title)<>''), content text not null check(btrim(content)<>''), is_current boolean not null default true,
 changed_at timestamptz not null default now(), changed_by text not null check(changed_by in ('00','99')), change_reason text not null check(btrim(change_reason)<>''), operation_key text not null unique check(btrim(operation_key)<>''), primary key(config_key,version)
);
create unique index project_config_current on pogo_meta.project_config(config_key) where is_current;
alter table pogo_meta.project_chats enable row level security;
alter table pogo_meta.project_config enable row level security;
revoke all on pogo_meta.project_chats,pogo_meta.project_config from public,anon,authenticated,service_role,pogo_reader;
grant select on pogo_meta.project_chats,pogo_meta.project_config to pogo_reader;
create policy mobile_reader_select on pogo_meta.project_chats for select to pogo_reader using(true);
create policy mobile_reader_select on pogo_meta.project_config for select to pogo_reader using(true);
create function pogo_meta.publish_context_revision(p_kind text,p_key text,p_expected integer,p_operation_key text,p_actor text,p_reason text,p_data jsonb) returns jsonb language plpgsql security invoker set search_path='' as $$
declare prev integer; payload jsonb; existing jsonb; result jsonb;
begin
 if p_kind is null or p_kind not in ('chat','config') or p_key is null or p_actor is null or p_actor not in ('00','99') or nullif(btrim(p_operation_key),'') is null or nullif(btrim(p_reason),'') is null or jsonb_typeof(p_data) is distinct from 'object' or p_expected is null or p_expected<0 then raise exception 'invalid revision request'; end if;
 if not exists(select 1 from pogo_meta.system_state where singleton and readiness in ('pilot','released')) then raise exception 'writes not released'; end if;
 perform pg_advisory_xact_lock(730030,0);
 if p_kind='chat' then
 if p_key !~ '^[0-9]{2}$' or (select count(*) from jsonb_object_keys(p_data))<>6 or not (p_data ?& array['display_name','status','purpose','responsibilities','boundaries','initial_tasks']) or exists(select 1 from jsonb_each(p_data) e where jsonb_typeof(e.value)<>'string' or btrim(e.value#>>'{}')='') then raise exception 'invalid chat payload'; end if;
 else
 if p_key !~ '^[a-z][a-z0-9_]*$' or (select count(*) from jsonb_object_keys(p_data))<>2 or not (p_data ?& array['title','content']) or exists(select 1 from jsonb_each(p_data) e where jsonb_typeof(e.value)<>'string' or btrim(e.value#>>'{}')='') then raise exception 'invalid config payload'; end if;
 end if;
 payload:=jsonb_build_object('kind',p_kind,'key',p_key,'version',p_expected+1,'actor',p_actor,'reason',p_reason,'data',p_data);
 select jsonb_build_object('kind','chat','key',chat_id,'version',version,'actor',changed_by,'reason',change_reason,'data',jsonb_build_object('display_name',display_name,'status',status,'purpose',purpose,'responsibilities',responsibilities,'boundaries',boundaries,'initial_tasks',initial_tasks)) into existing from pogo_meta.project_chats where operation_key=p_operation_key;
 if existing is null then select jsonb_build_object('kind','config','key',config_key,'version',version,'actor',changed_by,'reason',change_reason,'data',jsonb_build_object('title',title,'content',content)) into existing from pogo_meta.project_config where operation_key=p_operation_key; end if;
 if existing is not null then
 if existing is distinct from payload then raise exception 'idempotency conflict'; end if;
 return jsonb_build_object('kind',p_kind,'key',p_key,'version',p_expected+1,'operation_key',p_operation_key);
 end if;
 if p_kind='chat' then
 select version into prev from pogo_meta.project_chats where chat_id=p_key and is_current;
 if coalesce(prev,0)<>p_expected then raise exception 'revision version conflict'; end if;
 update pogo_meta.project_chats set is_current=false where chat_id=p_key and is_current;
 insert into pogo_meta.project_chats(chat_id,version,display_name,status,purpose,responsibilities,boundaries,initial_tasks,changed_by,change_reason,operation_key) values(p_key,p_expected+1,p_data->>'display_name',p_data->>'status',p_data->>'purpose',p_data->>'responsibilities',p_data->>'boundaries',p_data->>'initial_tasks',p_actor,p_reason,p_operation_key);
 else
 select version into prev from pogo_meta.project_config where config_key=p_key and is_current;
 if coalesce(prev,0)<>p_expected then raise exception 'revision version conflict'; end if;
 update pogo_meta.project_config set is_current=false where config_key=p_key and is_current;
 insert into pogo_meta.project_config(config_key,version,title,content,changed_by,change_reason,operation_key) values(p_key,p_expected+1,p_data->>'title',p_data->>'content',p_actor,p_reason,p_operation_key);
 end if;
 return jsonb_build_object('kind',p_kind,'key',p_key,'version',p_expected+1,'operation_key',p_operation_key);
end $$;
create function pogo_meta.guard_context_revision() returns trigger language plpgsql security invoker set search_path='' as $$
declare ctx text;
begin
 get diagnostics ctx = PG_CONTEXT;
 if TG_OP in ('DELETE','TRUNCATE') or not exists(select 1 from regexp_split_to_table(ctx,chr(10)) as line where line ~ '^PL/pgSQL function (pogo_meta\.)?publish_context_revision\(text,text,integer,text,text,text,jsonb\) line [0-9]+ at SQL statement$') then raise exception using errcode='P0301',message='direct context write blocked'; end if;
 return null;
end $$;
create trigger guard_context_revision before insert or update or delete or truncate on pogo_meta.project_chats for each statement execute function pogo_meta.guard_context_revision();
create trigger guard_context_revision before insert or update or delete or truncate on pogo_meta.project_config for each statement execute function pogo_meta.guard_context_revision();
create function pogo_meta.get_chat_context(p_chat_id text) returns jsonb language plpgsql stable security invoker set search_path='' as $$
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
 return jsonb_build_object('system_state',st,'technical_contract',ct,'own_chat',own,'project_chats',directory,'project_config',cfg,'loaded_at',statement_timestamp(),'available_modules',jsonb_build_array('inventory','project_context'),'unavailable_modules',jsonb_build_array('mailbox','resources','strategic_goals','planned_actions','decisions','assessments','research','events','teams','pokedex','mega'));
end $$;
revoke all on function pogo_meta.publish_context_revision(text,text,integer,text,text,text,jsonb),pogo_meta.guard_context_revision(),pogo_meta.get_chat_context(text) from public,anon,authenticated,service_role,pogo_reader;
