-- pgTAP: the CRUD surfaces wired up in the frontend this pass — projects, members,
-- commitments (+participants), payments, tasks, milestones. Verifies persistence,
-- RLS enforcement, and the status-transition/guard triggers the UI relies on.
begin;
create extension if not exists pgtap with schema extensions;
select plan(40);

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

insert into auth.users (instance_id,id,aud,role,email,raw_app_meta_data,raw_user_meta_data,
  created_at,updated_at,confirmation_token,email_change,email_change_token_new,recovery_token)
values
 ('00000000-0000-0000-0000-000000000000','a5000000-0000-0000-0000-00000000005a','authenticated','authenticated','a5@t.co','{}','{"display_name":"Organizer A"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','b5000000-0000-0000-0000-00000000005b','authenticated','authenticated','b5@t.co','{}','{"display_name":"Member B"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','c5000000-0000-0000-0000-00000000005c','authenticated','authenticated','c5@t.co','{}','{"display_name":"Viewer C"}',now(),now(),'','','','');

insert into public.projects (id,name,status,timezone,currency)
values ('55550000-0000-0000-0000-000000000001','CRUD Test Trip','active','UTC','GBP');
insert into public.project_members (id,project_id,user_id,display_name,email,role,status)
values
 ('5a000000-0000-0000-0000-00000000005a','55550000-0000-0000-0000-000000000001','a5000000-0000-0000-0000-00000000005a','Organizer A','a5@t.co','organizer','active'),
 ('5b000000-0000-0000-0000-00000000005b','55550000-0000-0000-0000-000000000001','b5000000-0000-0000-0000-00000000005b','Member B','b5@t.co','member','active'),
 ('5c000000-0000-0000-0000-00000000005c','55550000-0000-0000-0000-000000000001','c5000000-0000-0000-0000-00000000005c','Viewer C','c5@t.co','viewer','active');
update public.projects set created_by='5a000000-0000-0000-0000-00000000005a' where id='55550000-0000-0000-0000-000000000001';

-- =====================================================================
-- PROJECTS: update, archive/unarchive, member-cannot-rename
-- =====================================================================
select pg_temp.login('a5000000-0000-0000-0000-00000000005a','a5@t.co');
select is(pg_temp.wc($$update public.projects set name='CRUD Test Trip (renamed)' where id='55550000-0000-0000-0000-000000000001'$$),
  1, 'PROJECT: organizer can rename');
select is(pg_temp.wc($$update public.projects set status='archived' where id='55550000-0000-0000-0000-000000000001'$$),
  1, 'PROJECT: organizer can archive');
select is(pg_temp.wc($$update public.projects set status='active' where id='55550000-0000-0000-0000-000000000001'$$),
  1, 'PROJECT: organizer can unarchive');
select pg_temp.logout();

select pg_temp.login('b5000000-0000-0000-0000-00000000005b','b5@t.co');
select is(pg_temp.wc($$update public.projects set name='hacked' where id='55550000-0000-0000-0000-000000000001'$$),
  0, 'PROJECT: member cannot rename (organizer-only)');
select pg_temp.logout();

-- =====================================================================
-- MEMBERS: role change, self-escalation blocked, last-organizer guard, removal
-- =====================================================================
select pg_temp.login('a5000000-0000-0000-0000-00000000005a','a5@t.co');
select is(pg_temp.wc($$update public.project_members set role='organizer' where id='5b000000-0000-0000-0000-00000000005b'$$),
  1, 'MEMBER: organizer can promote B to organizer');
select is(pg_temp.wc($$update public.project_members set role='member' where id='5a000000-0000-0000-0000-00000000005a'$$),
  1, 'MEMBER: A can demote self now that B is also organizer');
select pg_temp.logout();

select pg_temp.login('c5000000-0000-0000-0000-00000000005c','c5@t.co');
select throws_ok($$update public.project_members set role='organizer' where id='5c000000-0000-0000-0000-00000000005c'$$,
  'P0001', null, 'MEMBER: viewer cannot self-escalate to organizer');
select pg_temp.logout();

select pg_temp.login('b5000000-0000-0000-0000-00000000005b','b5@t.co');
select throws_ok($$update public.project_members set role='member' where id='5b000000-0000-0000-0000-00000000005b'$$,
  'P0001', null, 'MEMBER: last organizer cannot demote self');
select is(pg_temp.wc($$update public.project_members set status='removed' where id='5c000000-0000-0000-0000-00000000005c'$$),
  1, 'MEMBER: organizer can remove a member');
select pg_temp.logout();

