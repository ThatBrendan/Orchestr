begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
create function pg_temp.login(p_uid uuid, p_email text) returns void language plpgsql as $$
begin
  perform set_config('role','authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub',p_uid,'email',p_email,'role','authenticated')::text, true);
end $$;
create function pg_temp.wc(sql text) returns int language plpgsql as $$
declare n int; begin execute sql; get diagnostics n = row_count; return n; end $$;

insert into auth.users (instance_id,id,aud,role,email,raw_app_meta_data,raw_user_meta_data,
  created_at,updated_at,confirmation_token,email_change,email_change_token_new,recovery_token)
values
 ('00000000-0000-0000-0000-000000000000','aa240000-0000-0000-0000-000000000024','authenticated','authenticated','execution-a@t.co','{}','{"display_name":"Execution A"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','bb240000-0000-0000-0000-000000000024','authenticated','authenticated','execution-b@t.co','{}','{"display_name":"Execution B"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','cc240000-0000-0000-0000-000000000024','authenticated','authenticated','execution-c@t.co','{}','{"display_name":"Execution C"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','dd240000-0000-0000-0000-000000000024','authenticated','authenticated','execution-d@t.co','{}','{"display_name":"Execution D"}',now(),now(),'','','','');

select pg_temp.login('aa240000-0000-0000-0000-000000000024','execution-a@t.co');
create temporary table pg_temp.ctx as
select public.create_project('Execution actual cost','UTC','GBP',null,null,'team_project') as project_id;

set local role postgres;
insert into public.project_members (project_id, user_id, display_name, role)
select project_id, 'bb240000-0000-0000-0000-000000000024', 'Execution B', 'member' from pg_temp.ctx;
insert into public.project_members (project_id, user_id, display_name, role)
select project_id, 'cc240000-0000-0000-0000-000000000024', 'Execution C', 'viewer' from pg_temp.ctx;


select pg_temp.login('aa240000-0000-0000-0000-000000000024','execution-a@t.co');

create temporary table pg_temp.activities as
with rows as (
 insert into public.commitments(project_id,title,kind,activity_type,status)
 select ctx.project_id,t::text,'other',t,'idea' from pg_temp.ctx ctx cross join unnest(enum_range(null::public.activity_type)) t returning id,activity_type
) select * from rows;
select lives_ok($$update public.commitments set status='researching' where id in(select id from pg_temp.activities)$$,'Organizer starts every Activity Type');
select lives_ok($$update public.commitments set status='completed' where id in(select id from pg_temp.activities where activity_type<>'booking')$$,'In-progress non-bookings complete');
select throws_ok($$update public.commitments set status='completed' where id=(select id from pg_temp.activities where activity_type='booking')$$,'P0001',null,'Booking cannot skip its existing booking stages');
select lives_ok($$update public.commitments set status='confirmed' where id=(select id from pg_temp.activities where activity_type='booking')$$,'Booking confirmation retained');
select lives_ok($$update public.commitments set status='booked',booking_confirmed=true where id=(select id from pg_temp.activities where activity_type='booking')$$,'Booking recorded independently of completion');
select lives_ok($$update public.commitments set status='completed' where id=(select id from pg_temp.activities where activity_type='booking')$$,'Booked Activity completes');
select lives_ok($$update public.commitments set status='booked' where id=(select id from pg_temp.activities where activity_type='booking')$$,'Booking reopen keeps booking stage');
select ok((select booking_confirmed from public.commitments where id=(select id from pg_temp.activities where activity_type='booking')),'Reopen preserves booking confirmation');
select pg_temp.login('bb240000-0000-0000-0000-000000000024','execution-b@t.co');
select lives_ok($$update public.commitments set status='researching' where id=(select id from pg_temp.activities where activity_type='task')$$,'Member can reopen under existing permissions');
select lives_ok($$update public.commitments set status='idea' where id=(select id from pg_temp.activities where activity_type='task')$$,'Prepare direct-complete fixture');
select lives_ok($$update public.commitments set status='completed' where id=(select id from pg_temp.activities where activity_type='task')$$,'Member directly completes not-started task');
select pg_temp.login('cc240000-0000-0000-0000-000000000024','execution-c@t.co');
select is(pg_temp.wc($$update public.commitments set status='researching' where id=(select id from pg_temp.activities where activity_type='task')$$),0,'Viewer cannot mutate execution');
select is((select status::text from public.commitments where id=(select id from pg_temp.activities where activity_type='task')),'completed','Viewer attempt preserves status');
select pg_temp.login('aa240000-0000-0000-0000-000000000024','execution-a@t.co');
select lives_ok($$update public.commitments set status='cancelled' where id=(select id from pg_temp.activities where activity_type='booking')$$,'Secondary cancel retains existing rule');
select lives_ok($$update public.commitments set status='researching' where id=(select id from pg_temp.activities where activity_type='booking')$$,'Secondary restore retains existing rule');
select * from finish();
rollback;
