-- Hosted pg_net transport tables can have platform-owned PUBLIC grants that the
-- project migration role cannot revoke. Therefore NEVER put credentials there.
-- An HTTP wake-up has no authority/data of its own: it can only consume a private
-- cron-issued window and start the already-authorized, fixed reconciliation job.
create table app.calendar_worker_dispatch (
 singleton boolean primary key default true check(singleton),
 ready_until timestamptz, last_started_at timestamptz
);
alter table app.calendar_worker_dispatch enable row level security;
alter table app.calendar_worker_dispatch force row level security;
revoke all on app.calendar_worker_dispatch from public,anon,authenticated,service_role;

create function public.calendar_worker_wakeup() returns boolean
language plpgsql security definer set search_path='' as $$
begin
 update app.calendar_worker_dispatch set ready_until=null,last_started_at=clock_timestamp()
 where singleton and ready_until>clock_timestamp()
  and (last_started_at is null or last_started_at<clock_timestamp()-interval '2 minutes');
 return found;
end $$;
revoke all on function public.calendar_worker_wakeup() from public,anon,authenticated;
grant execute on function public.calendar_worker_wakeup() to service_role;

create or replace function app.request_external_calendar_worker() returns void
language plpgsql security definer set search_path='' as $$
declare url text;
begin
 delete from vault.secrets where id in(select verifier_secret from app.calendar_oauth_states where expires_at<now());
 delete from app.calendar_oauth_states where expires_at<now();
 select decrypted_secret into url from vault.decrypted_secrets where name='orchestrio.calendar_worker_url';
 if url is null then return; end if;
 insert into app.calendar_worker_dispatch(singleton,ready_until) values(true,clock_timestamp()+interval '1 minute')
 on conflict(singleton) do update set ready_until=excluded.ready_until
 where app.calendar_worker_dispatch.last_started_at is null
  or app.calendar_worker_dispatch.last_started_at<clock_timestamp()-interval '2 minutes';
 if not found then return; end if;
 perform net.http_post(url:=url,headers:=jsonb_build_object('Content-Type','application/json'),body:='{}'::jsonb,timeout_milliseconds:=5000);
end $$;
revoke all on function app.request_external_calendar_worker() from public,anon,authenticated,service_role;
-- This key was never activated/queued on develop. The old dispatcher action now
-- always rejects it; runtime uses the narrow service-only wake-up RPC above.
delete from vault.secrets where name='orchestrio.calendar_worker_key';
