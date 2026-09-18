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
 ('00000000-0000-0000-0000-000000000000','aa210000-0000-0000-0000-000000000021','authenticated','authenticated','budget-a@t.co','{}','{"display_name":"Budget A"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','bb210000-0000-0000-0000-000000000021','authenticated','authenticated','budget-b@t.co','{}','{"display_name":"Budget B"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','cc210000-0000-0000-0000-000000000021','authenticated','authenticated','budget-c@t.co','{}','{"display_name":"Budget C"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','dd210000-0000-0000-0000-000000000021','authenticated','authenticated','budget-d@t.co','{}','{"display_name":"Budget D"}',now(),now(),'','','','');

select pg_temp.login('aa210000-0000-0000-0000-000000000021','budget-a@t.co');
create temporary table pg_temp.ctx as
select public.create_project('Budget actual cost','UTC','GBP','2026-01-01',null,'team_project') as project_id;

insert into public.project_members (project_id, user_id, display_name, role)
select project_id, 'bb210000-0000-0000-0000-000000000021', 'Budget B', 'member' from pg_temp.ctx;
insert into public.project_members (project_id, user_id, display_name, role)
select project_id, 'cc210000-0000-0000-0000-000000000021', 'Budget C', 'viewer' from pg_temp.ctx;

create temporary table pg_temp.item as
with added as (insert into public.commitments(project_id,title,kind,activity_type,status,estimated_cost_minor,owner_member_id)
select project_id,'Cost task','other','task','idea',30000,(select id from public.project_members where project_id=ctx.project_id and role='member') from pg_temp.ctx ctx returning id) select id from added;
select ok((select actual_cost_minor is null and estimated_cost_minor=30000 from public.commitments where id=(select id from pg_temp.item)),'No fabricated historical actual');
select is((select total_target_minor from public.v_project_financials where project_id=(select project_id from pg_temp.ctx)),null::bigint,'total_target_minor = null::bigint');
select is((select remaining_budget_minor from public.v_project_financials where project_id=(select project_id from pg_temp.ctx)),null::bigint,'remaining_budget_minor = null::bigint');
select is((select budget_used_pct from public.v_project_financials where project_id=(select project_id from pg_temp.ctx)),null::numeric,'budget_used_pct = null::numeric');
select is((select total_cost_minor from public.v_project_financials where project_id=(select project_id from pg_temp.ctx)),30000::bigint,'total_cost_minor = 30000::bigint');
select is((select committed_spend_minor from public.v_project_financials where project_id=(select project_id from pg_temp.ctx)),0::bigint,'committed_spend_minor = 0::bigint');
select lives_ok($$select public.set_project_budget((select project_id from pg_temp.ctx),500000)$$,'Organizer sets budget');
select is((select remaining_budget_minor from public.v_project_financials where project_id=(select project_id from pg_temp.ctx)),470000::bigint,'remaining_budget_minor = 470000::bigint');
select is((select budget_used_pct from public.v_project_financials where project_id=(select project_id from pg_temp.ctx)),6.0::numeric,'budget_used_pct = 6.0::numeric');
select lives_ok($$select public.set_project_budget((select project_id from pg_temp.ctx),600000)$$,'Organizer edits budget');
select lives_ok($$select public.set_project_budget((select project_id from pg_temp.ctx),null)$$,'Organizer clears budget');
select is((select total_target_minor from public.v_project_financials where project_id=(select project_id from pg_temp.ctx)),null::bigint,'total_target_minor = null::bigint');
select lives_ok($$select public.set_project_budget((select project_id from pg_temp.ctx),0)$$,'Explicit zero budget');
select is((select remaining_budget_minor from public.v_project_financials where project_id=(select project_id from pg_temp.ctx)),-30000::bigint,'remaining_budget_minor = -30000::bigint');
select is((select budget_used_pct from public.v_project_financials where project_id=(select project_id from pg_temp.ctx)),null::numeric,'budget_used_pct = null::numeric');
select throws_ok($$select public.set_project_budget((select project_id from pg_temp.ctx),-1)$$,'22023',null,'Negative budget rejected');
select throws_ok($$select public.set_project_budget((select project_id from pg_temp.ctx),1.5)$$,'22023',null,'Fractional minor units rejected');
select throws_ok($$select public.set_project_budget((select project_id from pg_temp.ctx),'NaN'::numeric)$$,'22023',null,'Nonfinite amount rejected');
select lives_ok($$select public.set_project_budget((select project_id from pg_temp.ctx),500000)$$,'Restore target');
select lives_ok($$select public.set_commitment_actual_cost((select id from pg_temp.item),35000,false)$$,'Organizer sets actual above estimate');
select is((select total_cost_minor from public.v_project_financials where project_id=(select project_id from pg_temp.ctx)),35000::bigint,'total_cost_minor = 35000::bigint');
select throws_ok($$select public.set_commitment_actual_cost((select id from pg_temp.item),-1,false)$$,'22023',null,'Negative actual rejected');
select throws_ok($$select public.set_commitment_actual_cost((select id from pg_temp.item),1.5,false)$$,'22023',null,'Fractional actual minor units rejected');
select throws_ok($$select public.set_commitment_actual_cost((select id from pg_temp.item),'Infinity'::numeric,false)$$,'22023',null,'Infinite actual rejected');
-- A second item exercises aggregation without double-counting payments.
create temporary table pg_temp.second_item as
with added as (insert into public.commitments(project_id,title,kind,activity_type,status,estimated_cost_minor,confirmed_cost_minor)
select project_id,'Second cost item','other','purchase','confirmed',10000,12000 from pg_temp.ctx returning id) select id from added;
select is((select total_cost_minor from public.v_project_financials where project_id=(select project_id from pg_temp.ctx)),47000::bigint,'Multiple items include legacy agreed-price precedence');
select is((select committed_spend_minor from public.v_project_financials where project_id=(select project_id from pg_temp.ctx)),12000::bigint,'Only committed statuses contribute');
select lives_ok($$select public.set_commitment_actual_cost((select id from pg_temp.second_item),0,false)$$,'Second item actual zero overrides agreed price');
select is((select total_cost_minor from public.v_project_financials where project_id=(select project_id from pg_temp.ctx)),35000::bigint,'Zero second actual does not fall back');
update public.commitments set status='cancelled' where id=(select id from pg_temp.second_item);
select pg_temp.login('bb210000-0000-0000-0000-000000000021','budget-b@t.co');
select throws_ok($$select public.set_project_budget((select project_id from pg_temp.ctx),1)$$,'42501',null,'Member cannot set budget');
select lives_ok($$select public.set_commitment_actual_cost((select id from pg_temp.item),0,false)$$,'Assigned member sets actual zero');
select is((select total_cost_minor from public.v_project_financials where project_id=(select project_id from pg_temp.ctx)),0::bigint,'total_cost_minor = 0::bigint');
select lives_ok($$select public.set_commitment_actual_cost((select id from pg_temp.item),null,false)$$,'Null actual restores estimate');
select is((select total_cost_minor from public.v_project_financials where project_id=(select project_id from pg_temp.ctx)),30000::bigint,'total_cost_minor = 30000::bigint');
select lives_ok($$select public.set_commitment_actual_cost((select id from pg_temp.item),24750,true)$$,'Assigned Member completes with final cost atomically');
select is((select committed_spend_minor from public.v_project_financials where project_id=(select project_id from pg_temp.ctx)),24750::bigint,'committed_spend_minor = 24750::bigint');
select is((select net_actual_spend_minor from public.v_project_financials where project_id=(select project_id from pg_temp.ctx)),0::bigint,'net_actual_spend_minor = 0::bigint');
select is((select outstanding_minor from public.v_project_financials where project_id=(select project_id from pg_temp.ctx)),24750::bigint,'outstanding_minor = 24750::bigint');
select is((select remaining_budget_minor from public.v_project_financials where project_id=(select project_id from pg_temp.ctx)),475250::bigint,'remaining_budget_minor = 475250::bigint');
select is((select estimated_cost_minor from public.commitments where id=(select id from pg_temp.item)),30000::bigint,'Estimate preserved');
select throws_ok($$select public.set_commitment_actual_cost((select id from pg_temp.item),25000,false)$$,'42501',null,'Member cannot alter completed final cost');
select pg_temp.login('cc210000-0000-0000-0000-000000000021','budget-c@t.co');
select throws_ok($$select public.set_project_budget((select project_id from pg_temp.ctx),10)$$,'42501',null,'Viewer cannot set budget');
select throws_ok($$select public.set_commitment_actual_cost((select id from pg_temp.item),1,false)$$,'42501',null,'Viewer cannot set actual');
select pg_temp.login('dd210000-0000-0000-0000-000000000021','budget-d@t.co');
select throws_ok($$select public.set_project_budget((select project_id from pg_temp.ctx),10)$$,'42501',null,'Nonmember cannot set budget');
select throws_ok($$select public.set_commitment_actual_cost((select id from pg_temp.item),1,false)$$,'42501',null,'Nonmember cannot set actual');
select is((select count(*)::int from public.v_project_financials where project_id=(select project_id from pg_temp.ctx)),0,'Project financial isolation');
select pg_temp.login('aa210000-0000-0000-0000-000000000021','budget-a@t.co');
select lives_ok($$select public.set_commitment_actual_cost((select id from pg_temp.item),24750,false)$$,'Organizer can correct completed cost');
insert into public.payments(project_id,commitment_id,type,direction,status,amount_minor,paid_on) values((select project_id from pg_temp.ctx),(select id from pg_temp.item),'deposit','outgoing','paid',10000,current_date);
select is((select net_actual_spend_minor from public.v_project_financials where project_id=(select project_id from pg_temp.ctx)),10000::bigint,'net_actual_spend_minor = 10000::bigint');
select is((select outstanding_minor from public.v_project_financials where project_id=(select project_id from pg_temp.ctx)),14750::bigint,'outstanding_minor = 14750::bigint');
insert into public.payments(project_id,commitment_id,type,direction,status,amount_minor,paid_on) values((select project_id from pg_temp.ctx),(select id from pg_temp.item),'refund','incoming','paid',2000,current_date);
select is((select net_actual_spend_minor from public.v_project_financials where project_id=(select project_id from pg_temp.ctx)),8000::bigint,'net_actual_spend_minor = 8000::bigint');
select is((select outstanding_minor from public.v_project_financials where project_id=(select project_id from pg_temp.ctx)),16750::bigint,'outstanding_minor = 16750::bigint');
select lives_ok($$select public.set_project_budget((select project_id from pg_temp.ctx),10000)$$,'Lower budget below spend');
select is((select remaining_budget_minor from public.v_project_financials where project_id=(select project_id from pg_temp.ctx)),-14750::bigint,'remaining_budget_minor = -14750::bigint');
select is((select budget_used_pct from public.v_project_financials where project_id=(select project_id from pg_temp.ctx)),247.5::numeric,'budget_used_pct = 247.5::numeric');
update public.commitments set status='researching' where id=(select id from pg_temp.item);
update public.commitments set status='cancelled' where id=(select id from pg_temp.item);
select is((select net_actual_spend_minor from public.v_project_financials where project_id=(select project_id from pg_temp.ctx)),8000::bigint,'net_actual_spend_minor = 8000::bigint');
select is((select committed_spend_minor from public.v_project_financials where project_id=(select project_id from pg_temp.ctx)),0::bigint,'committed_spend_minor = 0::bigint');
select is((select outstanding_minor from public.v_project_financials where project_id=(select project_id from pg_temp.ctx)),0::bigint,'outstanding_minor = 0::bigint');
select is((select actual_cost_minor from public.commitments where id=(select id from pg_temp.item)),24750::bigint,'Cancellation preserves final cost');
update public.commitments set status='researching',owner_member_id=null where id=(select id from pg_temp.item);
select pg_temp.login('bb210000-0000-0000-0000-000000000021','budget-b@t.co');
select throws_ok($$select public.set_commitment_actual_cost((select id from pg_temp.item),100,false)$$,'42501',null,'Unassigned Member cannot set actual');
select throws_ok($$update public.commitments set actual_cost_minor=100,owner_member_id=app.current_member_id((select project_id from pg_temp.ctx)) where id=(select id from pg_temp.item)$$,'42501',null,'Direct update cannot spoof owner and final cost together');
select pg_temp.login('aa210000-0000-0000-0000-000000000021','budget-a@t.co');
select lives_ok($$select public.set_commitment_actual_cost((select id from pg_temp.item),0,false)$$,'Organizer confirms free activity');
update public.commitments set activity_type='purchase',status='confirmed' where id=(select id from pg_temp.item);
select is((select count(*)::int from app._health_findings((select project_id from pg_temp.ctx)) where code='missing_cost'),0,'Actual zero is not missing cost');
update public.projects set status='archived' where id=(select project_id from pg_temp.ctx);
select throws_ok($$select public.set_project_budget((select project_id from pg_temp.ctx),100)$$,'42501',null,'Archive blocks budget');
select throws_ok($$select public.set_commitment_actual_cost((select id from pg_temp.item),100,false)$$,'42501',null,'Archive blocks actual');
set local role postgres;
select set_config('request.jwt.claims','',true);
update public.users set platform_role='admin' where id='dd210000-0000-0000-0000-000000000021';
select pg_temp.login('dd210000-0000-0000-0000-000000000021','budget-d@t.co');
select throws_ok($$select public.set_project_budget((select project_id from pg_temp.ctx),100)$$,'42501',null,'Platform admin does not bypass membership');
select throws_ok($$select public.set_commitment_actual_cost((select id from pg_temp.item),100,false)$$,'42501',null,'Platform admin cannot set actual without membership');
set local role postgres;
select set_config('request.jwt.claims','',true);
select ok(exists(select 1 from public.audit_log where entity_type='budgets' and action='update'),'Budget updates audited');
select ok(exists(select 1 from public.audit_log where entity_type='commitments' and after->>'actual_cost_minor'='24750'),'Final cost audited');
select * from finish();
rollback;
