begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
CREATE OR REPLACE FUNCTION pg_temp.original_can_read_reimbursement(p_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select exists(select 1 from public.reimbursement_requests r
 join public.projects p on p.id=r.project_id join public.commitments c on c.id=r.commitment_id
 join public.payments pay on pay.id=r.payment_id
 where r.id=p_id and app.is_member(r.project_id) and p.deleted_at is null and c.deleted_at is null and pay.deleted_at is null
 and (app.is_organizer(r.project_id) or app.current_member_id(r.project_id) in (r.debtor_member_id,r.creditor_member_id)));
$function$;

CREATE OR REPLACE FUNCTION pg_temp.original_can_confirm_reimbursement(p_ack uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select exists(select 1 from public.reimbursement_payment_acknowledgements a
 join public.reimbursement_requests r on r.id=a.reimbursement_request_id
 join public.project_members d on d.id=r.debtor_member_id join public.project_members c on c.id=r.creditor_member_id
 join public.commitments activity on activity.id=r.commitment_id
 where a.id=p_ack and a.withdrawn_at is null and a.debtor_member_id=r.debtor_member_id
 and app.can_read_reimbursement(r.id) and app.is_writable_project(r.project_id) and activity.status<>'cancelled'
 and r.status='open' and not app.reimbursement_needs_review(r.id)
 and c.user_id=auth.uid() and c.status='active' and c.deleted_at is null and d.status='active' and d.deleted_at is null
 and not exists(select 1 from public.reimbursement_receipt_confirmations f where f.reimbursement_request_id=r.id)
 and r.amount_minor<=(select remaining_minor from public.v_activity_member_settlements where commitment_id=r.commitment_id and member_id=r.debtor_member_id)
 and r.amount_minor<=(select -remaining_minor from public.v_activity_member_settlements where commitment_id=r.commitment_id and member_id=r.creditor_member_id));
$function$;

create function pg_temp.login(i integer) returns void language plpgsql as $$ begin
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub','40100000-0000-4000-8000-'||lpad(i::text,12,'0'),'role','authenticated')::text,true);
end $$;
insert into auth.users(instance_id,id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,confirmation_token,email_change,email_change_token_new,recovery_token)
select '00000000-0000-0000-0000-000000000000',('40100000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'authenticated','authenticated','reimbursement-test-'||i||'@example.test','{}','{}',now(),now(),'','','','' from generate_series(1,6) i;
select pg_temp.login(1);
create temp table ctx as select public.create_project('Receipt confirmation fixture','UTC','GBP','2026-01-01') id;
create temp table cat as with c as(insert into public.project_areas(project_id,title) select id,'Villa' from ctx returning id) select * from c;
set local role postgres;
insert into public.project_members(project_id,user_id,display_name,role,status)
select ctx.id,('40100000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'Reimbursement member '||i,case when i=4 then 'viewer' else 'member' end::public.member_role,'active' from ctx,generate_series(2,4) i;
create temp table members as select right(user_id::text,1)::int n,id from public.project_members where project_id=(select id from ctx);
grant select on members to authenticated;
select pg_temp.login(1);
create temp table activity as select (public.create_activity_in_category((select id from ctx),(select id from cat),'{"title":"Villa","kind":"other","activity_type":"task","estimated_cost_minor":90000}',null)).id;
select public.set_activity_cost_split((select id from activity),jsonb_build_object('mode','even','cost',90000,'members',(select jsonb_agg(id order by id) from members where n<=3)));
create temp table payment as with p as(insert into public.payments(project_id,commitment_id,paid_by_member_id,type,direction,status,amount_minor,paid_on) select ctx.id,activity.id,members.id,'full','outgoing','paid',90000,current_date from ctx,activity,members where n=1 returning id) select * from p;
insert into public.activity_payment_schedules(project_id,commitment_id,title,amount_minor,due_on) select ctx.id,activity.id,'Vendor schedule',90000,current_date+30 from ctx,activity;
create temp table before_schedules as select jsonb_agg(to_jsonb(s) order by payment_schedule_id) doc from public.v_activity_payment_schedule_financials s where project_id=(select id from ctx);
create temp table before_financial as select to_jsonb(f) doc from public.v_project_financials f where project_id=(select id from ctx);
create temp table before_balances as select jsonb_agg(to_jsonb(s) order by member_id) doc from public.v_activity_member_settlements s where commitment_id=(select id from activity);
create temp table before_member_balances as select jsonb_agg(to_jsonb(s) order by member_id) doc from public.v_member_balances s where project_id=(select id from ctx);
create temp table before_shares as select jsonb_agg(to_jsonb(s) order by member_id) doc from public.cost_shares s where commitment_id=(select id from activity);
create temp table request_a as select public.create_reimbursement((select id from payment),(select id from members where n=2),30000) id;
create temp table request_b as select public.create_reimbursement((select id from payment),(select id from members where n=3),30000) id;
set local role postgres;
update public.project_members set role='organizer' where project_id=(select id from ctx) and user_id='40100000-0000-4000-8000-000000000003';
select pg_temp.login(1);create temp table ack(id uuid);grant select,insert on ack to authenticated;
set local role postgres;
select pg_temp.login(1);
select ok((select bool_and(app.can_read_reimbursement(id) is not distinct from pg_temp.original_can_read_reimbursement(id)) from (select id from request_a union all select id from request_b union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'pending: actor 1 reimbursement visibility equals original');
select ok((select bool_and(app.can_confirm_reimbursement(id) is not distinct from pg_temp.original_can_confirm_reimbursement(id)) from (select id from ack union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'pending: actor 1 confirmation eligibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'pending: actor 1 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'pending: actor 1 unread membership remains correct');
select pg_temp.login(2);
select ok((select bool_and(app.can_read_reimbursement(id) is not distinct from pg_temp.original_can_read_reimbursement(id)) from (select id from request_a union all select id from request_b union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'pending: actor 2 reimbursement visibility equals original');
select ok((select bool_and(app.can_confirm_reimbursement(id) is not distinct from pg_temp.original_can_confirm_reimbursement(id)) from (select id from ack union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'pending: actor 2 confirmation eligibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'pending: actor 2 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'pending: actor 2 unread membership remains correct');
select pg_temp.login(3);
select ok((select bool_and(app.can_read_reimbursement(id) is not distinct from pg_temp.original_can_read_reimbursement(id)) from (select id from request_a union all select id from request_b union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'pending: actor 3 reimbursement visibility equals original');
select ok((select bool_and(app.can_confirm_reimbursement(id) is not distinct from pg_temp.original_can_confirm_reimbursement(id)) from (select id from ack union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'pending: actor 3 confirmation eligibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'pending: actor 3 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'pending: actor 3 unread membership remains correct');
select pg_temp.login(4);
select ok((select bool_and(app.can_read_reimbursement(id) is not distinct from pg_temp.original_can_read_reimbursement(id)) from (select id from request_a union all select id from request_b union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'pending: actor 4 reimbursement visibility equals original');
select ok((select bool_and(app.can_confirm_reimbursement(id) is not distinct from pg_temp.original_can_confirm_reimbursement(id)) from (select id from ack union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'pending: actor 4 confirmation eligibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'pending: actor 4 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'pending: actor 4 unread membership remains correct');
select pg_temp.login(5);
select ok((select bool_and(app.can_read_reimbursement(id) is not distinct from pg_temp.original_can_read_reimbursement(id)) from (select id from request_a union all select id from request_b union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'pending: actor 5 reimbursement visibility equals original');
select ok((select bool_and(app.can_confirm_reimbursement(id) is not distinct from pg_temp.original_can_confirm_reimbursement(id)) from (select id from ack union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'pending: actor 5 confirmation eligibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'pending: actor 5 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'pending: actor 5 unread membership remains correct');
select is((select count(*) from public.v_reimbursement_payment_status where reimbursement_request_id in(select id from request_a union all select id from request_b)),0::bigint,'pending: outsider 5 status hidden');
select is((select count(*) from public.v_my_notification_inbox),0::bigint,'pending: outsider 5 inbox empty');
select pg_temp.login(6);
select ok((select bool_and(app.can_read_reimbursement(id) is not distinct from pg_temp.original_can_read_reimbursement(id)) from (select id from request_a union all select id from request_b union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'pending: actor 6 reimbursement visibility equals original');
select ok((select bool_and(app.can_confirm_reimbursement(id) is not distinct from pg_temp.original_can_confirm_reimbursement(id)) from (select id from ack union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'pending: actor 6 confirmation eligibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'pending: actor 6 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'pending: actor 6 unread membership remains correct');
select is((select count(*) from public.v_reimbursement_payment_status where reimbursement_request_id in(select id from request_a union all select id from request_b)),0::bigint,'pending: outsider 6 status hidden');
select is((select count(*) from public.v_my_notification_inbox),0::bigint,'pending: outsider 6 inbox empty');
select pg_temp.login(2);insert into ack select public.acknowledge_reimbursement_payment((select id from request_a));
set local role postgres;
select pg_temp.login(1);
select ok((select bool_and(app.can_read_reimbursement(id) is not distinct from pg_temp.original_can_read_reimbursement(id)) from (select id from request_a union all select id from request_b union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'marked paid: actor 1 reimbursement visibility equals original');
select ok((select bool_and(app.can_confirm_reimbursement(id) is not distinct from pg_temp.original_can_confirm_reimbursement(id)) from (select id from ack union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'marked paid: actor 1 confirmation eligibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'marked paid: actor 1 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'marked paid: actor 1 unread membership remains correct');
select pg_temp.login(2);
select ok((select bool_and(app.can_read_reimbursement(id) is not distinct from pg_temp.original_can_read_reimbursement(id)) from (select id from request_a union all select id from request_b union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'marked paid: actor 2 reimbursement visibility equals original');
select ok((select bool_and(app.can_confirm_reimbursement(id) is not distinct from pg_temp.original_can_confirm_reimbursement(id)) from (select id from ack union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'marked paid: actor 2 confirmation eligibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'marked paid: actor 2 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'marked paid: actor 2 unread membership remains correct');
select pg_temp.login(3);
select ok((select bool_and(app.can_read_reimbursement(id) is not distinct from pg_temp.original_can_read_reimbursement(id)) from (select id from request_a union all select id from request_b union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'marked paid: actor 3 reimbursement visibility equals original');
select ok((select bool_and(app.can_confirm_reimbursement(id) is not distinct from pg_temp.original_can_confirm_reimbursement(id)) from (select id from ack union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'marked paid: actor 3 confirmation eligibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'marked paid: actor 3 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'marked paid: actor 3 unread membership remains correct');
select pg_temp.login(4);
select ok((select bool_and(app.can_read_reimbursement(id) is not distinct from pg_temp.original_can_read_reimbursement(id)) from (select id from request_a union all select id from request_b union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'marked paid: actor 4 reimbursement visibility equals original');
select ok((select bool_and(app.can_confirm_reimbursement(id) is not distinct from pg_temp.original_can_confirm_reimbursement(id)) from (select id from ack union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'marked paid: actor 4 confirmation eligibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'marked paid: actor 4 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'marked paid: actor 4 unread membership remains correct');
select pg_temp.login(5);
select ok((select bool_and(app.can_read_reimbursement(id) is not distinct from pg_temp.original_can_read_reimbursement(id)) from (select id from request_a union all select id from request_b union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'marked paid: actor 5 reimbursement visibility equals original');
select ok((select bool_and(app.can_confirm_reimbursement(id) is not distinct from pg_temp.original_can_confirm_reimbursement(id)) from (select id from ack union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'marked paid: actor 5 confirmation eligibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'marked paid: actor 5 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'marked paid: actor 5 unread membership remains correct');
select is((select count(*) from public.v_reimbursement_payment_status where reimbursement_request_id in(select id from request_a union all select id from request_b)),0::bigint,'marked paid: outsider 5 status hidden');
select is((select count(*) from public.v_my_notification_inbox),0::bigint,'marked paid: outsider 5 inbox empty');
select pg_temp.login(6);
select ok((select bool_and(app.can_read_reimbursement(id) is not distinct from pg_temp.original_can_read_reimbursement(id)) from (select id from request_a union all select id from request_b union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'marked paid: actor 6 reimbursement visibility equals original');
select ok((select bool_and(app.can_confirm_reimbursement(id) is not distinct from pg_temp.original_can_confirm_reimbursement(id)) from (select id from ack union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'marked paid: actor 6 confirmation eligibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'marked paid: actor 6 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'marked paid: actor 6 unread membership remains correct');
select is((select count(*) from public.v_reimbursement_payment_status where reimbursement_request_id in(select id from request_a union all select id from request_b)),0::bigint,'marked paid: outsider 6 status hidden');
select is((select count(*) from public.v_my_notification_inbox),0::bigint,'marked paid: outsider 6 inbox empty');
select pg_temp.login(1);create temp table confirmation as select public.confirm_reimbursement_receipt((select id from ack)) id;
set local role postgres;
select pg_temp.login(1);
select ok((select bool_and(app.can_read_reimbursement(id) is not distinct from pg_temp.original_can_read_reimbursement(id)) from (select id from request_a union all select id from request_b union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'confirmed: actor 1 reimbursement visibility equals original');
select ok((select bool_and(app.can_confirm_reimbursement(id) is not distinct from pg_temp.original_can_confirm_reimbursement(id)) from (select id from ack union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'confirmed: actor 1 confirmation eligibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'confirmed: actor 1 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'confirmed: actor 1 unread membership remains correct');
select pg_temp.login(2);
select ok((select bool_and(app.can_read_reimbursement(id) is not distinct from pg_temp.original_can_read_reimbursement(id)) from (select id from request_a union all select id from request_b union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'confirmed: actor 2 reimbursement visibility equals original');
select ok((select bool_and(app.can_confirm_reimbursement(id) is not distinct from pg_temp.original_can_confirm_reimbursement(id)) from (select id from ack union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'confirmed: actor 2 confirmation eligibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'confirmed: actor 2 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'confirmed: actor 2 unread membership remains correct');
select pg_temp.login(3);
select ok((select bool_and(app.can_read_reimbursement(id) is not distinct from pg_temp.original_can_read_reimbursement(id)) from (select id from request_a union all select id from request_b union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'confirmed: actor 3 reimbursement visibility equals original');
select ok((select bool_and(app.can_confirm_reimbursement(id) is not distinct from pg_temp.original_can_confirm_reimbursement(id)) from (select id from ack union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'confirmed: actor 3 confirmation eligibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'confirmed: actor 3 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'confirmed: actor 3 unread membership remains correct');
select pg_temp.login(4);
select ok((select bool_and(app.can_read_reimbursement(id) is not distinct from pg_temp.original_can_read_reimbursement(id)) from (select id from request_a union all select id from request_b union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'confirmed: actor 4 reimbursement visibility equals original');
select ok((select bool_and(app.can_confirm_reimbursement(id) is not distinct from pg_temp.original_can_confirm_reimbursement(id)) from (select id from ack union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'confirmed: actor 4 confirmation eligibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'confirmed: actor 4 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'confirmed: actor 4 unread membership remains correct');
select pg_temp.login(5);
select ok((select bool_and(app.can_read_reimbursement(id) is not distinct from pg_temp.original_can_read_reimbursement(id)) from (select id from request_a union all select id from request_b union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'confirmed: actor 5 reimbursement visibility equals original');
select ok((select bool_and(app.can_confirm_reimbursement(id) is not distinct from pg_temp.original_can_confirm_reimbursement(id)) from (select id from ack union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'confirmed: actor 5 confirmation eligibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'confirmed: actor 5 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'confirmed: actor 5 unread membership remains correct');
select is((select count(*) from public.v_reimbursement_payment_status where reimbursement_request_id in(select id from request_a union all select id from request_b)),0::bigint,'confirmed: outsider 5 status hidden');
select is((select count(*) from public.v_my_notification_inbox),0::bigint,'confirmed: outsider 5 inbox empty');
select pg_temp.login(6);
select ok((select bool_and(app.can_read_reimbursement(id) is not distinct from pg_temp.original_can_read_reimbursement(id)) from (select id from request_a union all select id from request_b union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'confirmed: actor 6 reimbursement visibility equals original');
select ok((select bool_and(app.can_confirm_reimbursement(id) is not distinct from pg_temp.original_can_confirm_reimbursement(id)) from (select id from ack union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'confirmed: actor 6 confirmation eligibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'confirmed: actor 6 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'confirmed: actor 6 unread membership remains correct');
select is((select count(*) from public.v_reimbursement_payment_status where reimbursement_request_id in(select id from request_a union all select id from request_b)),0::bigint,'confirmed: outsider 6 status hidden');
select is((select count(*) from public.v_my_notification_inbox),0::bigint,'confirmed: outsider 6 inbox empty');
select pg_temp.login(1);
select is((select confirmation_state from public.v_reimbursement_payment_status where reimbursement_request_id=(select id from request_a)),'settled','Confirmed state remains settled');
select public.cancel_item_settlement((select settlement_group_id from public.reimbursement_receipt_confirmations where id=(select id from confirmation)));
set local role postgres;
select pg_temp.login(1);
select ok((select bool_and(app.can_read_reimbursement(id) is not distinct from pg_temp.original_can_read_reimbursement(id)) from (select id from request_a union all select id from request_b union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'reversed: actor 1 reimbursement visibility equals original');
select ok((select bool_and(app.can_confirm_reimbursement(id) is not distinct from pg_temp.original_can_confirm_reimbursement(id)) from (select id from ack union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'reversed: actor 1 confirmation eligibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'reversed: actor 1 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'reversed: actor 1 unread membership remains correct');
select pg_temp.login(2);
select ok((select bool_and(app.can_read_reimbursement(id) is not distinct from pg_temp.original_can_read_reimbursement(id)) from (select id from request_a union all select id from request_b union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'reversed: actor 2 reimbursement visibility equals original');
select ok((select bool_and(app.can_confirm_reimbursement(id) is not distinct from pg_temp.original_can_confirm_reimbursement(id)) from (select id from ack union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'reversed: actor 2 confirmation eligibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'reversed: actor 2 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'reversed: actor 2 unread membership remains correct');
select pg_temp.login(3);
select ok((select bool_and(app.can_read_reimbursement(id) is not distinct from pg_temp.original_can_read_reimbursement(id)) from (select id from request_a union all select id from request_b union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'reversed: actor 3 reimbursement visibility equals original');
select ok((select bool_and(app.can_confirm_reimbursement(id) is not distinct from pg_temp.original_can_confirm_reimbursement(id)) from (select id from ack union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'reversed: actor 3 confirmation eligibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'reversed: actor 3 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'reversed: actor 3 unread membership remains correct');
select pg_temp.login(4);
select ok((select bool_and(app.can_read_reimbursement(id) is not distinct from pg_temp.original_can_read_reimbursement(id)) from (select id from request_a union all select id from request_b union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'reversed: actor 4 reimbursement visibility equals original');
select ok((select bool_and(app.can_confirm_reimbursement(id) is not distinct from pg_temp.original_can_confirm_reimbursement(id)) from (select id from ack union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'reversed: actor 4 confirmation eligibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'reversed: actor 4 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'reversed: actor 4 unread membership remains correct');
select pg_temp.login(5);
select ok((select bool_and(app.can_read_reimbursement(id) is not distinct from pg_temp.original_can_read_reimbursement(id)) from (select id from request_a union all select id from request_b union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'reversed: actor 5 reimbursement visibility equals original');
select ok((select bool_and(app.can_confirm_reimbursement(id) is not distinct from pg_temp.original_can_confirm_reimbursement(id)) from (select id from ack union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'reversed: actor 5 confirmation eligibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'reversed: actor 5 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'reversed: actor 5 unread membership remains correct');
select is((select count(*) from public.v_reimbursement_payment_status where reimbursement_request_id in(select id from request_a union all select id from request_b)),0::bigint,'reversed: outsider 5 status hidden');
select is((select count(*) from public.v_my_notification_inbox),0::bigint,'reversed: outsider 5 inbox empty');
select pg_temp.login(6);
select ok((select bool_and(app.can_read_reimbursement(id) is not distinct from pg_temp.original_can_read_reimbursement(id)) from (select id from request_a union all select id from request_b union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'reversed: actor 6 reimbursement visibility equals original');
select ok((select bool_and(app.can_confirm_reimbursement(id) is not distinct from pg_temp.original_can_confirm_reimbursement(id)) from (select id from ack union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'reversed: actor 6 confirmation eligibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'reversed: actor 6 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'reversed: actor 6 unread membership remains correct');
select is((select count(*) from public.v_reimbursement_payment_status where reimbursement_request_id in(select id from request_a union all select id from request_b)),0::bigint,'reversed: outsider 6 status hidden');
select is((select count(*) from public.v_my_notification_inbox),0::bigint,'reversed: outsider 6 inbox empty');
select pg_temp.login(1);
select is((select confirmation_state from public.v_reimbursement_payment_status where reimbursement_request_id=(select id from request_a)),'reversed','Reversed confirmation remains historical');
insert into public.payments(project_id,commitment_id,paid_by_member_id,type,direction,status,amount_minor,paid_on) select ctx.id,activity.id,members.id,'refund','incoming','paid',1000,current_date from ctx,activity,members where n=1;
set local role postgres;
select pg_temp.login(1);
select ok((select bool_and(app.can_read_reimbursement(id) is not distinct from pg_temp.original_can_read_reimbursement(id)) from (select id from request_a union all select id from request_b union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'refunded: actor 1 reimbursement visibility equals original');
select ok((select bool_and(app.can_confirm_reimbursement(id) is not distinct from pg_temp.original_can_confirm_reimbursement(id)) from (select id from ack union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'refunded: actor 1 confirmation eligibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'refunded: actor 1 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'refunded: actor 1 unread membership remains correct');
select pg_temp.login(2);
select ok((select bool_and(app.can_read_reimbursement(id) is not distinct from pg_temp.original_can_read_reimbursement(id)) from (select id from request_a union all select id from request_b union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'refunded: actor 2 reimbursement visibility equals original');
select ok((select bool_and(app.can_confirm_reimbursement(id) is not distinct from pg_temp.original_can_confirm_reimbursement(id)) from (select id from ack union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'refunded: actor 2 confirmation eligibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'refunded: actor 2 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'refunded: actor 2 unread membership remains correct');
select pg_temp.login(3);
select ok((select bool_and(app.can_read_reimbursement(id) is not distinct from pg_temp.original_can_read_reimbursement(id)) from (select id from request_a union all select id from request_b union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'refunded: actor 3 reimbursement visibility equals original');
select ok((select bool_and(app.can_confirm_reimbursement(id) is not distinct from pg_temp.original_can_confirm_reimbursement(id)) from (select id from ack union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'refunded: actor 3 confirmation eligibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'refunded: actor 3 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'refunded: actor 3 unread membership remains correct');
select pg_temp.login(4);
select ok((select bool_and(app.can_read_reimbursement(id) is not distinct from pg_temp.original_can_read_reimbursement(id)) from (select id from request_a union all select id from request_b union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'refunded: actor 4 reimbursement visibility equals original');
select ok((select bool_and(app.can_confirm_reimbursement(id) is not distinct from pg_temp.original_can_confirm_reimbursement(id)) from (select id from ack union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'refunded: actor 4 confirmation eligibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'refunded: actor 4 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'refunded: actor 4 unread membership remains correct');
select pg_temp.login(5);
select ok((select bool_and(app.can_read_reimbursement(id) is not distinct from pg_temp.original_can_read_reimbursement(id)) from (select id from request_a union all select id from request_b union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'refunded: actor 5 reimbursement visibility equals original');
select ok((select bool_and(app.can_confirm_reimbursement(id) is not distinct from pg_temp.original_can_confirm_reimbursement(id)) from (select id from ack union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'refunded: actor 5 confirmation eligibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'refunded: actor 5 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'refunded: actor 5 unread membership remains correct');
select is((select count(*) from public.v_reimbursement_payment_status where reimbursement_request_id in(select id from request_a union all select id from request_b)),0::bigint,'refunded: outsider 5 status hidden');
select is((select count(*) from public.v_my_notification_inbox),0::bigint,'refunded: outsider 5 inbox empty');
select pg_temp.login(6);
select ok((select bool_and(app.can_read_reimbursement(id) is not distinct from pg_temp.original_can_read_reimbursement(id)) from (select id from request_a union all select id from request_b union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'refunded: actor 6 reimbursement visibility equals original');
select ok((select bool_and(app.can_confirm_reimbursement(id) is not distinct from pg_temp.original_can_confirm_reimbursement(id)) from (select id from ack union all select '00000000-0000-0000-0000-000000000000'::uuid) x),'refunded: actor 6 confirmation eligibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'refunded: actor 6 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'refunded: actor 6 unread membership remains correct');
select is((select count(*) from public.v_reimbursement_payment_status where reimbursement_request_id in(select id from request_a union all select id from request_b)),0::bigint,'refunded: outsider 6 status hidden');
select is((select count(*) from public.v_my_notification_inbox),0::bigint,'refunded: outsider 6 inbox empty');
set local role postgres;
select ok((select bool_and(relrowsecurity and relforcerowsecurity) from pg_class where oid in('public.reimbursement_requests'::regclass,'public.reimbursement_receipt_confirmations'::regclass)),'Reimbursement tables keep FORCE RLS');
select ok((select relrowsecurity from pg_class where oid='public.notifications'::regclass),'Notifications retain existing RLS');
select * from finish();
rollback;
