-- pgTAP: foreign keys (cross-project), CHECK constraints, deletion behaviour,
-- invitation flow, audit-log immutability.
begin;
create extension if not exists pgtap with schema extensions;
select plan(20);

create function pg_temp.login(p_uid uuid, p_email text) returns void language plpgsql as $$
begin
  perform set_config('role','authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub',p_uid,'email',p_email,'role','authenticated')::text, true);
end $$;
create function pg_temp.logout() returns void language plpgsql as $$
begin perform set_config('request.jwt.claims','', true); perform set_config('role','postgres', true); end $$;

insert into auth.users (instance_id,id,aud,role,email,raw_app_meta_data,raw_user_meta_data,
  created_at,updated_at,confirmation_token,email_change,email_change_token_new,recovery_token)
values
 ('00000000-0000-0000-0000-000000000000','1a000000-0000-0000-0000-00000000001a','authenticated','authenticated','org@t.co','{}','{"display_name":"Org"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','1b000000-0000-0000-0000-00000000001b','authenticated','authenticated','invitee@t.co','{}','{"display_name":"Invitee"}',now(),now(),'','','','');

insert into public.projects (id,name,status,timezone,currency) values
 ('a1000000-0000-0000-0000-0000000000a1','P1','active','UTC','GBP'),
 ('a2000000-0000-0000-0000-0000000000a2','P2','active','UTC','GBP');
insert into public.project_members (id,project_id,user_id,display_name,email,role,status) values
 ('b1000000-0000-0000-0000-0000000000b1','a1000000-0000-0000-0000-0000000000a1','1a000000-0000-0000-0000-00000000001a','Org','org@t.co','organizer','active'),
 ('b1000000-0000-0000-0000-0000000000b2','a1000000-0000-0000-0000-0000000000a1',null,'Mem','mem@t.co','member','active'),
 ('b2000000-0000-0000-0000-0000000000b3','a2000000-0000-0000-0000-0000000000a2',null,'Other','other@t.co','organizer','active');
update public.projects set created_by='b1000000-0000-0000-0000-0000000000b1' where id='a1000000-0000-0000-0000-0000000000a1';
update public.projects set created_by='b2000000-0000-0000-0000-0000000000b3' where id='a2000000-0000-0000-0000-0000000000a2';

-- ===== cross-project FK =====
select throws_ok($$
  insert into public.commitments (project_id,title,kind,status,owner_member_id)
  values ('a1000000-0000-0000-0000-0000000000a1','x','other','researching','b2000000-0000-0000-0000-0000000000b3') $$,
  '23503', null, 'FK: cannot own a P1 commitment with a P2 member');
select throws_ok($$
  insert into public.payments (project_id,commitment_id,type,status,amount_minor)
  select 'a1000000-0000-0000-0000-0000000000a1', id, 'full','scheduled',100
  from public.commitments where project_id='a2000000-0000-0000-0000-0000000000a2' limit 1 $$,
  null, null, 'FK: cannot attach a P1 payment to a P2 commitment');

-- ===== CHECK constraints =====
insert into public.commitments (id,project_id,title,kind,status,confirmed_cost_minor)
values ('c1000000-0000-0000-0000-0000000000c1','a1000000-0000-0000-0000-0000000000a1','C1','experience','researching',10000);
select throws_ok($$update public.commitments set starts_at=now(), ends_at=now()-interval '1 h'
  where id='c1000000-0000-0000-0000-0000000000c1'$$, '23514', null, 'CHECK: ends_at >= starts_at');
select throws_ok($$insert into public.payments (project_id,commitment_id,type,status,amount_minor)
  values ('a1000000-0000-0000-0000-0000000000a1','c1000000-0000-0000-0000-0000000000c1','full','scheduled',0)$$,
  '23514', null, 'CHECK: payment amount_minor > 0');
select throws_ok($$insert into public.projects (name,status,timezone,currency)
  values ('   ','draft','UTC','GBP')$$, '23514', null, 'CHECK: project name non-blank');
select throws_ok($$update public.projects set timezone='Mars/Olympus' where id='a1000000-0000-0000-0000-0000000000a1'$$,
  'P0001', null, 'TRIGGER: invalid timezone rejected');

-- ===== currency immutability =====
select throws_ok($$update public.projects set currency='EUR' where id='a1000000-0000-0000-0000-0000000000a1'$$,
  'P0001', null, 'TRIGGER: currency locked once commitments exist');

