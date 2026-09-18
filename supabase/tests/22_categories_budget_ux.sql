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
 ('00000000-0000-0000-0000-000000000000','aa220000-0000-0000-0000-000000000022','authenticated','authenticated','category-a@t.co','{}','{"display_name":"Category A"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','bb220000-0000-0000-0000-000000000022','authenticated','authenticated','category-b@t.co','{}','{"display_name":"Category B"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','cc220000-0000-0000-0000-000000000022','authenticated','authenticated','category-c@t.co','{}','{"display_name":"Category C"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','dd220000-0000-0000-0000-000000000022','authenticated','authenticated','category-d@t.co','{}','{"display_name":"Category D"}',now(),now(),'','','','');

select pg_temp.login('aa220000-0000-0000-0000-000000000022','category-a@t.co');
create temporary table pg_temp.ctx as
select public.create_project('Category actual cost','UTC','GBP','2026-01-01',null,'team_project') as project_id;

insert into public.project_members (project_id, user_id, display_name, role)
select project_id, 'bb220000-0000-0000-0000-000000000022', 'Category B', 'member' from pg_temp.ctx;
insert into public.project_members (project_id, user_id, display_name, role)
select project_id, 'cc220000-0000-0000-0000-000000000022', 'Category C', 'viewer' from pg_temp.ctx;


-- Every old and new category persists and is visible through financial views.
insert into public.commitments(project_id,title,kind,activity_type,estimated_cost_minor)
select ctx.project_id,k::text,k,'task',0 from pg_temp.ctx ctx
cross join unnest(enum_range(null::public.commitment_kind)) k;
select is((select count(*)::int from public.commitments where project_id=(select project_id from pg_temp.ctx)),11,'All eleven categories persist');
select is((select count(*)::int from public.v_budget_category_actuals where project_id=(select project_id from pg_temp.ctx)),11,'All categories appear in budget read model');
insert into public.budget_category_targets(project_id,kind,amount_minor)
select ctx.project_id,k,10000 from pg_temp.ctx ctx cross join unnest(array['equipment_assets','technology','marketing','supplies_materials','fees_admin']::public.commitment_kind[]) k;
select is((select count(*)::int from public.v_budget_category_actuals where project_id=(select project_id from pg_temp.ctx) and target_minor=10000),5,'New categories support targets');

insert into public.commitments(project_id,title,kind,activity_type,status,estimated_cost_minor)
select project_id,'Buy laptops','equipment_assets'::public.commitment_kind,'purchase'::public.activity_type,'confirmed'::public.commitment_status,50000 from pg_temp.ctx
union all select project_id,'Set up hosting','technology','task','idea',20000 from pg_temp.ctx
union all select project_id,'Launch ads','marketing','task','idea',50000 from pg_temp.ctx;
select public.set_project_budget((select project_id from pg_temp.ctx),100000);
insert into public.payments(project_id,commitment_id,type,direction,status,amount_minor,paid_on)
select project_id,id,'deposit','outgoing','paid',95000,current_date from public.commitments where project_id=(select project_id from pg_temp.ctx) and title='Buy laptops';
select is((select total_cost_minor from public.v_project_financials where project_id=(select project_id from pg_temp.ctx)),120000::bigint,'Planned 1200');
select is((select net_actual_spend_minor from public.v_project_financials where project_id=(select project_id from pg_temp.ctx)),95000::bigint,'Paid 950 is independent');
select is((select remaining_budget_minor from public.v_project_financials where project_id=(select project_id from pg_temp.ctx)),-20000::bigint,'Remaining -200');
select is((select projected_variance_minor from public.v_project_financials where project_id=(select project_id from pg_temp.ctx)),-20000::bigint,'Projected variance -200');
select is((select budget_used_pct from public.v_project_financials where project_id=(select project_id from pg_temp.ctx)),120.0::numeric,'Budget used 120 percent');
select is((select net_paid_minor from public.v_budget_category_actuals where project_id=(select project_id from pg_temp.ctx) and kind='equipment_assets'),95000::bigint,'Category paid comes from Payments');
select is((select actual_minor from public.v_budget_category_actuals where project_id=(select project_id from pg_temp.ctx) and kind='technology'),20000::bigint,'Technology grouped independently');

-- Category changes leave operational type intact for each requested pairing.
insert into public.commitments(project_id,title,kind,activity_type,status)
select project_id,'Purchase technology','technology','purchase','researching' from pg_temp.ctx;
update public.commitments set kind='equipment_assets' where project_id=(select project_id from pg_temp.ctx) and title='Purchase technology';
select is((select activity_type::text from public.commitments where project_id=(select project_id from pg_temp.ctx) and title='Purchase technology'),'purchase','Category change preserves Purchase behaviour');
update public.commitments set kind='services' where project_id=(select project_id from pg_temp.ctx) and title='Set up hosting';
select is((select activity_type::text from public.commitments where project_id=(select project_id from pg_temp.ctx) and title='Set up hosting'),'task','Task Technology to Services stays Task');
insert into public.commitments(project_id,title,kind,activity_type,status)
select project_id,'Book services','services','booking','researching' from pg_temp.ctx;
select is((select activity_type::text from public.commitments where project_id=(select project_id from pg_temp.ctx) and title='Book services'),'booking','Booking Services stays Booking');
select public.set_project_budget((select project_id from pg_temp.ctx),null);
select is((select budget_used_pct from public.v_project_financials where project_id=(select project_id from pg_temp.ctx)),null::numeric,'No target has no percentage');
select is((select remaining_budget_minor from public.v_project_financials where project_id=(select project_id from pg_temp.ctx)),null::bigint,'No target has no remaining');
select * from finish();
rollback;
