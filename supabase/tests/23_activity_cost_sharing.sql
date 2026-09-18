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
 ('00000000-0000-0000-0000-000000000000','aa230000-0000-0000-0000-000000000023','authenticated','authenticated','split-a@t.co','{}','{"display_name":"Split A"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','bb230000-0000-0000-0000-000000000023','authenticated','authenticated','split-b@t.co','{}','{"display_name":"Split B"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','cc230000-0000-0000-0000-000000000023','authenticated','authenticated','split-c@t.co','{}','{"display_name":"Split C"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','dd230000-0000-0000-0000-000000000023','authenticated','authenticated','split-d@t.co','{}','{"display_name":"Split D"}',now(),now(),'','','','');

select pg_temp.login('aa230000-0000-0000-0000-000000000023','split-a@t.co');
create temporary table pg_temp.ctx as
select public.create_project('Split actual cost','UTC','GBP','2026-01-01',null,'team_project') as project_id;

set local role postgres;
insert into public.project_members (project_id, user_id, display_name, role)
select project_id, 'bb230000-0000-0000-0000-000000000023', 'Split B', 'member' from pg_temp.ctx;
insert into public.project_members (project_id, user_id, display_name, role)
select project_id, 'cc230000-0000-0000-0000-000000000023', 'Split C', 'viewer' from pg_temp.ctx;


select pg_temp.login('aa230000-0000-0000-0000-000000000023','split-a@t.co');
-- Name-only active members are supported by existing project membership rules.
insert into public.project_members(project_id,display_name,role,status)
select project_id,'Alex','member','active' from pg_temp.ctx;
create temporary table pg_temp.item as
with added as (insert into public.commitments(project_id,title,kind,activity_type,status,estimated_cost_minor,cost_split_mode)
 select project_id,'Airbnb','accommodation','booking','researching',60000,'none' from pg_temp.ctx returning id) select id from added;
create function pg_temp.split(mode text,cost bigint,amount bigint default null) returns jsonb language sql as $$
 select jsonb_build_object('mode',mode,'cost',cost,'members',jsonb_agg(id order by id),'amounts',jsonb_object_agg(id,coalesce(amount,20000)))
 from public.project_members where project_id=(select project_id from pg_temp.ctx) and role<>'viewer' and status='active';
$$;
select lives_ok($$select public.set_activity_cost_split((select id from pg_temp.item),pg_temp.split('even',60000))$$,'Even split saves');
select is((select sum(fixed_amount_minor)::bigint from public.cost_shares where commitment_id=(select id from pg_temp.item)),60000::bigint,'Shares sum exactly');
select is((select count(*)::int from public.cost_shares where commitment_id=(select id from pg_temp.item) and fixed_amount_minor=20000),3,'600 / 3 is 200 each');
select is((select count(*)::int from public.v_activity_cost_shares where commitment_id=(select id from pg_temp.item)),3,'Existing shares read through view');
select throws_ok($$select public.set_activity_cost_split((select id from pg_temp.item),pg_temp.split('custom',60000,19000))$$,'P0001',null,'Under allocation rejected');
select throws_ok($$select public.set_activity_cost_split((select id from pg_temp.item),pg_temp.split('custom',60000,21000))$$,'P0001',null,'Over allocation rejected');
select lives_ok($$select public.set_activity_cost_split((select id from pg_temp.item),pg_temp.split('custom',60000))$$,'Custom exact total accepted');
-- Deferred constraints validate at transaction end; force them for regression assertions.
create function pg_temp.change_cost(amount bigint) returns void language plpgsql as $$
begin
 update public.commitments set estimated_cost_minor=amount where id=(select id from pg_temp.item);
 set constraints all immediate;
end $$;
select throws_ok($$select pg_temp.change_cost(57000)$$,'P0001',null,'Cost edit without reconciliation rejected');
select is((select estimated_cost_minor from public.commitments where id=(select id from pg_temp.item)),60000::bigint,'Failed cost edit rolled back');
select lives_ok($$select public.set_actual_cost_with_split((select id from pg_temp.item),57000,false,pg_temp.split('even',57000))$$,'Actual transition reconciles atomically');
select is((select sum(fixed_amount_minor)::bigint from public.cost_shares where commitment_id=(select id from pg_temp.item)),57000::bigint,'Actual cost has reconciled shares');
select lives_ok($$select public.set_actual_cost_with_split((select id from pg_temp.item),10000,false,pg_temp.split('even',10000))$$,'Uneven pennies accepted');
select is((select array_agg(fixed_amount_minor order by member_id) from public.cost_shares where commitment_id=(select id from pg_temp.item)),array[3334,3333,3333]::bigint[],'Deterministic penny distribution');
select is((select count(*)::int from public.payments where commitment_id=(select id from pg_temp.item)),0,'No payment invented');
select lives_ok($$select public.set_activity_cost_split((select id from pg_temp.item),'{"mode":"none"}'::jsonb)$$,'No split clears allocations explicitly');
insert into public.commitment_participants(project_id,commitment_id,member_id)
select ctx.project_id,item.id,m.id from pg_temp.ctx ctx cross join pg_temp.item item join public.project_members m on m.project_id=ctx.project_id and m.role<>'viewer';
select is((select count(*)::int from public.v_activity_cost_shares where commitment_id=(select id from pg_temp.item)),0,'No split never invents participant equal shares');
select lives_ok($$select public.set_activity_cost_split((select id from pg_temp.item),pg_temp.split('even',10000))$$,'Split restored');
-- Existing implicit allocation is retained, but changing cost requires explicit review.
create temporary table pg_temp.legacy_item as with c as (
 insert into public.commitments(project_id,title,kind,activity_type,estimated_cost_minor)
 select project_id,'Legacy shared Activity','food','task',9000 from pg_temp.ctx returning id,project_id
) select * from c;
insert into public.commitment_participants(project_id,commitment_id,member_id)
select l.project_id,l.id,m.id from pg_temp.legacy_item l join public.project_members m on m.project_id=l.project_id and m.role<>'viewer';
select is((select sum(amount_minor)::bigint from public.v_activity_cost_shares where commitment_id=(select id from pg_temp.legacy_item)),9000::bigint,'Legacy participant allocation preserved');
create function pg_temp.legacy_cost() returns void language plpgsql as $$ begin
 perform public.set_commitment_actual_cost((select id from pg_temp.legacy_item),8000,false);
 set constraints all immediate;
