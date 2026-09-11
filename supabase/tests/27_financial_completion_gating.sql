begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
create function pg_temp.login(p_uid uuid, p_email text) returns void language plpgsql as $$
begin
  perform set_config('role','authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub',p_uid,'email',p_email,'role','authenticated')::text, true);
end $$;

insert into auth.users (instance_id,id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,confirmation_token,email_change,email_change_token_new,recovery_token)
values ('00000000-0000-0000-0000-000000000000','aa270000-0000-0000-0000-000000000027','authenticated','authenticated','completion-a@t.co','{}','{}',now(),now(),'','','',''),
       ('00000000-0000-0000-0000-000000000000','bb270000-0000-0000-0000-000000000027','authenticated','authenticated','completion-b@t.co','{}','{}',now(),now(),'','','','');
select pg_temp.login('aa270000-0000-0000-0000-000000000027','completion-a@t.co');
create temporary table pg_temp.ctx as select public.create_project('Completion gating','UTC','GBP',null,null,'team_project') as project_id;
set local role postgres;
insert into public.project_members(project_id,user_id,display_name,role)
select project_id,'bb270000-0000-0000-0000-000000000027','Completion B','member' from pg_temp.ctx;
select pg_temp.login('aa270000-0000-0000-0000-000000000027','completion-a@t.co');

create temporary table pg_temp.item as
with c as (insert into public.commitments(project_id,title,kind,activity_type,status,estimated_cost_minor,cost_split_mode)
select project_id,'Costed activity','other','task','idea',20000,'none' from pg_temp.ctx returning id)
select * from c;
select throws_ok($$update public.commitments set status='completed' where id=(select id from pg_temp.item)$$,'P0001',null,'Unpaid cost cannot complete');
select lives_ok($$insert into public.payments(project_id,commitment_id,type,amount_minor,status,paid_on) select project_id,id,'deposit',10000,'paid',current_date from pg_temp.ctx,pg_temp.item$$,'Partial payment records');
select throws_ok($$update public.commitments set status='completed' where id=(select id from pg_temp.item)$$,'P0001',null,'Partial payment cannot complete');
select lives_ok($$insert into public.payments(project_id,commitment_id,type,amount_minor,status,paid_on) select project_id,id,'balance',10000,'paid',current_date from pg_temp.ctx,pg_temp.item$$,'Balance payment records');
select lives_ok($$update public.commitments set status='completed' where id=(select id from pg_temp.item)$$,'Fully paid cost completes');

create temporary table pg_temp.zero as
with c as (insert into public.commitments(project_id,title,kind,activity_type,status,estimated_cost_minor,cost_split_mode)
select project_id,'Zero cost','other','task','idea',0,'none' from pg_temp.ctx returning id)
select * from c;
select lives_ok($$update public.commitments set status='completed' where id=(select id from pg_temp.zero)$$,'Zero-cost activity completes');

create temporary table pg_temp.split as
with c as (insert into public.commitments(project_id,title,kind,activity_type,status,estimated_cost_minor,cost_split_mode)
select project_id,'Split cost','other','task','idea',20000,'none' from pg_temp.ctx returning id)
select * from c;
select public.set_activity_cost_split((select id from pg_temp.split),jsonb_build_object('mode','even','cost',20000,'members',jsonb_build_array((select id from public.project_members where project_id=(select project_id from pg_temp.ctx) and role='organizer'),(select id from public.project_members where project_id=(select project_id from pg_temp.ctx) and role='member'))));
select throws_ok($$update public.commitments set status='completed' where id=(select id from pg_temp.split)$$,'P0001',null,'Unsettled split member blocks completion');
select public.record_member_payment((select id from pg_temp.split),(select id from public.project_members where project_id=(select project_id from pg_temp.ctx) and role='organizer'),10000,'full',true,current_date);
select public.record_member_payment((select id from pg_temp.split),(select id from public.project_members where project_id=(select project_id from pg_temp.ctx) and role='member'),10000,'full',true,current_date);
select lives_ok($$update public.commitments set status='completed' where id=(select id from pg_temp.split)$$,'Fully settled split completes');

select * from finish();
rollback;