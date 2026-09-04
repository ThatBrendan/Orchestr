-- pgTAP: derived financial calculations (v_project_financials, v_member_balances,
-- v_commitment_financials) against a hand-computed fixture, incl. the
-- financial-history rule (paid money on a cancelled commitment is preserved).
begin;
create extension if not exists pgtap with schema extensions;
select plan(13);

create function pg_temp.login(p_uid uuid, p_email text) returns void language plpgsql as $$
begin
  perform set_config('role','authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub',p_uid,'email',p_email,'role','authenticated')::text, true);
end $$;

insert into auth.users (instance_id,id,aud,role,email,raw_app_meta_data,raw_user_meta_data,
  created_at,updated_at,confirmation_token,email_change,email_change_token_new,recovery_token)
values ('00000000-0000-0000-0000-000000000000','0f000000-0000-0000-0000-00000000000f','authenticated','authenticated','o@t.co','{}','{"display_name":"O"}',now(),now(),'','','','');

insert into public.projects (id,name,status,timezone,currency) values
 ('ff000000-0000-0000-0000-0000000000ff','PF','active','UTC','GBP');
insert into public.project_members (id,project_id,user_id,display_name,email,role,status) values
 ('ff100000-0000-0000-0000-00000000000f','ff000000-0000-0000-0000-0000000000ff','0f000000-0000-0000-0000-00000000000f','O','o@t.co','organizer','active'),
 ('ff100000-0000-0000-0000-000000000001','ff000000-0000-0000-0000-0000000000ff',null,'M1','m1@t.co','member','active'),
 ('ff100000-0000-0000-0000-000000000002','ff000000-0000-0000-0000-0000000000ff',null,'M2','m2@t.co','member','active'),
 ('ff100000-0000-0000-0000-000000000003','ff000000-0000-0000-0000-0000000000ff',null,'M3','m3@t.co','member','active');
update public.projects set created_by='ff100000-0000-0000-0000-00000000000f' where id='ff000000-0000-0000-0000-0000000000ff';

insert into public.budgets (project_id,total_target_minor) values ('ff000000-0000-0000-0000-0000000000ff',100000);

insert into public.commitments (id,project_id,title,kind,status,confirmed_cost_minor,estimated_cost_minor) values
 ('fc000000-0000-0000-0000-000000000001','ff000000-0000-0000-0000-0000000000ff','C1','experience','confirmed',30000,null),
 ('fc000000-0000-0000-0000-000000000002','ff000000-0000-0000-0000-0000000000ff','C2','food','researching',null,20000),
 ('fc000000-0000-0000-0000-000000000003','ff000000-0000-0000-0000-0000000000ff','C3','other','researching',50000,null);

insert into public.commitment_participants (project_id,commitment_id,member_id)
select 'ff000000-0000-0000-0000-0000000000ff','fc000000-0000-0000-0000-000000000001', m.id
from public.project_members m
where m.project_id='ff000000-0000-0000-0000-0000000000ff' and m.display_name in ('M1','M2','M3');

-- payments
insert into public.payments (project_id,commitment_id,type,direction,status,amount_minor,due_on,paid_on,paid_by_member_id) values
 ('ff000000-0000-0000-0000-0000000000ff','fc000000-0000-0000-0000-000000000001','deposit','outgoing','paid',12000,null,current_date-1,'ff100000-0000-0000-0000-000000000001'),
 ('ff000000-0000-0000-0000-0000000000ff','fc000000-0000-0000-0000-000000000001','balance','outgoing','scheduled',18000,current_date+30,null,null),
 ('ff000000-0000-0000-0000-0000000000ff','fc000000-0000-0000-0000-000000000003','full','outgoing','paid',5000,null,current_date-1,'ff100000-0000-0000-0000-000000000002');

-- now cancel C3 (its PAID payment must survive)
update public.commitments set status='cancelled' where id='fc000000-0000-0000-0000-000000000003';

select pg_temp.login('0f000000-0000-0000-0000-00000000000f','o@t.co');

select is( (select total_cost_minor        from public.v_project_financials where project_id='ff000000-0000-0000-0000-0000000000ff'), 50000::bigint, 'total_cost = C1+C2 (C3 cancelled excluded)');
select is( (select committed_spend_minor   from public.v_project_financials where project_id='ff000000-0000-0000-0000-0000000000ff'), 30000::bigint, 'committed_spend = C1 only');
select is( (select gross_paid_minor        from public.v_project_financials where project_id='ff000000-0000-0000-0000-0000000000ff'), 17000::bigint, 'gross_paid = 12000 + 5000 (5000 on a CANCELLED commitment is preserved)');
select is( (select net_actual_spend_minor  from public.v_project_financials where project_id='ff000000-0000-0000-0000-0000000000ff'), 17000::bigint, 'net_actual_spend = gross_paid - refunds');
select is( (select outstanding_minor       from public.v_project_financials where project_id='ff000000-0000-0000-0000-0000000000ff'), 18000::bigint, 'outstanding = C1 (30000 - 12000)');
select is( (select scheduled_outstanding_minor from public.v_project_financials where project_id='ff000000-0000-0000-0000-0000000000ff'), 18000::bigint, 'scheduled_outstanding = the C1 balance payment');
select is( (select remaining_budget_minor  from public.v_project_financials where project_id='ff000000-0000-0000-0000-0000000000ff'), 50000::bigint, 'remaining_budget = target - total_cost');
select is( (select settled_variance_minor  from public.v_project_financials where project_id='ff000000-0000-0000-0000-0000000000ff'), 83000::bigint, 'settled_variance = target - net_actual_spend');
select is( (select progress_pct            from public.v_project_financials where project_id='ff000000-0000-0000-0000-0000000000ff'), 50, 'progress = 1 of 2 non-cancelled committed');

select is( (select payment_progress from public.v_commitment_financials where commitment_id='fc000000-0000-0000-0000-000000000001'), 'deposit_paid', 'C1 payment_progress = deposit_paid');

select is( (select balance_minor from public.v_member_balances where member_id='ff100000-0000-0000-0000-000000000001'),  2000::bigint, 'M1 balance = +2000 (paid 12000, owes 10000)');
select is( (select balance_minor from public.v_member_balances where member_id='ff100000-0000-0000-0000-000000000002'), -5000::bigint, 'M2 balance = -5000 (paid 5000, owes 10000)');
select is( (select balance_minor from public.v_member_balances where member_id='ff100000-0000-0000-0000-000000000003'),-10000::bigint, 'M3 balance = -10000 (paid 0, owes 10000)');

select * from finish();
rollback;
