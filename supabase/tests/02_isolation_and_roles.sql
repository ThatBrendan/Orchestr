-- pgTAP: cross-project isolation, role gradient, self-enrolment, role escalation.
-- Verifies: RLS works · users cannot access other projects · organizer/member/viewer access.
begin;
create extension if not exists pgtap with schema extensions;
select plan(23);

create function pg_temp.login(p_uid uuid, p_email text) returns void language plpgsql as $$
begin
  perform set_config('role','authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub',p_uid,'email',p_email,'role','authenticated')::text, true);
end $$;
create function pg_temp.logout() returns void language plpgsql as $$
begin perform set_config('request.jwt.claims','', true); perform set_config('role','postgres', true); end $$;
-- runs a write and returns affected row count (propagates exceptions)
create function pg_temp.wc(sql text) returns int language plpgsql as $$
declare n int; begin execute sql; get diagnostics n = row_count; return n; end $$;

insert into auth.users (instance_id,id,aud,role,email,raw_app_meta_data,raw_user_meta_data,
  created_at,updated_at,confirmation_token,email_change,email_change_token_new,recovery_token)
values
 ('00000000-0000-0000-0000-000000000000','a0a0a0a0-0000-0000-0000-00000000000a','authenticated','authenticated','a@t.co','{}','{"display_name":"A"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','b0b0b0b0-0000-0000-0000-00000000000b','authenticated','authenticated','b@t.co','{}','{"display_name":"B"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','c0c0c0c0-0000-0000-0000-00000000000c','authenticated','authenticated','c@t.co','{}','{"display_name":"C"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','d0d0d0d0-0000-0000-0000-00000000000d','authenticated','authenticated','d@t.co','{}','{"display_name":"D"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','e0e0e0e0-0000-0000-0000-00000000000e','authenticated','authenticated','e@t.co','{}','{"display_name":"E"}',now(),now(),'','','','');

insert into public.projects (id,name,status,timezone,currency) values
 ('11110000-0000-0000-0000-000000000001','P1','active','UTC','GBP'),
 ('22220000-0000-0000-0000-000000000002','P2','active','UTC','GBP');
insert into public.project_members (id,project_id,user_id,display_name,email,role,status) values
 ('f1110000-0000-0000-0000-00000000000a','11110000-0000-0000-0000-000000000001','a0a0a0a0-0000-0000-0000-00000000000a','A','a@t.co','organizer','active'),
 ('f1110000-0000-0000-0000-00000000000b','11110000-0000-0000-0000-000000000001','b0b0b0b0-0000-0000-0000-00000000000b','B','b@t.co','member','active'),
 ('f1110000-0000-0000-0000-00000000000c','11110000-0000-0000-0000-000000000001','c0c0c0c0-0000-0000-0000-00000000000c','C','c@t.co','viewer','active'),
 ('f2220000-0000-0000-0000-00000000000d','22220000-0000-0000-0000-000000000002','d0d0d0d0-0000-0000-0000-00000000000d','D','d@t.co','organizer','active');
update public.projects set created_by='f1110000-0000-0000-0000-00000000000a' where id='11110000-0000-0000-0000-000000000001';
update public.projects set created_by='f2220000-0000-0000-0000-00000000000d' where id='22220000-0000-0000-0000-000000000002';
insert into public.commitments (id,project_id,title,kind,status,confirmed_cost_minor)
values ('c1110000-0000-0000-0000-000000000001','11110000-0000-0000-0000-000000000001','P1 boat','experience','researching',10000);

-- ===== anonymous =====
select set_config('role','anon', true); select set_config('request.jwt.claims','', true);
select is((select count(*)::int from public.projects), 0, 'anon: 0 projects');
select is((select count(*)::int from public.commitments), 0, 'anon: 0 commitments');
select pg_temp.logout();

-- ===== D (P2 only) cannot reach P1 =====
select pg_temp.login('d0d0d0d0-0000-0000-0000-00000000000d','d@t.co');
select is((select count(*)::int from public.projects   where id='11110000-0000-0000-0000-000000000001'), 0, 'D: cannot see P1');
select is((select count(*)::int from public.commitments where project_id='11110000-0000-0000-0000-000000000001'), 0, 'D: cannot see P1 commitments');
select is((select count(*)::int from public.projects   where id='22220000-0000-0000-0000-000000000002'), 1, 'D: sees own P2');
select throws_ok($$insert into public.commitments (project_id,title,kind,status)
  values ('11110000-0000-0000-0000-000000000001','hack','other','idea')$$,
  '42501', null, 'D: cannot insert into P1');
