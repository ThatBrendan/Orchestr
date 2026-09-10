begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

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


-- Dedicated rows; all changes roll back.
insert into public.commitments (id,project_id,title,kind,created_by,owner_member_id)
values ('5d000000-0000-0000-0000-00000000005d','55550000-0000-0000-0000-000000000001','Delete regression','other','5a000000-0000-0000-0000-00000000005a','5b000000-0000-0000-0000-00000000005b');
insert into public.tasks (id,project_id,title,created_by,assignee_member_id)
values ('5f000000-0000-0000-0000-00000000005f','55550000-0000-0000-0000-000000000001','Delete regression','5a000000-0000-0000-0000-00000000005a','5b000000-0000-0000-0000-00000000005b');
insert into public.tasks (project_id,title,commitment_id)
values ('55550000-0000-0000-0000-000000000001','Cascade regression','5d000000-0000-0000-0000-00000000005d');
insert into public.payments (project_id,commitment_id,type,amount_minor,status,paid_on)
values ('55550000-0000-0000-0000-000000000001','5d000000-0000-0000-0000-00000000005d','deposit',100,'paid',current_date);
update public.commitments set starts_at=current_date, is_all_day=true, recurrence_frequency='weekly', recurrence_interval=1, recurrence_start_date=current_date where project_id='55550000-0000-0000-0000-000000000001';
update public.tasks set due_on=current_date, recurrence_frequency='weekly', recurrence_interval=1, recurrence_start_date=current_date where project_id='55550000-0000-0000-0000-000000000001';
select pg_temp.login('c5000000-0000-0000-0000-00000000005c','c5@t.co');
select throws_ok($$select public.soft_delete_commitment('5d000000-0000-0000-0000-00000000005d')$$, '42501', null, 'commitment: viewer delete denied');
select throws_ok($$select public.soft_delete_task('5f000000-0000-0000-0000-00000000005f')$$, '42501', null, 'task: viewer delete denied');
select pg_temp.logout();
update public.commitments set owner_member_id=null where project_id='55550000-0000-0000-0000-000000000001'; update public.tasks set assignee_member_id=null where project_id='55550000-0000-0000-0000-000000000001';
select pg_temp.login('b5000000-0000-0000-0000-00000000005b','b5@t.co');
select throws_ok($$select public.soft_delete_commitment('5d000000-0000-0000-0000-00000000005d')$$, '42501', null, 'commitment: outsider delete denied');
select throws_ok($$select public.soft_delete_task('5f000000-0000-0000-0000-00000000005f')$$, '42501', null, 'task: outsider delete denied');
select pg_temp.logout();
update public.commitments set owner_member_id='5b000000-0000-0000-0000-00000000005b' where project_id='55550000-0000-0000-0000-000000000001'; update public.tasks set assignee_member_id='5b000000-0000-0000-0000-00000000005b' where project_id='55550000-0000-0000-0000-000000000001'; update public.projects set status='archived' where id='55550000-0000-0000-0000-000000000001';
select pg_temp.login('b5000000-0000-0000-0000-00000000005b','b5@t.co');
select throws_ok($$select public.soft_delete_commitment('5d000000-0000-0000-0000-00000000005d')$$, 'P0001', null, 'commitment: archived delete denied');
select throws_ok($$update public.commitments set title='blocked' where id='5d000000-0000-0000-0000-00000000005d'$$, 'P0001', null, 'Archived activity edit denied');
select throws_ok($$update public.tasks set title='blocked' where id='5f000000-0000-0000-0000-00000000005f'$$, 'P0001', null, 'Archived task edit denied');
select throws_ok($$select public.soft_delete_task('5f000000-0000-0000-0000-00000000005f')$$, 'P0001', null, 'task: archived delete denied');
select pg_temp.logout();
update public.projects set status='active' where id='55550000-0000-0000-0000-000000000001';
select pg_temp.login('b5000000-0000-0000-0000-00000000005b','b5@t.co');
select lives_ok($$select public.soft_delete_commitment('5d000000-0000-0000-0000-00000000005d')$$, 'commitment: owner/assignee soft delete succeeds');
select lives_ok($$select public.soft_delete_task('5f000000-0000-0000-0000-00000000005f')$$, 'task: owner/assignee soft delete succeeds');
select is((select count(*)::int from public.commitments where project_id='55550000-0000-0000-0000-000000000001'), 0, 'commitments: deleted rows absent including cascades');
select is((select count(*)::int from public.tasks where project_id='55550000-0000-0000-0000-000000000001'), 0, 'tasks: deleted rows absent including cascades');
select is((select count(*)::int from public.payments where project_id='55550000-0000-0000-0000-000000000001' and status='paid'), 1, 'Paid history preserved');
select is((select count(*)::int from public.get_commitment_occurrences('5d000000-0000-0000-0000-00000000005d',current_date,current_date+7)),0,'Deleted activity has no derived occurrences');
select is((select count(*)::int from public.get_task_occurrences('5f000000-0000-0000-0000-00000000005f',current_date,current_date+7)),0,'Deleted task has no derived occurrences');
select pg_temp.logout();

select pg_temp.login('a5000000-0000-0000-0000-00000000005a','a5@t.co');
update public.projects set status='archived' where id='55550000-0000-0000-0000-000000000001';
select throws_ok($$update public.projects set name='blocked' where id='55550000-0000-0000-0000-000000000001'$$, '42501', null, 'Archived project fields protected');
select throws_ok($$select public.soft_delete_project('55550000-0000-0000-0000-000000000001')$$, 'P0001', null, 'Archived project delete denied');
update public.projects set status='active' where id='55550000-0000-0000-0000-000000000001';
select lives_ok($$select public.soft_delete_project('55550000-0000-0000-0000-000000000001')$$, 'Organizer project delete succeeds');
select is((select count(*)::int from public.projects where id='55550000-0000-0000-0000-000000000001'),0,'Deleted project hidden');
select pg_temp.logout();
select * from finish();
rollback;
