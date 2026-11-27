create table pogo_meta.chat_messages (
 id uuid primary key default gen_random_uuid(), sender text not null check(sender ~ '^[0-9]{2}$'), recipient text not null check(recipient ~ '^[0-9]{2}$' and recipient<>sender), kind text not null check(kind in ('message','task')), subject text not null check(btrim(subject)<>''), body text not null check(btrim(body)<>''), priority text not null default 'normal' check(priority in ('low','normal','high','urgent')), pokemon_id uuid references pogo.pokemon(id), due_at timestamptz, status text not null check(status in ('open','in_progress','completed','cancelled')), read_at timestamptz, result text, version integer not null default 1 check(version>0), created_at timestamptz not null default now(), updated_at timestamptz not null default now(), sender_seen_version integer not null default 1 check(sender_seen_version>0 and sender_seen_version<=version),
 check(kind='task' or (due_at is null and status='open' and result is null)), check(status<>'completed' or nullif(btrim(result),'') is not null)
);
create index chat_messages_recipient on pogo_meta.chat_messages(recipient,status,read_at);
create index chat_messages_sender on pogo_meta.chat_messages(sender,status);
create table pogo_meta.chat_message_history (
 operation_key text primary key check(btrim(operation_key)<>''), message_id uuid not null references pogo_meta.chat_messages(id), actor text not null, action text not null, payload jsonb not null, before_data jsonb, after_data jsonb not null, response jsonb not null, recorded_at timestamptz not null default now()
);
create index chat_message_history_message on pogo_meta.chat_message_history(message_id);
alter table pogo_meta.chat_messages enable row level security;
alter table pogo_meta.chat_message_history enable row level security;
revoke all on pogo_meta.chat_messages,pogo_meta.chat_message_history from public,anon,authenticated,service_role,pogo_reader;
grant select on pogo_meta.chat_messages,pogo_meta.chat_message_history to pogo_reader;
create policy mobile_reader_select on pogo_meta.chat_messages for select to pogo_reader using(true);
create policy mobile_reader_select on pogo_meta.chat_message_history for select to pogo_reader using(true);
create function pogo_meta.write_chat_message(p_key text,p_actor text,p_action text,p_id uuid,p_expected integer,p_data jsonb) returns jsonb language plpgsql security invoker set search_path='' as $$
declare m pogo_meta.chat_messages%rowtype; old_m pogo_meta.chat_messages%rowtype; h pogo_meta.chat_message_history%rowtype; payload jsonb; answer jsonb; next_status text;
begin
 if nullif(btrim(p_key),'') is null or p_actor is null or p_action is null or p_action not in ('create','read','start','complete','cancel','acknowledge') or jsonb_typeof(p_data) is distinct from 'object' then raise exception 'invalid mailbox request'; end if;
 if not exists(select 1 from pogo_meta.system_state where singleton and readiness in ('pilot','released')) then raise exception 'writes not released'; end if;
 perform pg_advisory_xact_lock(730030,1);
 payload:=jsonb_build_object('actor',p_actor,'action',p_action,'id',p_id,'expected',p_expected,'data',p_data);
 select * into h from pogo_meta.chat_message_history where operation_key=p_key;
 if found then
 if h.payload is distinct from payload then raise exception 'idempotency conflict'; end if;
 return h.response;
 end if;
 if not exists(select 1 from pogo_meta.project_chats where chat_id=p_actor and is_current and status<>'retired') then raise exception 'unknown or retired actor'; end if;
 if p_action='create' then
 if p_id is not null or p_expected is not null then raise exception 'create requires null id and expected version'; end if;
 if exists(select 1 from jsonb_object_keys(p_data) k where k not in ('recipient','kind','subject','body','priority','pokemon_id','due_at')) then raise exception 'unknown create field'; end if;
 if not exists(select 1 from pogo_meta.project_chats where chat_id=p_data->>'recipient' and is_current and status<>'retired') then raise exception 'unknown or retired recipient'; end if;
 if exists(select 1 from jsonb_each(p_data) e where jsonb_typeof(e.value) not in ('string','null')) then raise exception 'invalid create value'; end if;
 insert into pogo_meta.chat_messages(sender,recipient,kind,subject,body,priority,pokemon_id,due_at,status)
 values(p_actor,p_data->>'recipient',p_data->>'kind',p_data->>'subject',p_data->>'body',coalesce(p_data->>'priority','normal'),(p_data->>'pokemon_id')::uuid,(p_data->>'due_at')::timestamptz,'open') returning * into m;
 else
 select * into old_m from pogo_meta.chat_messages where id=p_id for update;
 if not found or p_expected is null or old_m.version<>p_expected then raise exception 'message version conflict or missing message'; end if;
 if p_action='complete' then
 if (select count(*) from jsonb_object_keys(p_data))<>1 or jsonb_typeof(p_data->'result') is distinct from 'string' or nullif(btrim(p_data->>'result'),'') is null then raise exception 'completion requires result'; end if;
 elsif p_action='cancel' then
 if (select count(*) from jsonb_object_keys(p_data))<>1 or jsonb_typeof(p_data->'reason') is distinct from 'string' or nullif(btrim(p_data->>'reason'),'') is null then raise exception 'cancellation requires reason'; end if;
 elsif p_data<>'{}'::jsonb then raise exception 'unexpected action data'; end if;
 if p_action='acknowledge' then
 if p_actor<>old_m.sender or old_m.kind<>'task' or old_m.status not in ('completed','cancelled') or old_m.sender_seen_version=old_m.version then raise exception 'invalid acknowledgement'; end if;
 update pogo_meta.chat_messages set version=version+1,sender_seen_version=version+1,updated_at=clock_timestamp() where id=p_id returning * into m;
 elsif p_action='cancel' then
 if p_actor not in (old_m.sender,old_m.recipient) or old_m.kind<>'task' or old_m.status not in ('open','in_progress') then raise exception 'invalid cancellation'; end if;
 update pogo_meta.chat_messages set status='cancelled',result=p_data->>'reason',version=version+1,updated_at=clock_timestamp(),sender_seen_version=case when p_actor=sender then version+1 else sender_seen_version end where id=p_id returning * into m;
 else
 if p_actor<>old_m.recipient then raise exception 'recipient action only'; end if;
 if p_action='read' then
 if old_m.read_at is not null then raise exception 'already read'; end if;
 update pogo_meta.chat_messages set read_at=clock_timestamp(),version=version+1,updated_at=clock_timestamp() where id=p_id returning * into m;
 else
 if old_m.kind<>'task' or (p_action='start' and old_m.status<>'open') or (p_action='complete' and old_m.status not in ('open','in_progress')) then raise exception 'invalid task transition'; end if;
 next_status:=case when p_action='start' then 'in_progress' else 'completed' end;
 update pogo_meta.chat_messages set status=next_status,result=case when p_action='complete' then p_data->>'result' else null end,read_at=coalesce(read_at,clock_timestamp()),version=version+1,updated_at=clock_timestamp() where id=p_id returning * into m;
 end if;
 end if;
 end if;
 answer:=jsonb_build_object('id',m.id,'version',m.version,'status',m.status,'operation_key',p_key);
 insert into pogo_meta.chat_message_history(operation_key,message_id,actor,action,payload,before_data,after_data,response) values(p_key,m.id,p_actor,p_action,payload,case when p_action='create' then null else to_jsonb(old_m) end,to_jsonb(m),answer);
 return answer;
end $$;
create function pogo_meta.guard_mailbox_write() returns trigger language plpgsql security invoker set search_path='' as $$
declare ctx text;
begin
 get diagnostics ctx = PG_CONTEXT;
 if TG_OP in ('DELETE','TRUNCATE') or (TG_TABLE_NAME='chat_message_history' and TG_OP<>'INSERT') or not exists(select 1 from regexp_split_to_table(ctx,chr(10)) line where line ~ '^PL/pgSQL function (pogo_meta\.)?write_chat_message\(text,text,text,uuid,integer,jsonb\) line [0-9]+ at SQL statement$') then raise exception using errcode='P0301',message='direct mailbox write blocked'; end if;
 return null;
end $$;
create trigger guard_mailbox_write before insert or update or delete or truncate on pogo_meta.chat_messages for each statement execute function pogo_meta.guard_mailbox_write();
create trigger guard_mailbox_write before insert or update or delete or truncate on pogo_meta.chat_message_history for each statement execute function pogo_meta.guard_mailbox_write();
revoke all on function pogo_meta.write_chat_message(text,text,text,uuid,integer,jsonb),pogo_meta.guard_mailbox_write() from public,anon,authenticated,service_role,pogo_reader;

