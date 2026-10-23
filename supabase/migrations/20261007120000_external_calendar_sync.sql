-- External integration metadata only. Deliberately NO authoritative-source triggers.
create table public.user_calendar_connections (
 id uuid primary key default gen_random_uuid(), user_id uuid not null unique references auth.users(id),
 provider text not null default 'google' check(provider='google'),
 status text not null default 'disconnected' check(status in ('disconnected','connected','reauthorization_required','degraded','provisioning')),
 account_label text, activities boolean not null default true, decisions boolean not null default true, payments boolean not null default false,
 last_synced_at timestamptz, last_error_code text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table public.user_calendar_connections enable row level security;
alter table public.user_calendar_connections force row level security;
revoke all on public.user_calendar_connections from public,anon,authenticated,service_role;
grant select on public.user_calendar_connections to authenticated;
create policy calendar_connection_owner on public.user_calendar_connections for select to authenticated using(user_id=auth.uid());
-- Audit only this sanitized row, never token references/provider payloads.
create trigger calendar_connection_audit after insert or update on public.user_calendar_connections for each row execute function app.tg_audit_row();
create table app.calendar_credentials (
 connection_id uuid primary key references public.user_calendar_connections(id),
 access_secret uuid not null, refresh_secret uuid not null, expires_at timestamptz not null,
 provider_subject text not null, calendar_id text
);
create table app.calendar_oauth_states (
 state_hash text primary key, user_id uuid not null references auth.users(id), verifier_secret uuid not null,
 expires_at timestamptz not null, used_at timestamptz
);
create table app.external_calendar_jobs (
 id uuid primary key default gen_random_uuid(), connection_id uuid not null references public.user_calendar_connections(id),
 status text not null default 'pending' check(status in ('pending','running','complete','failed','cancelled')),
 attempt integer not null default 0, available_at timestamptz not null default now(),
 lease uuid, lease_until timestamptz, cursor_key text not null default '',
 created_at timestamptz not null default now(), completed_at timestamptz, error_code text
);
create unique index calendar_job_coalesced on app.external_calendar_jobs(connection_id) where status in ('pending','running');
create index calendar_jobs_ready on app.external_calendar_jobs(available_at) where status in ('pending','running');
create table app.external_calendar_event_links (
 connection_id uuid not null references public.user_calendar_connections(id), source_key text not null,
 provider_event_id text not null default replace(gen_random_uuid()::text,'-',''), synced_at timestamptz,
 primary key(connection_id,source_key), unique(connection_id,provider_event_id),
 check(source_key ~ '^(activity:|decision:|payment_schedule:|occurrence:)[0-9a-f-]{36}(:[0-9]{4}-[0-9]{2}-[0-9]{2})?$')
);
create table app.external_calendar_receipts (
 id bigint generated always as identity primary key, job_id uuid, connection_id uuid not null,
 operation text not null, result text not null, attempt integer, created_at timestamptz not null default now()
);
do $$ declare t text; begin
 foreach t in array array['calendar_credentials','calendar_oauth_states','external_calendar_jobs','external_calendar_event_links','external_calendar_receipts'] loop
 execute format('alter table app.%I enable row level security',t);
 execute format('alter table app.%I force row level security',t);
 execute format('revoke all on app.%I from public,anon,authenticated,service_role',t);
 end loop;
end $$;

-- Dedicated NOLOGIN/NOBYPASSRLS owner: normal source SELECT policies apply even
-- when a trusted worker derives another user's projection. The fixed helper reads only; this role cannot log in.
create role orchestrio_calendar_reader nologin nosuperuser nobypassrls inherit;
grant authenticated to orchestrio_calendar_reader;
grant orchestrio_calendar_reader to postgres;
grant usage on schema public,app to orchestrio_calendar_reader;
create function app.calendar_projection_for_user(p_user uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare prior text:=current_setting('request.jwt.claims',true); result jsonb;
begin
 perform set_config('request.jwt.claims',jsonb_build_object('sub',p_user,'role','authenticated')::text,true);
 select coalesce(jsonb_agg(distinct jsonb_build_object(
  'entry_id',e.entry_id,'source_type',e.source_type,'source_id',e.source_id,'project_id',e.project_id,
  'title',e.title,'status',e.status,'start_at',e.start_at,'end_at',e.end_at,'start_date',e.start_date,'end_date',e.end_date,
  'all_day',e.all_day,'activity_id',e.activity_id,'occurrence_date',e.occurrence_date,'timezone',p.timezone
 )), '[]'::jsonb) into result
 from public.projects p
 cross join lateral generate_series(0,1) chunk
 cross join lateral public.get_project_calendar(p.id,
  (statement_timestamp() at time zone p.timezone)::date-30+chunk*60,
  (statement_timestamp() at time zone p.timezone)::date-30+(chunk+1)*60) e
 where p.deleted_at is null;
 perform set_config('request.jwt.claims',coalesce(prior,''),true);
 if jsonb_array_length(result)>500 then raise exception 'calendar_capacity' using errcode='54000'; end if;
 return result;
exception when others then
 perform set_config('request.jwt.claims',coalesce(prior,''),true); raise;
end $$;
grant create on schema app to orchestrio_calendar_reader;
alter function app.calendar_projection_for_user(uuid) owner to orchestrio_calendar_reader;
revoke create on schema app from orchestrio_calendar_reader;
revoke all on function app.calendar_projection_for_user(uuid) from public,anon,authenticated,service_role;
grant execute on function app.calendar_projection_for_user(uuid) to postgres;

create function app.queue_calendar(p_connection uuid) returns void language sql security definer set search_path='' as $$
 insert into app.external_calendar_jobs(connection_id)
 select id from public.user_calendar_connections where id=p_connection and status='connected'
 on conflict(connection_id) where status in ('pending','running') do nothing;
$$;
revoke all on function app.queue_calendar(uuid) from public,anon,authenticated,service_role;
create function public.request_calendar_sync(p_activities boolean default null,p_decisions boolean default null,p_payments boolean default null)
returns void language plpgsql security definer set search_path='' as $$
declare c public.user_calendar_connections%rowtype;
begin
 select * into c from public.user_calendar_connections where user_id=auth.uid() for update;
 if not found or c.status<>'connected' then raise exception 'Calendar unavailable' using errcode='42501'; end if;
 update public.user_calendar_connections set activities=coalesce(p_activities,activities),decisions=coalesce(p_decisions,decisions),payments=coalesce(p_payments,payments),updated_at=now() where id=c.id;
 perform app.queue_calendar(c.id);
 insert into app.external_calendar_receipts(connection_id,operation,result) values(c.id,'sync_requested','queued');
end $$;
revoke all on function public.request_calendar_sync(boolean,boolean,boolean) from public,anon,service_role;
grant execute on function public.request_calendar_sync(boolean,boolean,boolean) to authenticated;

-- Static trusted backend dispatcher. Never granted to browser roles. Secrets may
-- be returned only to the authenticated service backend, never owner Settings.
create function public.calendar_backend(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare c public.user_calendar_connections%rowtype; k app.calendar_credentials%rowtype;
 j app.external_calendar_jobs%rowtype; st app.calendar_oauth_states%rowtype;
 result jsonb; a uuid; r uuid; v text; owner_id uuid; err text;
begin
 if p_action='authorize_worker' then
  return to_jsonb(exists(select 1 from vault.decrypted_secrets where name='orchestrio.calendar_worker_key' and decrypted_secret=p_data->>'key'));
 elsif p_action='state_create' then
  owner_id:=(p_data->>'user_id')::uuid;
  perform 1 from public.users where id=owner_id for update;
  delete from vault.secrets where id in(select verifier_secret from app.calendar_oauth_states where user_id=owner_id or expires_at<now());
  delete from app.calendar_oauth_states where user_id=owner_id or expires_at<now();
  a:=vault.create_secret(p_data->>'verifier');
  insert into app.calendar_oauth_states values(p_data->>'hash',owner_id,a,now()+interval '10 minutes',null);
  return '{}'::jsonb;
 elsif p_action='state_consume' then
  select * into st from app.calendar_oauth_states where state_hash=p_data->>'hash' and used_at is null for update;
  if not found then raise exception 'Invalid OAuth state' using errcode='42501'; end if;
  select decrypted_secret into v from vault.decrypted_secrets where id=st.verifier_secret;
  delete from vault.secrets where id=st.verifier_secret;
  -- Expiry consumes the state and erases its verifier without raising/rolling back.
  if st.expires_at<=now() then delete from app.calendar_oauth_states where state_hash=st.state_hash; return null; end if;
  update app.calendar_oauth_states set used_at=now() where state_hash=st.state_hash;
  return jsonb_build_object('user_id',st.user_id,'verifier',v);
 elsif p_action='connect' then
  owner_id:=(p_data->>'user_id')::uuid;
  perform 1 from public.users where id=owner_id for update;
  delete from app.calendar_oauth_states where state_hash=p_data->>'hash' and user_id=owner_id and used_at is not null and expires_at>now() returning * into st;
  if not found then raise exception 'Invalid OAuth state' using errcode='42501'; end if;
  insert into public.user_calendar_connections(user_id) values(owner_id) on conflict(user_id) do nothing;
  select * into strict c from public.user_calendar_connections where user_id=owner_id for update;
  select * into k from app.calendar_credentials where connection_id=c.id;
  if c.status='provisioning' or c.last_error_code='provisioning_uncertain' then raise exception 'Disconnect and check Google Calendar before reconnecting'; end if;
  if c.last_error_code='calendar_missing' then
   update app.calendar_credentials set calendar_id=null where connection_id=c.id;
   delete from app.external_calendar_event_links where connection_id=c.id;
   k.calendar_id:=null;
  end if;
  if k.provider_subject is not null and k.provider_subject<>p_data->>'subject' then raise exception 'Disconnect before changing account'; end if;
  if nullif(p_data->>'refresh_token','') is null then raise exception 'Offline consent required'; end if;
  a:=vault.create_secret(p_data->>'access_token'); r:=vault.create_secret(p_data->>'refresh_token');
  delete from vault.secrets where id in(k.access_secret,k.refresh_secret);
  insert into app.calendar_credentials(connection_id,access_secret,refresh_secret,expires_at,provider_subject,calendar_id)
  values(c.id,a,r,(p_data->>'expires_at')::timestamptz,p_data->>'subject',k.calendar_id)
  on conflict(connection_id) do update set access_secret=excluded.access_secret,refresh_secret=excluded.refresh_secret,expires_at=excluded.expires_at,calendar_id=excluded.calendar_id;
  update public.user_calendar_connections set status='connected',account_label=left(p_data->>'email',254),last_error_code=null,updated_at=now() where id=c.id;
  update app.external_calendar_jobs set status='cancelled',lease=null where connection_id=c.id and status in ('pending','running');
  perform app.queue_calendar(c.id);
  return jsonb_build_object('id',c.id);
 elsif p_action='disconnect' then
  owner_id:=(p_data->>'user_id')::uuid;
  perform 1 from public.users where id=owner_id for update;
  delete from vault.secrets where id in(select verifier_secret from app.calendar_oauth_states where user_id=owner_id);
  delete from app.calendar_oauth_states where user_id=owner_id;
  select * into c from public.user_calendar_connections where user_id=(p_data->>'user_id')::uuid for update;
  if not found then return '{}'::jsonb; end if;
  select * into k from app.calendar_credentials where connection_id=c.id;
  select jsonb_build_object('id',c.id,'calendar_id',k.calendar_id,'access_token',(select decrypted_secret from vault.decrypted_secrets where id=k.access_secret),'refresh_token',(select decrypted_secret from vault.decrypted_secrets where id=k.refresh_secret)) into result;
  delete from vault.secrets where id in(k.access_secret,k.refresh_secret) or id in(select verifier_secret from app.calendar_oauth_states where user_id=c.user_id);
  delete from app.calendar_oauth_states where user_id=c.user_id;
  delete from app.calendar_credentials where connection_id=c.id;
  update app.external_calendar_jobs set status='cancelled',lease=null,completed_at=now() where connection_id=c.id and status in ('pending','running');
  delete from app.external_calendar_event_links where connection_id=c.id;
  update public.user_calendar_connections set status='disconnected',account_label=null,last_error_code=null,updated_at=now() where id=c.id;
  return result;
 elsif p_action='cleanup_warning' then
  update public.user_calendar_connections set last_error_code='cleanup_required' where id=(p_data->>'id')::uuid and status='disconnected'; return '{}';
 elsif p_action='claim' then
  -- Expired leases count toward the same finite retry budget, including crashes.
  update app.external_calendar_jobs q set status=case when q.attempt>=4 then 'failed' else 'pending' end,
   attempt=q.attempt+1,lease=null,error_code='transient',available_at=now()+interval '60 seconds'
   where q.status='running' and q.lease_until<now();
  update public.user_calendar_connections cc set status='degraded',last_error_code='provisioning_uncertain'
   where cc.status='provisioning' and not exists(select 1 from app.external_calendar_jobs q where q.connection_id=cc.id and q.status='running');
  -- Isolated scheduler; not called from source, event, notification or settlement writes.
  perform app.queue_calendar(cc.id) from public.user_calendar_connections cc
   where cc.status='connected' and (cc.last_synced_at is null or cc.last_synced_at<now()-interval '15 minutes')
   and not exists(select 1 from app.external_calendar_jobs f where f.connection_id=cc.id and f.status='failed' and f.created_at>coalesce(cc.last_synced_at,'-infinity'::timestamptz));
  select q.* into j from app.external_calendar_jobs q join public.user_calendar_connections cc on cc.id=q.connection_id
   where cc.status='connected' and ((q.status='pending' and q.available_at<=now()) or(q.status='running' and q.lease_until<now()))
   order by q.available_at,q.id limit 1 for update of q skip locked;
  if not found then return null; end if;
  update app.external_calendar_jobs set status='running',lease=gen_random_uuid(),lease_until=now()+interval '5 minutes' where id=j.id returning * into j;
  return to_jsonb(j);
 end if;
 -- Every subsequent worker operation requires an unexpired lease and live connection.
 select * into j from app.external_calendar_jobs where id=(p_data->>'job_id')::uuid;
 if not found then raise exception 'Invalid sync lease' using errcode='42501'; end if;
 select * into strict c from public.user_calendar_connections where id=j.connection_id for update;
 select * into j from app.external_calendar_jobs where id=(p_data->>'job_id')::uuid and lease=(p_data->>'lease')::uuid and status='running' and lease_until>now() for update;
 if not found then raise exception 'Invalid sync lease' using errcode='42501'; end if;
 if c.status not in ('connected','provisioning') then raise exception 'Connection disabled' using errcode='42501'; end if;
 select * into strict k from app.calendar_credentials where connection_id=c.id;
 case p_action
 when 'bundle' then
  return jsonb_build_object('connection',to_jsonb(c),'calendar_id',k.calendar_id,'access_token',(select decrypted_secret from vault.decrypted_secrets where id=k.access_secret),'refresh_token',(select decrypted_secret from vault.decrypted_secrets where id=k.refresh_secret),'expires_at',k.expires_at);
 when 'token' then
  perform vault.update_secret(k.access_secret,p_data->>'access_token');
  if nullif(p_data->>'refresh_token','') is not null then perform vault.update_secret(k.refresh_secret,p_data->>'refresh_token'); end if;
  update app.calendar_credentials set expires_at=(p_data->>'expires_at')::timestamptz where connection_id=c.id;
 when 'provision_begin' then
  if k.calendar_id is not null or c.status<>'connected' then raise exception 'Calendar already provisioning'; end if;
  update public.user_calendar_connections set status='provisioning',last_error_code='provisioning_uncertain' where id=c.id;
 when 'provision_finish' then
  update app.calendar_credentials set calendar_id=p_data->>'calendar_id' where connection_id=c.id;
  update public.user_calendar_connections set status='connected',last_error_code=null where id=c.id;
 when 'projection' then
  result:=app.calendar_projection_for_user(c.user_id);
  return coalesce((select jsonb_agg(e) from jsonb_array_elements(result) e where
   (c.activities and e->>'source_type' in ('activity','activity_occurrence')) or
   (c.decisions and e->>'source_type'='decision') or(c.payments and e->>'source_type'='payment_schedule')),'[]'::jsonb);
 when 'links' then
  return coalesce((select jsonb_agg(to_jsonb(l)) from app.external_calendar_event_links l where connection_id=c.id),'[]'::jsonb);
 when 'reserve' then
  insert into app.external_calendar_event_links(connection_id,source_key) values(c.id,p_data->>'source_key') on conflict do nothing;
  return (select to_jsonb(l) from app.external_calendar_event_links l where connection_id=c.id and source_key=p_data->>'source_key');
 when 'rotate' then
  update app.external_calendar_event_links set provider_event_id=replace(gen_random_uuid()::text,'-',''),synced_at=null where connection_id=c.id and source_key=p_data->>'source_key';
 when 'synced' then
  update app.external_calendar_event_links set synced_at=now() where connection_id=c.id and source_key=p_data->>'source_key';
  insert into app.external_calendar_receipts(job_id,connection_id,operation,result,attempt) values(j.id,c.id,'upsert','ok',j.attempt);
 when 'deleted' then
  delete from app.external_calendar_event_links where connection_id=c.id and source_key=p_data->>'source_key';
  insert into app.external_calendar_receipts(job_id,connection_id,operation,result,attempt) values(j.id,c.id,'delete','ok',j.attempt);
 when 'checkpoint' then
  update app.external_calendar_jobs set cursor_key=p_data->>'cursor_key' where id=j.id;
 when 'yield' then
  update app.external_calendar_jobs set status='pending',lease=null,cursor_key=coalesce(p_data->>'cursor_key',cursor_key),available_at=now() where id=j.id;
 when 'finish' then
  update app.external_calendar_jobs set status='complete',completed_at=now(),lease=null where id=j.id;
  update public.user_calendar_connections set last_synced_at=now(),last_error_code=null where id=c.id;
 when 'fail' then
  err:=case when p_data->>'code' in ('auth','quota','transient','permanent','calendar_missing','capacity','provisioning_uncertain') then p_data->>'code' else 'transient' end;
  update app.external_calendar_jobs set attempt=attempt+1,error_code=err,lease=null,
   status=case when err in ('auth','permanent','calendar_missing','capacity','provisioning_uncertain') or attempt>=4 then 'failed' else 'pending' end,
   available_at=now()+make_interval(secs=>least(14400,60*power(2,attempt)::integer)) where id=j.id;
  update public.user_calendar_connections set last_error_code=err,status=case when err='auth' then 'reauthorization_required' when err in ('calendar_missing','provisioning_uncertain') then 'degraded' else status end where id=c.id;
  insert into app.external_calendar_receipts(job_id,connection_id,operation,result,attempt) values(j.id,c.id,'sync',err,j.attempt+1);
 else raise exception 'Unknown calendar backend action';
 end case;
 return '{}'::jsonb;
end $$;
revoke all on function public.calendar_backend(text,jsonb) from public,anon,authenticated;
grant execute on function public.calendar_backend(text,jsonb) to service_role;

create extension if not exists pg_net with schema extensions;
select vault.create_secret(encode(extensions.gen_random_bytes(32),'hex'),'orchestrio.calendar_worker_key','Private scheduler authentication');
create function app.request_external_calendar_worker() returns void language plpgsql security definer set search_path='' as $$
declare url text; k text;
begin
 delete from vault.secrets where id in(select verifier_secret from app.calendar_oauth_states where expires_at<now());
 delete from app.calendar_oauth_states where expires_at<now();
 select decrypted_secret into url from vault.decrypted_secrets where name='orchestrio.calendar_worker_url';
 select decrypted_secret into k from vault.decrypted_secrets where name='orchestrio.calendar_worker_key';
 if url is null or k is null then return; end if;
 perform net.http_post(url:=url,headers:=jsonb_build_object('Authorization','Bearer '||k,'Content-Type','application/json'),body:='{}'::jsonb,timeout_milliseconds:=5000);
end $$;
revoke all on function app.request_external_calendar_worker() from public,anon,authenticated,service_role;
select cron.schedule('orchestrio-external-calendar','*/15 * * * *','select app.request_external_calendar_worker()');