select is(pg_temp.wc($$update public.commitments set title='x' where id='c1110000-0000-0000-0000-000000000001'$$),
  0, 'D: update of a P1 commitment affects 0 rows');
select pg_temp.logout();

-- ===== E (no memberships) =====
select pg_temp.login('e0e0e0e0-0000-0000-0000-00000000000e','e@t.co');
select is((select count(*)::int from public.projects), 0, 'E: sees no projects');
select throws_ok($$insert into public.project_members (project_id,user_id,display_name,email,role,status)
  values ('11110000-0000-0000-0000-000000000001','e0e0e0e0-0000-0000-0000-00000000000e','E','e@t.co','organizer','active')$$,
  '42501', null, 'E: cannot self-enrol as organizer');
select throws_ok($$insert into public.project_members (project_id,user_id,display_name,email,role,status)
  values ('11110000-0000-0000-0000-000000000001','e0e0e0e0-0000-0000-0000-00000000000e','E','e@t.co','member','active')$$,
  '42501', null, 'E: cannot self-enrol as member');
select public.create_project('E project','UTC','GBP','2026-01-01',null);
select is((select role::text from public.project_members
           where user_id='e0e0e0e0-0000-0000-0000-00000000000e'
             and role = 'organizer' and status = 'active'),
          'organizer', 'E: founding member auto-created as organizer');
select pg_temp.logout();

-- ===== C (viewer) =====
select pg_temp.login('c0c0c0c0-0000-0000-0000-00000000000c','c@t.co');
select is((select count(*)::int from public.commitments where project_id='11110000-0000-0000-0000-000000000001'), 1, 'C viewer: reads P1 commitments');
select throws_ok($$insert into public.commitments (project_id,title,kind,status)
  values ('11110000-0000-0000-0000-000000000001','v','other','idea')$$,
  '42501', null, 'C viewer: cannot insert a commitment');
select is(pg_temp.wc($$update public.commitments set title='x' where id='c1110000-0000-0000-0000-000000000001'$$),
  0, 'C viewer: commitment update affects 0 rows');
select pg_temp.logout();

-- ===== B (member) =====
select pg_temp.login('b0b0b0b0-0000-0000-0000-00000000000b','b@t.co');
select is(pg_temp.wc($$insert into public.commitments (id,project_id,title,kind,status,confirmed_cost_minor)
  values ('c1110000-0000-0000-0000-000000000002','11110000-0000-0000-0000-000000000001','B added','food','researching',5000)$$),
  1, 'B member: can insert a commitment');
select is(pg_temp.wc($$update public.commitments set title='B edit' where id='c1110000-0000-0000-0000-000000000001'$$),
  1, 'B member: can edit any commitment');
select is(pg_temp.wc($$update public.projects set name='x' where id='11110000-0000-0000-0000-000000000001'$$),
  0, 'B member: project rename affects 0 rows');
select throws_ok($$insert into public.budgets (project_id,total_target_minor)
  values ('11110000-0000-0000-0000-000000000001',999)$$,
  '42501', null, 'B member: cannot set the budget');
select throws_ok($$update public.project_members set role='organizer' where id='f1110000-0000-0000-0000-00000000000b'$$,
  'P0001', null, 'B member: cannot self-promote (trigger)');
select pg_temp.logout();

-- ===== A (organizer) =====
select pg_temp.login('a0a0a0a0-0000-0000-0000-00000000000a','a@t.co');
select is(pg_temp.wc($$update public.projects set name='P1 renamed' where id='11110000-0000-0000-0000-000000000001'$$),
  1, 'A organizer: can rename the project');
select is(pg_temp.wc($$insert into public.budgets (project_id,total_target_minor)
  values ('11110000-0000-0000-0000-000000000001',50000)$$),
  1, 'A organizer: can set the budget');
select throws_ok($$update public.project_members set role='member' where id='f1110000-0000-0000-0000-00000000000a'$$,
  'P0001', null, 'A organizer: cannot demote the last organizer');
select pg_temp.logout();

select * from finish();
rollback;