-- restore C as active member (viewer) for the commitment/participant tests below
select pg_temp.login('b5000000-0000-0000-0000-00000000005b','b5@t.co');
select is(pg_temp.wc($$update public.project_members set status='active' where id='5c000000-0000-0000-0000-00000000005c'$$),
  1, 'MEMBER: organizer can reinstate a removed member');
select pg_temp.logout();

-- =====================================================================
-- COMMITMENTS: create, update, status transitions, illegal jump, participants
-- =====================================================================
select pg_temp.login('b5000000-0000-0000-0000-00000000005b','b5@t.co');
insert into public.commitments (id,project_id,title,kind,status)
values ('5d000000-0000-0000-0000-00000000005d','55550000-0000-0000-0000-000000000001','Boat trip','experience','idea');
select is((select count(*)::int from public.commitments where id='5d000000-0000-0000-0000-00000000005d'), 1,
  'COMMITMENT: organizer/member role can create');
select is(pg_temp.wc($$update public.commitments set title='Boat trip (updated)' where id='5d000000-0000-0000-0000-00000000005d'$$),
  1, 'COMMITMENT: organizer/member role can edit');
select is(pg_temp.wc($$update public.commitments set status='researching' where id='5d000000-0000-0000-0000-00000000005d'$$),
  1, 'COMMITMENT: idea -> researching is legal');
select is(pg_temp.wc($$update public.commitments set status='confirmed' where id='5d000000-0000-0000-0000-00000000005d'$$),
  1, 'COMMITMENT: researching -> confirmed is legal');
select is(pg_temp.wc($$update public.commitments set status='booked' where id='5d000000-0000-0000-0000-00000000005d'$$),
  1, 'COMMITMENT: confirmed -> booked is legal');
select throws_ok($$update public.commitments set status='idea' where id='5d000000-0000-0000-0000-00000000005d'$$,
  'P0001', null, 'COMMITMENT: booked -> idea is illegal (must go through researching/confirmed)');

insert into public.commitment_participants (project_id,commitment_id,member_id)
values ('55550000-0000-0000-0000-000000000001','5d000000-0000-0000-0000-00000000005d','5b000000-0000-0000-0000-00000000005b');
select is((select count(*)::int from public.commitment_participants where commitment_id='5d000000-0000-0000-0000-00000000005d'),
  1, 'PARTICIPANT: organizer/member role can add a participant');
select pg_temp.logout();

select pg_temp.login('c5000000-0000-0000-0000-00000000005c','c5@t.co');
select throws_ok($$insert into public.commitment_participants (project_id,commitment_id,member_id)
  values ('55550000-0000-0000-0000-000000000001','5d000000-0000-0000-0000-00000000005d','5c000000-0000-0000-0000-00000000005c')$$,
  '42501', null, 'PARTICIPANT: viewer cannot add participants (including self)');
select throws_ok($$insert into public.commitments (project_id,title,kind,status)
  values ('55550000-0000-0000-0000-000000000001','viewer activity','other','idea')$$,
  '42501', null, 'COMMITMENT: viewer cannot create');
select pg_temp.logout();

-- =====================================================================
-- PAYMENTS: create, mark paid (ever_paid latch), future paid_on rejected,
-- paid payment cannot be soft-deleted, viewer cannot create
-- =====================================================================
select pg_temp.login('a5000000-0000-0000-0000-00000000005a','a5@t.co');
insert into public.payments (id,project_id,commitment_id,type,amount_minor,status,due_on)
values ('5e000000-0000-0000-0000-00000000005e','55550000-0000-0000-0000-000000000001','5d000000-0000-0000-0000-00000000005d','deposit',5000,'scheduled',current_date);
select is((select count(*)::int from public.payments where id='5e000000-0000-0000-0000-00000000005e'), 1,
  'PAYMENT: organizer can schedule a payment');
select throws_ok($$update public.payments set status='paid', paid_on=current_date+1 where id='5e000000-0000-0000-0000-00000000005e'$$,
  'P0001', null, 'PAYMENT: paid_on in the future is rejected');
select is(pg_temp.wc($$update public.payments set status='paid', paid_on=current_date where id='5e000000-0000-0000-0000-00000000005e'$$),
  1, 'PAYMENT: mark paid succeeds with a valid paid_on');
select is((select ever_paid from public.payments where id='5e000000-0000-0000-0000-00000000005e'), true,
  'PAYMENT: ever_paid latches true once paid');
select throws_ok($$update public.payments set deleted_at=now() where id='5e000000-0000-0000-0000-00000000005e'$$,
  'P0001', null, 'PAYMENT: a payment that has ever been paid cannot be soft-deleted');
