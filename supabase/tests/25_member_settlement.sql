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
 ('00000000-0000-0000-0000-000000000000','aa250000-0000-0000-0000-000000000025','authenticated','authenticated','settlement-a@t.co','{}','{"display_name":"Execution A"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','bb250000-0000-0000-0000-000000000025','authenticated','authenticated','settlement-b@t.co','{}','{"display_name":"Execution B"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','cc250000-0000-0000-0000-000000000025','authenticated','authenticated','settlement-c@t.co','{}','{"display_name":"Execution C"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','dd250000-0000-0000-0000-000000000025','authenticated','authenticated','settlement-d@t.co','{}','{"display_name":"Execution D"}',now(),now(),'','','','');

select pg_temp.login('aa250000-0000-0000-0000-000000000025','settlement-a@t.co');
create temporary table pg_temp.ctx as
select public.create_project('Execution actual cost','UTC','GBP',null,null,'team_project') as project_id;

set local role postgres;
insert into public.project_members (project_id, user_id, display_name, role)
select project_id, 'bb250000-0000-0000-0000-000000000025', 'Execution B', 'member' from pg_temp.ctx;
insert into public.project_members (project_id, user_id, display_name, role)
select project_id, 'cc250000-0000-0000-0000-000000000025', 'Execution C', 'viewer' from pg_temp.ctx;


select pg_temp.login('aa250000-0000-0000-0000-000000000025','settlement-a@t.co');

create temporary table pg_temp.item as with c as (
 insert into public.commitments(project_id,title,kind,activity_type,status,estimated_cost_minor,cost_split_mode)
 select project_id,'Shared cost','other','task','idea',3000,'none' from pg_temp.ctx returning id
) select * from c;
create temporary table pg_temp.recipient as select id from public.project_members where project_id=(select project_id from pg_temp.ctx) and role='member';
select public.set_activity_cost_split((select id from pg_temp.item),jsonb_build_object('mode','even','cost',3000,'members',jsonb_build_array((select id from pg_temp.recipient))));
select lives_ok($$select public.record_member_payment((select id from pg_temp.item),(select id from pg_temp.recipient),1000,'deposit',true,current_date)$$,'Organizer records partial payment');
select is((select remaining_minor from public.v_activity_member_settlements where commitment_id=(select id from pg_temp.item)),2000::bigint,'Partial remaining');
select lives_ok($$select public.record_member_payment((select id from pg_temp.item),(select id from pg_temp.recipient),500,'refund',true,current_date)$$,'Refund recorded');
select is((select remaining_minor from public.v_activity_member_settlements where commitment_id=(select id from pg_temp.item)),2500::bigint,'Refund increases remaining');
select pg_temp.login('bb250000-0000-0000-0000-000000000025','settlement-b@t.co');
select lives_ok($$select public.record_member_payment((select id from pg_temp.item),(select id from pg_temp.recipient),2500,'balance',true,current_date)$$,'Member settles own remainder');
select is((select remaining_minor from public.v_activity_member_settlements where commitment_id=(select id from pg_temp.item)),0::bigint,'Multiple payments fully settle');
select throws_ok($$insert into public.payments(project_id,commitment_id,type,status,amount_minor,paid_on,paid_by_member_id) select ctx.project_id,item.id,'full','paid',100,current_date,m.id from pg_temp.ctx ctx cross join pg_temp.item item join public.project_members m on m.project_id=ctx.project_id and m.role='organizer'$$,'42501',null,'Member cannot attribute another persons payment');
select pg_temp.login('cc250000-0000-0000-0000-000000000025','settlement-c@t.co');
select throws_ok($$select public.record_member_payment((select id from pg_temp.item),(select id from pg_temp.recipient),100,'full',true,current_date)$$,'42501',null,'Viewer cannot settle');
select pg_temp.login('dd250000-0000-0000-0000-000000000025','settlement-d@t.co');
select is((select count(*)::int from public.v_activity_member_settlements where commitment_id=(select id from pg_temp.item)),0,'Settlement isolation');
select * from finish();
rollback;
