-- pgTAP: the Health system (docs/BUSINESS_RULES.md §9) — findings are recomputed from
-- live data (HLT-G), and dismiss/snooze/reactivate only records dismissal state
-- (HLT-F), never the findings themselves. Blockers stay non-dismissible even via a
-- direct table write.
begin;
create extension if not exists pgtap with schema extensions;
select plan(15);

create function pg_temp.login(p_uid uuid, p_email text) returns void language plpgsql as $$
begin
  perform set_config('role','authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub',p_uid,'email',p_email,'role','authenticated')::text, true);
end $$;
create function pg_temp.logout() returns void language plpgsql as $$
begin perform set_config('request.jwt.claims','', true); perform set_config('role','postgres', true); end $$;
create function pg_temp.wc(sql text) returns int language plpgsql as $$
declare n int; begin execute sql; get diagnostics n = row_count; return n; end $$;
-- stash a named integer across statements without relying on psql's \gset
create table pg_temp.stash (k text primary key, v int);
create function pg_temp.stash_set(p_k text, p_v int) returns void language plpgsql as $$
begin insert into pg_temp.stash values (p_k, p_v) on conflict (k) do update set v = excluded.v; end $$;
create function pg_temp.stash_get(p_k text) returns int language sql as $$
  select v from pg_temp.stash where k = p_k;
$$;

insert into auth.users (instance_id,id,aud,role,email,raw_app_meta_data,raw_user_meta_data,
  created_at,updated_at,confirmation_token,email_change,email_change_token_new,recovery_token)
values
 ('00000000-0000-0000-0000-000000000000','a6000000-0000-0000-0000-00000000006a','authenticated','authenticated','a6@t.co','{}','{"display_name":"Organizer A6"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','b6000000-0000-0000-0000-00000000006b','authenticated','authenticated','b6@t.co','{}','{"display_name":"Member B6"}',now(),now(),'','','','');

insert into public.projects (id,name,status,timezone,currency)
values ('66660000-0000-0000-0000-000000000001','Health Test Trip','active','UTC','GBP');
insert into public.project_members (id,project_id,user_id,display_name,email,role,status)
values
 ('6a000000-0000-0000-0000-00000000006a','66660000-0000-0000-0000-000000000001','a6000000-0000-0000-0000-00000000006a','Organizer A6','a6@t.co','organizer','active'),
 ('6b000000-0000-0000-0000-00000000006b','66660000-0000-0000-0000-000000000001','b6000000-0000-0000-0000-00000000006b','Member B6','b6@t.co','member','active');
update public.projects set created_by='6a000000-0000-0000-0000-00000000006a' where id='66660000-0000-0000-0000-000000000001';

-- Boat: researching, no owner -> HLT-1 missing_owner (warning, dismissible)
insert into public.commitments (id,project_id,title,kind,status)
values ('6c000000-0000-0000-0000-00000000006c','66660000-0000-0000-0000-000000000001','Boat','experience','researching');

-- Flights: booked, owned, booking confirmed -> avoids tripping HLT-1/HLT-5 itself
insert into public.commitments (id,project_id,title,kind,status,owner_member_id,booking_reference,booking_confirmed,confirmed_cost_minor)
values ('6d000000-0000-0000-0000-00000000006d','66660000-0000-0000-0000-000000000001','Flights','transport','booked','6a000000-0000-0000-0000-00000000006a','ABC123',true,10000);
-- overdue scheduled payment on it -> HLT-3 payment_overdue (blocker, NOT dismissible)
insert into public.payments (id,project_id,commitment_id,type,amount_minor,status,due_on)
values ('6e000000-0000-0000-0000-00000000006e','66660000-0000-0000-0000-000000000001','6d000000-0000-0000-0000-00000000006d','deposit',5000,'scheduled',current_date - 3);

select pg_temp.login('b6000000-0000-0000-0000-00000000006b','b6@t.co');

-- ===== findings are derived, present, and correctly classified =====
select is(
  (select dismissed from public.get_project_health('66660000-0000-0000-0000-000000000001') where code='missing_owner' and subject_id='6c000000-0000-0000-0000-00000000006c'),
  false, 'HEALTH: missing_owner finding is present and not dismissed initially');
select is(
  (select dismissible from public.get_project_health('66660000-0000-0000-0000-000000000001') where code='missing_owner' and subject_id='6c000000-0000-0000-0000-00000000006c'),
  true, 'HEALTH: missing_owner is dismissible (warning)');