select is(pg_temp.wc($$update public.commitments set deleted_at=now() where id='5d000000-0000-0000-0000-00000000005d'$$),
  1, 'COMMITMENT: organizer can soft-delete an activity');
select is((select count(*)::int from public.commitments where id='5d000000-0000-0000-0000-00000000005d'), 0,
  'COMMITMENT: soft-deleted activity is excluded from normal reads');
select is((select count(*)::int from public.payments where id='5e000000-0000-0000-0000-00000000005e'), 1,
  'COMMITMENT: soft deletion preserves paid payment history');
select pg_temp.logout();

select pg_temp.login('c5000000-0000-0000-0000-00000000005c','c5@t.co');
select throws_ok($$insert into public.payments (project_id,commitment_id,type,amount_minor)
  values ('55550000-0000-0000-0000-000000000001','5d000000-0000-0000-0000-00000000005d','deposit',100)$$,
  '42501', null, 'PAYMENT: viewer cannot create a payment');
select pg_temp.logout();

-- =====================================================================
-- TASKS: create+assign, illegal assignee, complete/reopen (completed_at),
-- delete by non-owner blocked, delete by assignee allowed
-- =====================================================================
select pg_temp.login('a5000000-0000-0000-0000-00000000005a','a5@t.co');
select throws_ok($$insert into public.tasks (project_id,title,assignee_member_id)
  values ('55550000-0000-0000-0000-000000000001','Book boat','5c000000-0000-0000-0000-00000000005c')$$,
  'P0001', null, 'TASK: assigning to a viewer is rejected');

insert into public.tasks (id,project_id,title,assignee_member_id)
values ('5f000000-0000-0000-0000-00000000005f','55550000-0000-0000-0000-000000000001','Book boat','5b000000-0000-0000-0000-00000000005b');
select is((select count(*)::int from public.tasks where id='5f000000-0000-0000-0000-00000000005f'), 1,
  'TASK: organizer/member role can create and assign to another member');
select pg_temp.logout();

select pg_temp.login('b5000000-0000-0000-0000-00000000005b','b5@t.co');
select is(pg_temp.wc($$update public.tasks set status='done' where id='5f000000-0000-0000-0000-00000000005f'$$),
  1, 'TASK: assignee can mark done');
select is((select completed_at is not null from public.tasks where id='5f000000-0000-0000-0000-00000000005f'), true,
  'TASK: completed_at is stamped on done');
select is(pg_temp.wc($$update public.tasks set status='open' where id='5f000000-0000-0000-0000-00000000005f'$$),
  1, 'TASK: assignee can reopen');
select is((select completed_at from public.tasks where id='5f000000-0000-0000-0000-00000000005f'), null,
  'TASK: completed_at is cleared on reopen');
select is(pg_temp.wc($$update public.tasks set deleted_at=now() where id='5f000000-0000-0000-0000-00000000005f'$$),
  1, 'TASK: assignee can delete their own task');
select pg_temp.logout();

-- =====================================================================
-- MILESTONES: create, update, hard delete, no completion column (MIL-4/MIL-5)
-- =====================================================================
select pg_temp.login('b5000000-0000-0000-0000-00000000005b','b5@t.co');
insert into public.milestones (id,project_id,title,on_date)
values ('5f5f0000-0000-0000-0000-00000000005f','55550000-0000-0000-0000-000000000001','Deposit due','2027-01-01');
select is((select count(*)::int from public.milestones where id='5f5f0000-0000-0000-0000-00000000005f'), 1,
  'MILESTONE: organizer/member role can create');
select is(pg_temp.wc($$update public.milestones set on_date='2027-02-01' where id='5f5f0000-0000-0000-0000-00000000005f'$$),
  1, 'MILESTONE: organizer/member role can update');
select is(pg_temp.wc($$delete from public.milestones where id='5f5f0000-0000-0000-0000-00000000005f'$$),
  1, 'MILESTONE: delete is a hard delete');
select is((select count(*)::int from public.milestones where id='5f5f0000-0000-0000-0000-00000000005f'), 0,
  'MILESTONE: row is gone after delete');
select pg_temp.logout();

select is(
  (select count(*)::int from information_schema.columns
   where table_schema='public' and table_name='milestones' and column_name in ('completed_at','is_done','done_at')),
  0,
  'MILESTONE: no completion column exists (docs/BUSINESS_RULES.md MIL-4/MIL-5 — derived upcoming/passed only)'
);

select * from finish();
rollback;