-- ===== deletion behaviour =====
insert into public.payments (id,project_id,commitment_id,type,status,amount_minor,due_on)
values ('d1000000-0000-0000-0000-0000000000d1','a1000000-0000-0000-0000-0000000000a1','c1000000-0000-0000-0000-0000000000c1','balance','scheduled',5000,current_date+10);
insert into public.payments (id,project_id,commitment_id,type,status,amount_minor,paid_on,paid_by_member_id)
values ('d1000000-0000-0000-0000-0000000000d2','a1000000-0000-0000-0000-0000000000a1','c1000000-0000-0000-0000-0000000000c1','deposit','paid',2000,current_date-1,'b1000000-0000-0000-0000-0000000000b2');
insert into public.tasks (id,project_id,commitment_id,title,status)
values ('e1000000-0000-0000-0000-0000000000e1','a1000000-0000-0000-0000-0000000000a1','c1000000-0000-0000-0000-0000000000c1','t','open');
insert into public.milestones (id,project_id,commitment_id,title,on_date)
values ('f1000000-0000-0000-0000-0000000000f1','a1000000-0000-0000-0000-0000000000a1','c1000000-0000-0000-0000-0000000000c1','m',current_date+5);

-- paid payment cannot be soft-deleted
select throws_ok($$update public.payments set deleted_at=now() where id='d1000000-0000-0000-0000-0000000000d2'$$,
  'P0001', null, 'DELETE: a paid payment cannot be soft-deleted');

-- soft-delete the commitment -> cascades
update public.commitments set deleted_at=now() where id='c1000000-0000-0000-0000-0000000000c1';
select is((select status::text from public.payments where id='d1000000-0000-0000-0000-0000000000d1'), 'cancelled',
  'DELETE: scheduled payment on a deleted commitment is cancelled');
select is((select status::text from public.payments where id='d1000000-0000-0000-0000-0000000000d2'), 'paid',
  'DELETE: paid payment on a deleted commitment is preserved (still paid)');
select ok((select deleted_at is not null from public.tasks where id='e1000000-0000-0000-0000-0000000000e1'),
  'DELETE: child task soft-deleted with its commitment');
select is((select commitment_id from public.milestones where id='f1000000-0000-0000-0000-0000000000f1'), null,
  'DELETE: milestone survives, link cleared');

-- soft-delete the project -> members go too, project invisible to members
update public.projects set deleted_at=now() where id='a1000000-0000-0000-0000-0000000000a1';
select pg_temp.login('1a000000-0000-0000-0000-00000000001a','org@t.co');
select is((select count(*)::int from public.projects where id='a1000000-0000-0000-0000-0000000000a1'), 0,
  'DELETE: a soft-deleted project is invisible even to its organizer');
select pg_temp.logout();

-- ===== invitations =====
insert into public.invitations (id,project_id,email,role,invited_by,token,expires_at)
values ('91000000-0000-0000-0000-000000000091','a2000000-0000-0000-0000-0000000000a2','invitee@t.co','member',
        'b2000000-0000-0000-0000-0000000000b3','tok-good', now()+interval '7 days'),
       ('92000000-0000-0000-0000-000000000092','a2000000-0000-0000-0000-0000000000a2','someoneelse@t.co','member',
        'b2000000-0000-0000-0000-0000000000b3','tok-wrongmail', now()+interval '7 days');

select pg_temp.login('1b000000-0000-0000-0000-00000000001b','invitee@t.co');
select throws_ok($$insert into public.invitations (project_id,email,role,invited_by,token)
  values ('a2000000-0000-0000-0000-0000000000a2','x@t.co','member','b2000000-0000-0000-0000-0000000000b3','tok-x')$$,
  '42501', null, 'INVITE: clients cannot INSERT invitations directly');
select throws_ok($$select public.accept_invitation('tok-wrongmail')$$,
  'P0001', null, 'INVITE: cannot accept an invitation addressed to a different email');
select is( public.accept_invitation('tok-good'), 'a2000000-0000-0000-0000-0000000000a2',
  'INVITE: accepting a valid invitation returns the project_id');
select throws_ok($$select public.accept_invitation('tok-good')$$, 'P0001', null,
  'INVITE: accepted invitation cannot be accepted twice');
select pg_temp.logout();
select is((select role::text from public.project_members
           where project_id='a2000000-0000-0000-0000-0000000000a2' and user_id='1b000000-0000-0000-0000-00000000001b'),
          'member', 'INVITE: invitee joined at the invitation''s role');

-- ===== audit immutability =====
select throws_ok($$update public.audit_log set action='delete' where id=(select id from public.audit_log limit 1)$$,
  'P0001', null, 'AUDIT: audit_log rows cannot be updated (even as postgres)');
select throws_ok($$delete from public.audit_log where id=(select id from public.audit_log limit 1)$$,
  'P0001', null, 'AUDIT: audit_log rows cannot be deleted (even as postgres)');

select * from finish();
rollback;