select is(
  (select severity from public.get_project_health('66660000-0000-0000-0000-000000000001') where code='payment_overdue' and subject_id='6e000000-0000-0000-0000-00000000006e'),
  'blocker', 'HEALTH: overdue payment is a blocker');
select is(
  (select dismissible from public.get_project_health('66660000-0000-0000-0000-000000000001') where code='payment_overdue' and subject_id='6e000000-0000-0000-0000-00000000006e'),
  false, 'HEALTH: overdue payment is NOT dismissible');

select pg_temp.stash_set('before_attention', attention_count) from public.get_project_health_summary('66660000-0000-0000-0000-000000000001');
select ok(pg_temp.stash_get('before_attention') >= 2, 'HEALTH: summary counts at least the two seeded findings as needing attention');

-- ===== dismiss a warning =====
select is(pg_temp.wc($$insert into public.finding_dismissals (project_id,code,subject_type,subject_id,state)
  values ('66660000-0000-0000-0000-000000000001','missing_owner','commitment','6c000000-0000-0000-0000-00000000006c','dismissed')$$),
  1, 'DISMISS: member can dismiss a warning finding');
select is(
  (select dismissed from public.get_project_health('66660000-0000-0000-0000-000000000001') where code='missing_owner' and subject_id='6c000000-0000-0000-0000-00000000006c'),
  true, 'DISMISS: the finding now reads as dismissed');

select pg_temp.stash_set('after_dismiss_attention', attention_count) from public.get_project_health_summary('66660000-0000-0000-0000-000000000001');
select is(pg_temp.stash_get('after_dismiss_attention'), pg_temp.stash_get('before_attention') - 1, 'DISMISS: attention_count drops by exactly one');

-- ===== blockers cannot be dismissed, even by a direct write =====
select throws_ok($$insert into public.finding_dismissals (project_id,code,subject_type,subject_id,state)
  values ('66660000-0000-0000-0000-000000000001','payment_overdue','payment','6e000000-0000-0000-0000-00000000006e','dismissed')$$,
  'P0001', null, 'DISMISS: a blocker finding cannot be dismissed');

-- ===== snooze (upsert to snoozed with a future date) =====
select is(pg_temp.wc($$update public.finding_dismissals set state='snoozed', snoozed_until=current_date+7
  where project_id='66660000-0000-0000-0000-000000000001' and code='missing_owner' and subject_id='6c000000-0000-0000-0000-00000000006c'$$),
  1, 'SNOOZE: member can convert a dismissal to a snooze');
select is(
  (select dismissed from public.get_project_health('66660000-0000-0000-0000-000000000001') where code='missing_owner' and subject_id='6c000000-0000-0000-0000-00000000006c'),
  true, 'SNOOZE: still reads as dismissed while the snooze is in the future');

-- ===== reactivate (delete the dismissal row) =====
select is(pg_temp.wc($$delete from public.finding_dismissals
  where project_id='66660000-0000-0000-0000-000000000001' and code='missing_owner' and subject_id='6c000000-0000-0000-0000-00000000006c'$$),
  1, 'REACTIVATE: member can remove a dismissal');
select is(
  (select dismissed from public.get_project_health('66660000-0000-0000-0000-000000000001') where code='missing_owner' and subject_id='6c000000-0000-0000-0000-00000000006c'),
  false, 'REACTIVATE: the finding is visible again (VAL-43)');

select pg_temp.stash_set('after_reactivate_attention', attention_count) from public.get_project_health_summary('66660000-0000-0000-0000-000000000001');
select is(pg_temp.stash_get('after_reactivate_attention'), pg_temp.stash_get('before_attention'), 'REACTIVATE: attention_count is back to its original value');

-- ===== cross-project isolation on dismissals =====
select pg_temp.logout();
insert into auth.users (instance_id,id,aud,role,email,raw_app_meta_data,raw_user_meta_data,
  created_at,updated_at,confirmation_token,email_change,email_change_token_new,recovery_token)
values ('00000000-0000-0000-0000-000000000000','c6000000-0000-0000-0000-00000000006c','authenticated','authenticated','c6@t.co','{}','{"display_name":"Outsider C6"}',now(),now(),'','','','');
select pg_temp.login('c6000000-0000-0000-0000-00000000006c','c6@t.co');
select throws_ok($$insert into public.finding_dismissals (project_id,code,subject_type,subject_id,state)
  values ('66660000-0000-0000-0000-000000000001','missing_owner','commitment','6c000000-0000-0000-0000-00000000006c','dismissed')$$,
  '42501', null, 'ISOLATION: a non-member cannot dismiss a finding in this project');
select pg_temp.logout();

select * from finish();
rollback;
