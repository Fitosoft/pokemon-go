create table pogo.resource_catalog (
 id uuid primary key default gen_random_uuid(),
 code text not null unique check(code ~ '^[a-z][a-z0-9_]*(?::[a-z0-9_]+)*$'),
 resource_type text not null check(resource_type ~ '^[a-z][a-z0-9_]*$'),
 label text not null check(btrim(label)<>''),
 category text not null check(category in ('currency','item','candy','energy','storage','progress','reward')),
 unit text not null check(btrim(unit)<>''),
 scope_key text not null check(scope_key='global' or scope_key ~ '^pool:[a-z0-9_]+$'),
 measure text not null check(measure in ('stock','capacity','occupancy','counter','limit','claimable')),
 periodic boolean not null default false,
 source_ref text not null check(btrim(source_ref)<>''),
 rules jsonb not null default '{}' check(jsonb_typeof(rules)='object'),
 created_at timestamptz not null default now(),
 unique(resource_type,scope_key,measure,periodic)
);
create table pogo.resource_operations (
 id uuid primary key default gen_random_uuid(),
 operation_key text not null unique check(btrim(operation_key)<>''),
 actor text not null,
 kind text not null check(kind in ('catalog','batch')),
 payload jsonb not null,
 result jsonb,
 created_at timestamptz not null default now(),
 completed_at timestamptz,
 check((result is null)=(completed_at is null))
);
create table pogo.resource_balances (
 id uuid primary key default gen_random_uuid(),
 resource_id uuid not null references pogo.resource_catalog(id),
 period_start timestamptz not null default '-infinity',
 period_end timestamptz,
 quantity bigint check(quantity>=0),
 version bigint not null default 1 check(version>0),
 basis_history_id uuid,
 basis_from timestamptz, basis_to timestamptz,
 effective_from timestamptz, effective_to timestamptz,
 needs_reconcile boolean not null default false,
 pending_until timestamptz, pending_unknown boolean not null default false,
 updated_at timestamptz not null default now(),
 unique(resource_id,period_start),
 check((period_start='-infinity'::timestamptz and period_end is null) or (isfinite(period_start) and period_end is not null and isfinite(period_end) and period_end>period_start)),
 check((quantity is null and basis_history_id is null and basis_from is null and basis_to is null and effective_from is null and effective_to is null) or (quantity is not null and basis_history_id is not null and basis_from is not null and basis_to is not null and effective_from is not null and effective_to is not null and basis_from<=basis_to and effective_from<=effective_to)),
 check(needs_reconcile or (pending_until is null and not pending_unknown))
);
create table pogo.resource_history (
 id uuid primary key default gen_random_uuid(),
 balance_id uuid not null references pogo.resource_balances(id),
 operation_id uuid not null references pogo.resource_operations(id),
 event_key text not null check(btrim(event_key)<>''),
 kind text not null check(kind in ('snapshot','movement')),
 amount bigint not null,
 observed_from timestamptz, observed_to timestamptz,
 precision_code text not null check(precision_code in ('instant','day','month','year','interval','unknown')),
 source_type text not null check(source_type in ('user','screenshot','scanner','legacy_chat','derived','other','test')),
 source_ref text not null check(btrim(source_ref)<>''),
 verification_status text not null check(verification_status in ('verified','unverified','inferred','conflicting')),
 verified_at timestamptz,
 pokemon_id uuid references pogo.pokemon(id),
 related_ref text,
 disposition text not null check(disposition in ('applied','covered','historical','pending')),
 reason text not null,
 discrepancy bigint,
 before_data jsonb, after_data jsonb not null,
 recorded_at timestamptz not null default now(),
 unique(balance_id,kind,event_key),
 check((kind='snapshot' and amount>=0) or (kind='movement' and amount<>0 and verification_status='verified')),
 check((verification_status='verified' and verified_at is not null) or verification_status<>'verified'),
 check((precision_code='unknown' and observed_from is null and observed_to is null) or
 (precision_code<>'unknown' and observed_from is not null and observed_to is not null and isfinite(observed_from) and isfinite(observed_to) and ((precision_code='instant' and observed_from=observed_to) or (precision_code<>'instant' and observed_from<observed_to))))
);
alter table pogo.resource_balances add constraint resource_basis_fk foreign key(basis_history_id) references pogo.resource_history(id) deferrable initially deferred;
create index resource_history_op on pogo.resource_history(operation_id);
create index resource_history_time on pogo.resource_history(balance_id,observed_to);
create index resource_history_pokemon on pogo.resource_history(pokemon_id) where pokemon_id is not null;
create function pogo.publish_resource_catalog(p_key text,p_actor text,p_entries jsonb) returns jsonb language plpgsql security invoker set search_path='' as $$
declare op pogo.resource_operations%rowtype; entry jsonb; c pogo.resource_catalog%rowtype; payload jsonb; out_rows jsonb:='[]'; answer jsonb;
begin
 if nullif(btrim(p_key),'') is null or p_actor is distinct from '99' or jsonb_typeof(p_entries) is distinct from 'array' or jsonb_array_length(p_entries)=0 then raise exception 'invalid catalog request'; end if;
 if not exists(select 1 from pogo_meta.system_state where singleton and readiness in ('pilot','released')) then raise exception 'writes not released'; end if;
 perform pg_advisory_xact_lock(730030,2);
 payload:=jsonb_build_object('actor',p_actor,'kind','catalog','entries',p_entries);
 select * into op from pogo.resource_operations where operation_key=p_key;
 if found then if op.payload is distinct from payload then raise exception 'idempotency conflict';end if;return op.result;end if;
 insert into pogo.resource_operations(operation_key,actor,kind,payload) values(p_key,p_actor,'catalog',payload) returning * into op;
 for entry in select value from jsonb_array_elements(p_entries) loop
 if jsonb_typeof(entry) is distinct from 'object' or not(entry ?& array['code','resource_type','label','category','unit','scope_key','measure','source_ref']) or exists(select 1 from jsonb_object_keys(entry) k where k not in ('code','resource_type','label','category','unit','scope_key','measure','periodic','source_ref','rules')) or exists(select 1 from jsonb_each(entry) e where e.key not in ('periodic','rules') and jsonb_typeof(e.value)<>'string') or (entry?'periodic' and jsonb_typeof(entry->'periodic')<>'boolean') or (entry?'rules' and jsonb_typeof(entry->'rules')<>'object') then raise exception 'invalid catalog entry';end if;
 insert into pogo.resource_catalog(code,resource_type,label,category,unit,scope_key,measure,periodic,source_ref,rules)
 values(entry->>'code',entry->>'resource_type',entry->>'label',entry->>'category',entry->>'unit',entry->>'scope_key',entry->>'measure',coalesce((entry->>'periodic')::boolean,false),entry->>'source_ref',coalesce(entry->'rules','{}')) returning * into c;
 out_rows:=out_rows||jsonb_build_array(to_jsonb(c));
 end loop;
 answer:=jsonb_build_object('operation_id',op.id,'entries',out_rows);
 update pogo.resource_operations set result=answer,completed_at=clock_timestamp() where id=op.id;
 return answer;