end $$;
select throws_ok($$select pg_temp.legacy_cost()$$,'P0001',null,'Legacy cost change cannot silently reallocate');
select lives_ok($$select public.set_actual_cost_with_split((select id from pg_temp.legacy_item),8000,false,pg_temp.split('even',8000))$$,'Legacy allocation explicitly reconciled');
-- Create and edit wrappers must save both halves or neither.
select lives_ok($$select public.save_activity_with_split((select project_id from pg_temp.ctx),null,'{"title":"Airport transfer","activity_type":"purchase","kind":"transport","estimated_cost_minor":18000}'::jsonb,
 (select jsonb_build_object('mode','custom','cost',18000,'members',jsonb_agg(id),'amounts',jsonb_object_agg(id,case rn when 1 then 10000 when 2 then 5000 else 3000 end)) from (select id,row_number() over(order by id) rn from public.project_members where project_id=(select project_id from pg_temp.ctx) and role<>'viewer') m))$$,'Create Activity with 100/50/30 custom split');
select is((select sum(s.fixed_amount_minor)::bigint from public.cost_shares s join public.commitments c on c.id=s.commitment_id where c.project_id=(select project_id from pg_temp.ctx) and c.title='Airport transfer'),18000::bigint,'Custom transfer persisted exactly');
select lives_ok($$select public.save_activity_with_split((select project_id from pg_temp.ctx),(select id from public.commitments where project_id=(select project_id from pg_temp.ctx) and title='Airport transfer'),'{"estimated_cost_minor":15000}'::jsonb,pg_temp.split('even',15000))$$,'Edit cost and split atomically');
select throws_ok($$select public.save_activity_with_split((select project_id from pg_temp.ctx),null,'{"title":"Invalid allocation","estimated_cost_minor":60000}'::jsonb,pg_temp.split('custom',60000,1))$$,'P0001',null,'Invalid split rolls back Activity creation');
select is((select count(*)::int from public.commitments where project_id=(select project_id from pg_temp.ctx) and title='Invalid allocation'),0,'No partial Activity persisted');
select pg_temp.login('cc230000-0000-0000-0000-000000000023','split-c@t.co');
select throws_ok($$select public.set_activity_cost_split((select id from pg_temp.item),'{"mode":"none"}'::jsonb)$$,'42501',null,'Viewer cannot change split');
select pg_temp.login('dd230000-0000-0000-0000-000000000023','split-d@t.co');
select throws_ok($$select public.set_activity_cost_split((select id from pg_temp.item),'{"mode":"none"}'::jsonb)$$,'42501',null,'Nonmember cannot change split');
select is((select count(*)::int from public.v_activity_cost_shares where commitment_id=(select id from pg_temp.item)),0,'Project isolation');
create temporary table pg_temp.foreign_project as select public.create_project('Unrelated','UTC','GBP','2026-01-01',null,'team_project') as project_id;
create temporary table pg_temp.foreign_member as select id from public.project_members where project_id=(select project_id from pg_temp.foreign_project);
select pg_temp.login('aa230000-0000-0000-0000-000000000023','split-a@t.co');
select throws_ok($$select public.set_activity_cost_split((select id from pg_temp.item),jsonb_build_object('mode','even','cost',10000,'members',jsonb_build_array((select id from pg_temp.foreign_member))))$$,'42501',null,'Wrong project member rejected');
update public.project_members set status='removed' where project_id=(select project_id from pg_temp.ctx) and display_name='Alex';
select throws_ok($$select public.set_activity_cost_split((select id from pg_temp.item),jsonb_build_object('mode','even','cost',10000,'members',jsonb_build_array((select id from public.project_members where project_id=(select project_id from pg_temp.ctx) and display_name='Alex'))))$$,'42501',null,'Removed member rejected');
select pg_temp.login('bb230000-0000-0000-0000-000000000023','split-b@t.co');
select lives_ok($$select public.set_activity_cost_split((select id from pg_temp.item),pg_temp.split('even',10000))$$,'Other active Member may edit Activity split');
select pg_temp.login('aa230000-0000-0000-0000-000000000023','split-a@t.co');
update public.projects set status='archived' where id=(select project_id from pg_temp.ctx);
select throws_ok($$select public.set_activity_cost_split((select id from pg_temp.item),'{"mode":"none"}'::jsonb)$$,'42501',null,'Archive blocks split changes');
set constraints all immediate;
select * from finish();
rollback;