end $$;
create function pogo.write_resource_batch(p_key text,p_actor text,p_entries jsonb) returns jsonb language plpgsql security invoker set search_path='' as $$
declare op pogo.resource_operations%rowtype;c pogo.resource_catalog%rowtype;b pogo.resource_balances%rowtype; e jsonb; payload jsonb; prior jsonb; answer jsonb; rows_out jsonb:='[]'; start_t timestamptz; end_t timestamptz; lo timestamptz; hi timestamptz; vt timestamptz; qty bigint; expected bigint; event_id text; action_kind text; prec text; verify text; disp text; why text; hid uuid; diff bigint; new_row boolean; reconcile boolean; v_before bigint; field text; seen uuid[]:='{}';
begin
 if nullif(btrim(p_key),'') is null or p_actor is null or jsonb_typeof(p_entries) is distinct from 'array' or jsonb_array_length(p_entries)=0 then raise exception 'invalid batch request';end if;
 if not exists(select 1 from pogo_meta.system_state where singleton and readiness in ('pilot','released')) then raise exception 'writes not released';end if;
 perform pg_advisory_xact_lock(730030,2);
 payload:=jsonb_build_object('actor',p_actor,'kind','batch','entries',p_entries);
 select * into op from pogo.resource_operations where operation_key=p_key;
 if found then if op.payload is distinct from payload then raise exception 'idempotency conflict';end if;return op.result;end if;
 if not exists(select 1 from pogo_meta.project_chats where chat_id=p_actor and is_current and status<>'retired') then raise exception 'invalid actor';end if;
 insert into pogo.resource_operations(operation_key,actor,kind,payload) values(p_key,p_actor,'batch',payload) returning * into op;
 for e in select value from jsonb_array_elements(p_entries) loop
 if jsonb_typeof(e) is distinct from 'object' or not(e ?& array['code','expected','event_key','kind','amount','precision','source_type','source_ref','verification_status']) or exists(select 1 from jsonb_object_keys(e) k where k not in ('code','expected','event_key','kind','amount','precision','observed_from','observed_to','source_type','source_ref','verification_status','verified_at','pokemon_id','related_ref','period_start','period_end','reconcile_reason')) or exists(select 1 from jsonb_each(e) j where j.key not in ('expected','amount') and jsonb_typeof(j.value) not in ('string','null')) or jsonb_typeof(e->'amount') is distinct from 'number' or jsonb_typeof(e->'expected') is distinct from 'number' or (e->>'amount')::numeric<>trunc((e->>'amount')::numeric) or (e->>'expected')::numeric<>trunc((e->>'expected')::numeric) then raise exception 'invalid resource entry';end if;
 expected:=(e->>'expected')::bigint;qty:=(e->>'amount')::bigint;event_id:=e->>'event_key';action_kind:=e->>'kind';prec:=e->>'precision';verify:=e->>'verification_status';
 if expected<0 or nullif(btrim(event_id),'') is null or action_kind is null or action_kind not in ('snapshot','movement') or prec is null or prec not in ('instant','day','month','year','interval','unknown') or verify is null or verify not in ('verified','unverified','inferred','conflicting') then raise exception 'invalid entry attributes';end if;
 foreach field in array array['observed_from','observed_to','verified_at','period_start','period_end'] loop
 if e->>field is not null and (e->>field !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([.][0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$') then raise exception 'timestamp requires explicit offset: %',field;end if;
 end loop;
 lo:=(e->>'observed_from')::timestamptz;hi:=(e->>'observed_to')::timestamptz;vt:=(e->>'verified_at')::timestamptz;
 if (prec='unknown' and (lo is not null or hi is not null)) or (prec<>'unknown' and (lo is null or hi is null or lo>hi or (prec='instant' and lo<>hi) or (prec<>'instant' and lo=hi))) then raise exception 'invalid observation interval';end if;
 if lo>clock_timestamp() or (prec='instant' and hi>clock_timestamp()) or vt>clock_timestamp() or (verify='verified' and vt is null) or (verify='verified' and vt<lo) then raise exception 'invalid verification or future observation';end if;
 select * into c from pogo.resource_catalog where code=e->>'code';
 if not found then raise exception 'unknown resource code';end if;
 if c.periodic then
 start_t:=(e->>'period_start')::timestamptz;end_t:=(e->>'period_end')::timestamptz;
 if start_t is null or end_t is null or end_t<=start_t or (lo is not null and (lo<start_t or lo>=end_t or hi>end_t or (prec='instant' and hi=end_t))) then raise exception 'invalid explicit period';end if;
 if exists(select 1 from pogo.resource_balances x where x.resource_id=c.id and x.period_start<>start_t and x.period_start<end_t and x.period_end>start_t) then raise exception 'overlapping resource period';end if;
 else
 if e->>'period_start' is not null or e->>'period_end' is not null then raise exception 'nonperiodic resource';end if;
 start_t:='-infinity';end_t:=null;
 end if;
 if (action_kind='snapshot' and qty<0) or (action_kind='movement' and (qty=0 or verify<>'verified' or c.measure not in ('stock','counter','claimable'))) then raise exception 'invalid movement or quantity';end if;
 reconcile:=nullif(btrim(e->>'reconcile_reason'),'') is not null;
 if reconcile and (action_kind<>'snapshot' or verify<>'verified' or prec<>'instant') then raise exception 'reconciliation requires verified exact snapshot';end if;
 select * into b from pogo.resource_balances where resource_id=c.id and period_start=start_t for update;
 new_row:=not found;
 if new_row then
 if expected<>0 then raise exception 'resource version conflict';end if;
 insert into pogo.resource_balances(resource_id,period_start,period_end) values(c.id,start_t,end_t) returning * into b;
 prior:=null;v_before:=0;
 else
 if b.version<>expected or b.period_end is distinct from end_t then raise exception 'resource version conflict or period mismatch';end if;
 prior:=to_jsonb(b);v_before:=b.version;
 end if;
 if b.id=any(seen) then raise exception 'one entry per resource and period per batch';end if;seen:=array_append(seen,b.id);
 if exists(select 1 from pogo.resource_history where balance_id=b.id and kind=action_kind and event_key=event_id) then raise exception 'resource event already recorded';end if;
 hid:=gen_random_uuid();diff:=null;
 if action_kind='snapshot' then
 if b.quantity is not null and hi is not null and hi<b.basis_from then disp:='historical';why:='older than selected observation';
 elsif verify<>'verified' or prec='unknown' then
 disp:='pending';why:='not a verified, time-bounded observation';
 elsif b.effective_to is not null and lo<=b.effective_to then
 if prec='instant' and lo=b.basis_from and lo=b.effective_to and b.quantity=qty and not b.needs_reconcile then disp:='historical';why:='same value at same observation time';
 elsif hi<b.effective_from then disp:='historical';why:='older than effective balance';
 else disp:='pending';why:='overlapping observation or same-time conflict';end if;
 elsif b.pending_until is not null and lo<=b.pending_until then disp:='pending';why:='snapshot does not follow all unresolved events';
 elsif b.pending_unknown and not reconcile then disp:='pending';why:='unknown-time event requires explicit reconciliation';
 else
 disp:='applied';why:='new verified observation';if b.quantity is not null then diff:=qty-b.quantity;end if;
 b.quantity:=qty;b.basis_history_id:=hid;b.basis_from:=lo;b.basis_to:=hi;b.effective_from:=lo;b.effective_to:=hi;b.needs_reconcile:=false;b.pending_until:=null;b.pending_unknown:=false;
 if reconcile then why:=why||'; explicit reconciliation: '||(e->>'reconcile_reason');end if;
 end if;
 else
 if b.basis_from is not null and hi is not null and hi<b.basis_from then disp:='covered';why:='movement predates selected snapshot; not applied again';
 elsif b.quantity is null or prec<>'instant' or b.needs_reconcile or lo<=b.effective_to then disp:='pending';why:='missing base, uncertain ordering, or unresolved balance';
 else
 if b.quantity::numeric+qty<0 then raise exception 'negative resource balance';end if;
 disp:='applied';why:='confirmed movement after current balance';b.quantity:=b.quantity+qty;b.effective_from:=lo;b.effective_to:=hi;
 end if;
 end if;
 if disp='pending' then b.needs_reconcile:=true;b.pending_until:=greatest(b.pending_until,hi);b.pending_unknown:=b.pending_unknown or hi is null;end if;
 update pogo.resource_balances set quantity=b.quantity,basis_history_id=b.basis_history_id,basis_from=b.basis_from,basis_to=b.basis_to,effective_from=b.effective_from,effective_to=b.effective_to,needs_reconcile=b.needs_reconcile,pending_until=b.pending_until,pending_unknown=b.pending_unknown,version=v_before+1,updated_at=clock_timestamp() where id=b.id returning * into b;
 insert into pogo.resource_history(id,balance_id,operation_id,event_key,kind,amount,observed_from,observed_to,precision_code,source_type,source_ref,verification_status,verified_at,pokemon_id,related_ref,disposition,reason,discrepancy,before_data,after_data)
 values(hid,b.id,op.id,event_id,action_kind,qty,lo,hi,prec,e->>'source_type',e->>'source_ref',verify,vt,(e->>'pokemon_id')::uuid,e->>'related_ref',disp,why,diff,prior,to_jsonb(b));
 rows_out:=rows_out||jsonb_build_array(jsonb_build_object('code',c.code,'balance_id',b.id,'history_id',hid,'quantity',b.quantity,'version',b.version,'disposition',disp,'needs_reconcile',b.needs_reconcile,'discrepancy',diff));
 end loop;
 answer:=jsonb_build_object('operation_id',op.id,'entries',rows_out);
 update pogo.resource_operations set result=answer,completed_at=clock_timestamp() where id=op.id;
 return answer;
end $$;
create function pogo.get_resource_overview() returns jsonb language sql stable security invoker set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('catalog',to_jsonb(c),'balance',case when b.id is null then null else to_jsonb(b) end,'basis_evidence',case when h.id is null then null else jsonb_build_object('source_type',h.source_type,'source_ref',h.source_ref,'verification_status',h.verification_status,'verified_at',h.verified_at,'precision',h.precision_code) end,'current_period',case when not c.periodic then true when b.id is null then null else statement_timestamp()>=b.period_start and statement_timestamp()<b.period_end end) order by c.code,b.period_start desc),'[]'::jsonb)
 from pogo.resource_catalog c left join lateral (select * from pogo.resource_balances x where x.resource_id=c.id order by period_start desc limit 1) b on true left join pogo.resource_history h on h.id=b.basis_history_id;
$$;
create function pogo.guard_resource_write() returns trigger language plpgsql security invoker set search_path='' as $$
declare ctx text;
begin
 get diagnostics ctx=PG_CONTEXT;
 if TG_OP in ('DELETE','TRUNCATE') or (TG_TABLE_NAME in ('resource_catalog','resource_history') and TG_OP<>'INSERT') or not exists(select 1 from regexp_split_to_table(ctx,chr(10)) line where line ~ '^PL/pgSQL function (pogo\.)?(publish_resource_catalog|write_resource_batch)\(text,text,jsonb\) line [0-9]+ at SQL statement$') then raise exception using errcode='P0301',message='direct resource write blocked';end if;
 return null;
end $$;
alter table pogo.resource_catalog enable row level security;
revoke all on pogo.resource_catalog from public,anon,authenticated,service_role,pogo_reader;
grant select on pogo.resource_catalog to pogo_reader;
create policy mobile_reader_select on pogo.resource_catalog for select to pogo_reader using(true);
create trigger guard_resource_write before insert or update or delete or truncate on pogo.resource_catalog for each statement execute function pogo.guard_resource_write();
alter table pogo.resource_balances enable row level security;
revoke all on pogo.resource_balances from public,anon,authenticated,service_role,pogo_reader;
grant select on pogo.resource_balances to pogo_reader;
create policy mobile_reader_select on pogo.resource_balances for select to pogo_reader using(true);
create trigger guard_resource_write before insert or update or delete or truncate on pogo.resource_balances for each statement execute function pogo.guard_resource_write();
alter table pogo.resource_history enable row level security;
revoke all on pogo.resource_history from public,anon,authenticated,service_role,pogo_reader;
grant select on pogo.resource_history to pogo_reader;
create policy mobile_reader_select on pogo.resource_history for select to pogo_reader using(true);
create trigger guard_resource_write before insert or update or delete or truncate on pogo.resource_history for each statement execute function pogo.guard_resource_write();
alter table pogo.resource_operations enable row level security;
revoke all on pogo.resource_operations from public,anon,authenticated,service_role,pogo_reader;
grant select on pogo.resource_operations to pogo_reader;
create policy mobile_reader_select on pogo.resource_operations for select to pogo_reader using(true);
create trigger guard_resource_write before insert or update or delete or truncate on pogo.resource_operations for each statement execute function pogo.guard_resource_write();
revoke all on function pogo.publish_resource_catalog(text,text,jsonb),pogo.write_resource_batch(text,text,jsonb),pogo.get_resource_overview(),pogo.guard_resource_write() from public,anon,authenticated,service_role,pogo_reader;
