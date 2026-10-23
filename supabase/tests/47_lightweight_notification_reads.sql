begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
-- Reference is the pre-simplification inbox; normalize only intentional event-summary titles.
create temp view original_inbox with(security_invoker=true) as  SELECT v_my_activity_notifications.id,
    v_my_activity_notifications.project_id,
    v_my_activity_notifications.created_at,
    v_my_activity_notifications.read_at,
    'activity_created'::text AS kind,
    'activities'::text AS category,
    'activity'::text AS resource_type,
    v_my_activity_notifications.commitment_id AS resource_id,
    NULL::text AS section,
    'New activity'::text AS title,
    ((v_my_activity_notifications.activity_title || ' was added to '::text) || v_my_activity_notifications.project_name) || '.'::text AS body
   FROM v_my_activity_notifications
UNION ALL
 SELECT v_my_join_notifications.id,
    v_my_join_notifications.project_id,
    v_my_join_notifications.created_at,
    v_my_join_notifications.read_at,
    v_my_join_notifications.kind,
    'project_access'::text AS category,
    'project'::text AS resource_type,
    v_my_join_notifications.project_id AS resource_id,
        CASE
            WHEN v_my_join_notifications.kind = 'project_join_requested'::text THEN 'people'::text
            ELSE NULL::text
        END AS section,
        CASE
            WHEN v_my_join_notifications.kind = 'project_join_requested'::text THEN 'New project access request'::text
            ELSE 'Your access was approved'::text
        END AS title,
    v_my_join_notifications.project_name AS body
   FROM v_my_join_notifications
UNION ALL
 SELECT v_my_decision_notifications.id,
    v_my_decision_notifications.project_id,
    v_my_decision_notifications.created_at,
    v_my_decision_notifications.read_at,
    v_my_decision_notifications.kind,
    'decisions'::text AS category,
    'decision'::text AS resource_type,
    v_my_decision_notifications.decision_id AS resource_id,
    NULL::text AS section,
        CASE
            WHEN v_my_decision_notifications.kind = 'decision_resolved'::text THEN 'Decision resolved'::text
            ELSE 'Voting closed'::text
        END AS title,
    v_my_decision_notifications.decision_title ||
        CASE
            WHEN v_my_decision_notifications.kind = 'decision_resolved'::text THEN (' — '::text || COALESCE(v_my_decision_notifications.selected_title, 'An option'::text)) || ' was selected.'::text
            ELSE ' — Ready to resolve.'::text
        END AS body
   FROM v_my_decision_notifications
UNION ALL
 SELECT v_my_payment_notifications.id,
    v_my_payment_notifications.project_id,
    v_my_payment_notifications.created_at,
    v_my_payment_notifications.read_at,
    'payment_due_soon'::text AS kind,
    'payments'::text AS category,
    'activity'::text AS resource_type,
    v_my_payment_notifications.commitment_id AS resource_id,
    'payments'::text AS section,
        CASE
            WHEN v_my_payment_notifications.outstanding_minor > 0 THEN 'Payment due soon'::text
            ELSE 'Payment completed'::text
        END AS title,
    (v_my_payment_notifications.title || ' — Due '::text) || to_char(v_my_payment_notifications.due_on::timestamp with time zone, 'FMDD Month YYYY'::text) AS body
   FROM v_my_payment_notifications
UNION ALL
 SELECT v_my_reimbursement_notifications.id,
    v_my_reimbursement_notifications.project_id,
    v_my_reimbursement_notifications.created_at,
    v_my_reimbursement_notifications.read_at,
    'reimbursement_created'::text AS kind,
    'reimbursements'::text AS category,
    'activity'::text AS resource_type,
    v_my_reimbursement_notifications.commitment_id AS resource_id,
    'reimbursements'::text AS section,
        CASE
            WHEN v_my_reimbursement_notifications.needs_review THEN 'Reimbursement needs review'::text
            ELSE 'Reimbursement requested'::text
        END AS title,
    (v_my_reimbursement_notifications.activity_title || ' — '::text) || v_my_reimbursement_notifications.creditor_name AS body
   FROM v_my_reimbursement_notifications
UNION ALL
 SELECT v_my_payment_acknowledgement_notifications.id,
    v_my_payment_acknowledgement_notifications.project_id,
    v_my_payment_acknowledgement_notifications.created_at,
    v_my_payment_acknowledgement_notifications.read_at,
    v_my_payment_acknowledgement_notifications.kind,
    'reimbursements'::text AS category,
    'activity'::text AS resource_type,
    v_my_payment_acknowledgement_notifications.commitment_id AS resource_id,
    'reimbursements'::text AS section,
        CASE
            WHEN v_my_payment_acknowledgement_notifications.needs_review THEN 'Reimbursement needs review'::text
            WHEN v_my_payment_acknowledgement_notifications.kind = 'reimbursement_payment_acknowledged'::text THEN 'Payment marked as sent'::text
            ELSE 'Payment claim withdrawn'::text
        END AS title,
    (v_my_payment_acknowledgement_notifications.activity_title || ' — '::text) || v_my_payment_acknowledgement_notifications.debtor_name AS body
   FROM v_my_payment_acknowledgement_notifications
UNION ALL
 SELECT v_my_receipt_confirmation_notifications.id,
    v_my_receipt_confirmation_notifications.project_id,
    v_my_receipt_confirmation_notifications.created_at,
    v_my_receipt_confirmation_notifications.read_at,
    'reimbursement_receipt_confirmed'::text AS kind,
    'reimbursements'::text AS category,
    'activity'::text AS resource_type,
    v_my_receipt_confirmation_notifications.commitment_id AS resource_id,
    'reimbursements'::text AS section,
        CASE
            WHEN v_my_receipt_confirmation_notifications.confirmation_state = 'reversed'::text THEN 'Settlement reversed'::text
            ELSE 'Reimbursement settled'::text
        END AS title,
    (v_my_receipt_confirmation_notifications.activity_title || ' — '::text) || v_my_receipt_confirmation_notifications.creditor_name AS body
   FROM v_my_receipt_confirmation_notifications
UNION ALL
 SELECT n.id,
    n.project_id,
    n.created_at,
    n.read_at,
    n.kind,
    'activities'::text AS category,
    'activity'::text AS resource_type,
    c.id AS resource_id,
    NULL::text AS section,
    'Activity coming up'::text AS title,
    (c.title || ' — '::text) || to_char((c.starts_at AT TIME ZONE p.timezone), 'FMDD Month YYYY'::text) AS body
   FROM notifications n
     JOIN commitments c ON c.id = n.activity_reminder_id
     JOIN projects p ON p.id = n.project_id
  WHERE n.kind = 'activity_due_soon'::text AND c.deleted_at IS NULL AND p.deleted_at IS NULL AND c.status <> 'cancelled'::commitment_status;
grant select on original_inbox to authenticated;
create function pg_temp.inbox_matches() returns boolean language sql security invoker as $$
 select (select coalesce(jsonb_agg(to_jsonb(n) order by id),'[]') from public.v_my_notification_inbox n) =
 (select coalesce(jsonb_agg(to_jsonb(n)||jsonb_build_object('title',case kind when 'payment_due_soon' then 'Payment reminder' when 'reimbursement_created' then 'Reimbursement requested' when 'reimbursement_payment_acknowledged' then 'Payment marked as sent' when 'reimbursement_payment_acknowledgement_withdrawn' then 'Payment claim withdrawn' else title end) order by id),'[]') from pg_temp.original_inbox n);
$$;
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
select ok(pg_temp.inbox_matches(),'pending: actor 1 inbox rows, summaries and deep links equals original');
select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'pending: actor 1 boolean unread visibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'pending: actor 1 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'pending: actor 1 unread membership remains correct');
select pg_temp.login(2);
select ok(pg_temp.inbox_matches(),'pending: actor 2 inbox rows, summaries and deep links equals original');
select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'pending: actor 2 boolean unread visibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'pending: actor 2 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'pending: actor 2 unread membership remains correct');
select pg_temp.login(3);
select ok(pg_temp.inbox_matches(),'pending: actor 3 inbox rows, summaries and deep links equals original');
select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'pending: actor 3 boolean unread visibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'pending: actor 3 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'pending: actor 3 unread membership remains correct');
select pg_temp.login(4);
select ok(pg_temp.inbox_matches(),'pending: actor 4 inbox rows, summaries and deep links equals original');
select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'pending: actor 4 boolean unread visibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'pending: actor 4 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'pending: actor 4 unread membership remains correct');
select pg_temp.login(5);
select ok(pg_temp.inbox_matches(),'pending: actor 5 inbox rows, summaries and deep links equals original');
select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'pending: actor 5 boolean unread visibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'pending: actor 5 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'pending: actor 5 unread membership remains correct');
select is((select count(*) from public.v_reimbursement_payment_status where reimbursement_request_id in(select id from request_a union all select id from request_b)),0::bigint,'pending: outsider 5 status hidden');
select is((select count(*) from public.v_my_notification_inbox),0::bigint,'pending: outsider 5 inbox empty');
select pg_temp.login(6);
select ok(pg_temp.inbox_matches(),'pending: actor 6 inbox rows, summaries and deep links equals original');
select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'pending: actor 6 boolean unread visibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'pending: actor 6 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'pending: actor 6 unread membership remains correct');
select is((select count(*) from public.v_reimbursement_payment_status where reimbursement_request_id in(select id from request_a union all select id from request_b)),0::bigint,'pending: outsider 6 status hidden');
select is((select count(*) from public.v_my_notification_inbox),0::bigint,'pending: outsider 6 inbox empty');
select pg_temp.login(2);insert into ack select public.acknowledge_reimbursement_payment((select id from request_a));
set local role postgres;
select pg_temp.login(1);
select ok(pg_temp.inbox_matches(),'marked paid: actor 1 inbox rows, summaries and deep links equals original');
select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'marked paid: actor 1 boolean unread visibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'marked paid: actor 1 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'marked paid: actor 1 unread membership remains correct');
select pg_temp.login(2);
select ok(pg_temp.inbox_matches(),'marked paid: actor 2 inbox rows, summaries and deep links equals original');
select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'marked paid: actor 2 boolean unread visibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'marked paid: actor 2 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'marked paid: actor 2 unread membership remains correct');
select pg_temp.login(3);
select ok(pg_temp.inbox_matches(),'marked paid: actor 3 inbox rows, summaries and deep links equals original');
select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'marked paid: actor 3 boolean unread visibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'marked paid: actor 3 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'marked paid: actor 3 unread membership remains correct');
select pg_temp.login(4);
select ok(pg_temp.inbox_matches(),'marked paid: actor 4 inbox rows, summaries and deep links equals original');
select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'marked paid: actor 4 boolean unread visibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'marked paid: actor 4 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'marked paid: actor 4 unread membership remains correct');
select pg_temp.login(5);
select ok(pg_temp.inbox_matches(),'marked paid: actor 5 inbox rows, summaries and deep links equals original');
select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'marked paid: actor 5 boolean unread visibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'marked paid: actor 5 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'marked paid: actor 5 unread membership remains correct');
select is((select count(*) from public.v_reimbursement_payment_status where reimbursement_request_id in(select id from request_a union all select id from request_b)),0::bigint,'marked paid: outsider 5 status hidden');
select is((select count(*) from public.v_my_notification_inbox),0::bigint,'marked paid: outsider 5 inbox empty');
select pg_temp.login(6);
select ok(pg_temp.inbox_matches(),'marked paid: actor 6 inbox rows, summaries and deep links equals original');
select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'marked paid: actor 6 boolean unread visibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'marked paid: actor 6 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'marked paid: actor 6 unread membership remains correct');
select is((select count(*) from public.v_reimbursement_payment_status where reimbursement_request_id in(select id from request_a union all select id from request_b)),0::bigint,'marked paid: outsider 6 status hidden');
select is((select count(*) from public.v_my_notification_inbox),0::bigint,'marked paid: outsider 6 inbox empty');
select pg_temp.login(2);select public.withdraw_reimbursement_payment_acknowledgement((select id from ack));
select pg_temp.login(1);select ok(pg_temp.inbox_matches(),'Withdrawn claim: actor 1 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Withdrawn claim: actor 1 unread contract');
select pg_temp.login(2);select ok(pg_temp.inbox_matches(),'Withdrawn claim: actor 2 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Withdrawn claim: actor 2 unread contract');
select pg_temp.login(3);select ok(pg_temp.inbox_matches(),'Withdrawn claim: actor 3 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Withdrawn claim: actor 3 unread contract');
select pg_temp.login(4);select ok(pg_temp.inbox_matches(),'Withdrawn claim: actor 4 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Withdrawn claim: actor 4 unread contract');
select pg_temp.login(5);select ok(pg_temp.inbox_matches(),'Withdrawn claim: actor 5 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Withdrawn claim: actor 5 unread contract');
select pg_temp.login(6);select ok(pg_temp.inbox_matches(),'Withdrawn claim: actor 6 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Withdrawn claim: actor 6 unread contract');
set local role postgres;truncate ack;select pg_temp.login(2);insert into ack select public.acknowledge_reimbursement_payment((select id from request_a));
select pg_temp.login(1);create temp table confirmation as select public.confirm_reimbursement_receipt((select id from ack)) id;
set local role postgres;
select pg_temp.login(1);
select ok(pg_temp.inbox_matches(),'confirmed: actor 1 inbox rows, summaries and deep links equals original');
select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'confirmed: actor 1 boolean unread visibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'confirmed: actor 1 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'confirmed: actor 1 unread membership remains correct');
select pg_temp.login(2);
select ok(pg_temp.inbox_matches(),'confirmed: actor 2 inbox rows, summaries and deep links equals original');
select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'confirmed: actor 2 boolean unread visibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'confirmed: actor 2 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'confirmed: actor 2 unread membership remains correct');
select pg_temp.login(3);
select ok(pg_temp.inbox_matches(),'confirmed: actor 3 inbox rows, summaries and deep links equals original');
select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'confirmed: actor 3 boolean unread visibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'confirmed: actor 3 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'confirmed: actor 3 unread membership remains correct');
select pg_temp.login(4);
select ok(pg_temp.inbox_matches(),'confirmed: actor 4 inbox rows, summaries and deep links equals original');
select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'confirmed: actor 4 boolean unread visibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'confirmed: actor 4 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'confirmed: actor 4 unread membership remains correct');
select pg_temp.login(5);
select ok(pg_temp.inbox_matches(),'confirmed: actor 5 inbox rows, summaries and deep links equals original');
select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'confirmed: actor 5 boolean unread visibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'confirmed: actor 5 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'confirmed: actor 5 unread membership remains correct');
select is((select count(*) from public.v_reimbursement_payment_status where reimbursement_request_id in(select id from request_a union all select id from request_b)),0::bigint,'confirmed: outsider 5 status hidden');
select is((select count(*) from public.v_my_notification_inbox),0::bigint,'confirmed: outsider 5 inbox empty');
select pg_temp.login(6);
select ok(pg_temp.inbox_matches(),'confirmed: actor 6 inbox rows, summaries and deep links equals original');
select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'confirmed: actor 6 boolean unread visibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'confirmed: actor 6 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'confirmed: actor 6 unread membership remains correct');
select is((select count(*) from public.v_reimbursement_payment_status where reimbursement_request_id in(select id from request_a union all select id from request_b)),0::bigint,'confirmed: outsider 6 status hidden');
select is((select count(*) from public.v_my_notification_inbox),0::bigint,'confirmed: outsider 6 inbox empty');
select pg_temp.login(1);
select is((select confirmation_state from public.v_reimbursement_payment_status where reimbursement_request_id=(select id from request_a)),'settled','Confirmed state remains settled');
select public.cancel_item_settlement((select settlement_group_id from public.reimbursement_receipt_confirmations where id=(select id from confirmation)));
set local role postgres;
select pg_temp.login(1);
select ok(pg_temp.inbox_matches(),'reversed: actor 1 inbox rows, summaries and deep links equals original');
select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'reversed: actor 1 boolean unread visibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'reversed: actor 1 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'reversed: actor 1 unread membership remains correct');
select pg_temp.login(2);
select ok(pg_temp.inbox_matches(),'reversed: actor 2 inbox rows, summaries and deep links equals original');
select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'reversed: actor 2 boolean unread visibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'reversed: actor 2 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'reversed: actor 2 unread membership remains correct');
select pg_temp.login(3);
select ok(pg_temp.inbox_matches(),'reversed: actor 3 inbox rows, summaries and deep links equals original');
select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'reversed: actor 3 boolean unread visibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'reversed: actor 3 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'reversed: actor 3 unread membership remains correct');
select pg_temp.login(4);
select ok(pg_temp.inbox_matches(),'reversed: actor 4 inbox rows, summaries and deep links equals original');
select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'reversed: actor 4 boolean unread visibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'reversed: actor 4 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'reversed: actor 4 unread membership remains correct');
select pg_temp.login(5);
select ok(pg_temp.inbox_matches(),'reversed: actor 5 inbox rows, summaries and deep links equals original');
select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'reversed: actor 5 boolean unread visibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'reversed: actor 5 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'reversed: actor 5 unread membership remains correct');
select is((select count(*) from public.v_reimbursement_payment_status where reimbursement_request_id in(select id from request_a union all select id from request_b)),0::bigint,'reversed: outsider 5 status hidden');
select is((select count(*) from public.v_my_notification_inbox),0::bigint,'reversed: outsider 5 inbox empty');
select pg_temp.login(6);
select ok(pg_temp.inbox_matches(),'reversed: actor 6 inbox rows, summaries and deep links equals original');
select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'reversed: actor 6 boolean unread visibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'reversed: actor 6 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'reversed: actor 6 unread membership remains correct');
select is((select count(*) from public.v_reimbursement_payment_status where reimbursement_request_id in(select id from request_a union all select id from request_b)),0::bigint,'reversed: outsider 6 status hidden');
select is((select count(*) from public.v_my_notification_inbox),0::bigint,'reversed: outsider 6 inbox empty');
select pg_temp.login(1);
select is((select confirmation_state from public.v_reimbursement_payment_status where reimbursement_request_id=(select id from request_a)),'reversed','Reversed confirmation remains historical');
insert into public.payments(project_id,commitment_id,paid_by_member_id,type,direction,status,amount_minor,paid_on) select ctx.id,activity.id,members.id,'refund','incoming','paid',1000,current_date from ctx,activity,members where n=1;
set local role postgres;
select pg_temp.login(1);
select ok(pg_temp.inbox_matches(),'refunded: actor 1 inbox rows, summaries and deep links equals original');
select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'refunded: actor 1 boolean unread visibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'refunded: actor 1 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'refunded: actor 1 unread membership remains correct');
select pg_temp.login(2);
select ok(pg_temp.inbox_matches(),'refunded: actor 2 inbox rows, summaries and deep links equals original');
select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'refunded: actor 2 boolean unread visibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'refunded: actor 2 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'refunded: actor 2 unread membership remains correct');
select pg_temp.login(3);
select ok(pg_temp.inbox_matches(),'refunded: actor 3 inbox rows, summaries and deep links equals original');
select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'refunded: actor 3 boolean unread visibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'refunded: actor 3 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'refunded: actor 3 unread membership remains correct');
select pg_temp.login(4);
select ok(pg_temp.inbox_matches(),'refunded: actor 4 inbox rows, summaries and deep links equals original');
select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'refunded: actor 4 boolean unread visibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'refunded: actor 4 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'refunded: actor 4 unread membership remains correct');
select pg_temp.login(5);
select ok(pg_temp.inbox_matches(),'refunded: actor 5 inbox rows, summaries and deep links equals original');
select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'refunded: actor 5 boolean unread visibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'refunded: actor 5 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'refunded: actor 5 unread membership remains correct');
select is((select count(*) from public.v_reimbursement_payment_status where reimbursement_request_id in(select id from request_a union all select id from request_b)),0::bigint,'refunded: outsider 5 status hidden');
select is((select count(*) from public.v_my_notification_inbox),0::bigint,'refunded: outsider 5 inbox empty');
select pg_temp.login(6);
select ok(pg_temp.inbox_matches(),'refunded: actor 6 inbox rows, summaries and deep links equals original');
select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'refunded: actor 6 boolean unread visibility equals original');
select is((select count(*) from public.notifications where recipient_user_id<>auth.uid()),0::bigint,'refunded: actor 6 cannot read another recipient');
select is((select count(*) from public.v_my_notification_inbox where read_at is null),(select count(*) from public.v_my_notification_inbox where id in(select id from public.notifications where read_at is null)),'refunded: actor 6 unread membership remains correct');
select is((select count(*) from public.v_reimbursement_payment_status where reimbursement_request_id in(select id from request_a union all select id from request_b)),0::bigint,'refunded: outsider 6 status hidden');
select is((select count(*) from public.v_my_notification_inbox),0::bigint,'refunded: outsider 6 inbox empty');
set local role postgres;
select ok((select bool_and(relrowsecurity and relforcerowsecurity) from pg_class where oid in('public.reimbursement_requests'::regclass,'public.reimbursement_receipt_confirmations'::regclass)),'Reimbursement tables keep FORCE RLS');
select ok((select relrowsecurity from pg_class where oid='public.notifications'::regclass),'Notifications retain existing RLS');

select pg_temp.login(1);
create temp table decision as select public.create_decision((select id from ctx),'Dinner?',null,now()+interval '2 days','[{"title":"Early"},{"title":"Late"}]') id;
create temp table tokens as select public.regenerate_project_join_link((select id from ctx)) token;
select pg_temp.login(6);select public.request_project_access((select token from tokens));
select is(public.get_my_notification_unread_state(),false,'Pending access is not authorized unread');
select pg_temp.login(1);
select ok(exists(select 1 from public.v_my_notification_inbox where kind='project_join_requested' and section='people'),'Access request routes to People');
select ok(pg_temp.inbox_matches(),'Pending access summary exact');
set local role postgres;
create temp table join_request as select id from app.project_join_requests where project_id=(select id from ctx) and requester_user_id='40100000-0000-4000-8000-000000000006';
grant select on join_request to authenticated;
select pg_temp.login(1);select public.review_project_join_request((select id from join_request),true);
select pg_temp.login(6);
select ok(exists(select 1 from public.v_my_notification_inbox where kind='project_member_approved' and resource_id=(select id from ctx)),'Approved access routes to project');
select is(public.get_my_notification_unread_state(),true,'One unread approval');
select public.mark_notification_read(id) from public.v_my_notification_inbox;
select is(public.get_my_notification_unread_state(),false,'Read one clears only unread row');
select pg_temp.login(1);
create temp table reminder as select (public.create_activity_in_category((select id from ctx),(select id from cat),'{"title":"Upcoming","kind":"other","activity_type":"task","estimated_cost_minor":1000}',null)).id;
update public.commitments set starts_at=now()+interval '1 day',owner_member_id=(select id from members where n=2) where id=(select id from reminder);
insert into public.activity_payment_schedules(project_id,commitment_id,title,amount_minor,due_on) select ctx.id,reminder.id,'Deposit',1000,current_date from ctx,reminder;
set local role postgres;
update public.decisions set voting_deadline=now()-interval '1 minute' where id=(select id from decision);
select set_config('request.jwt.claims','{}',true);
select app.evaluate_decision_deadlines();select app.evaluate_payment_schedule_deadlines();select app.evaluate_activity_due_soon();
select pg_temp.login(1);select ok(pg_temp.inbox_matches(),'All branches before resolution: actor 1 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'All branches before resolution: actor 1 unread contract');
select pg_temp.login(2);select ok(pg_temp.inbox_matches(),'All branches before resolution: actor 2 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'All branches before resolution: actor 2 unread contract');
select pg_temp.login(3);select ok(pg_temp.inbox_matches(),'All branches before resolution: actor 3 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'All branches before resolution: actor 3 unread contract');
select pg_temp.login(4);select ok(pg_temp.inbox_matches(),'All branches before resolution: actor 4 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'All branches before resolution: actor 4 unread contract');
select pg_temp.login(5);select ok(pg_temp.inbox_matches(),'All branches before resolution: actor 5 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'All branches before resolution: actor 5 unread contract');
select pg_temp.login(6);select ok(pg_temp.inbox_matches(),'All branches before resolution: actor 6 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'All branches before resolution: actor 6 unread contract');
select pg_temp.login(1);
select ok(exists(select 1 from public.v_my_notification_inbox where kind='decision_deadline_reached'),'Deadline notice visible');

select public.resolve_decision((select id from decision),(select id from public.decision_options where decision_id=(select id from decision) order by sort_order limit 1));
select pg_temp.login(2);
select ok(exists(select 1 from public.v_my_notification_inbox where kind='payment_due_soon' and title='Payment reminder'),'Payment event summary visible');
select ok(exists(select 1 from public.v_my_notification_inbox where kind='activity_due_soon'),'Activity reminder visible');
select ok(exists(select 1 from public.v_my_notification_inbox where kind='decision_resolved'),'Resolution visible');
select is(public.get_my_notification_unread_state(),true,'Many unread rows');
select public.mark_notification_read(id) from public.v_my_notification_inbox where read_at is null limit 1;
select is(public.get_my_notification_unread_state(),true,'Reading one leaves remaining unread');
select public.mark_all_notifications_read();
select is(public.get_my_notification_unread_state(),false,'Mark all clears visible unread');
select ok(exists(select 1 from public.v_my_notification_inbox),'Mark all retains history');
select pg_temp.login(1);select public.create_invitation((select id from ctx),'reimbursement-test-5@example.test','member');
select pg_temp.login(5);
select is((select count(*) from public.list_my_invitations()),1::bigint,'Separate pending invitation');
select is(public.get_my_notification_unread_state(),false,'Invitation not counted as inbox unread');
select is((select count(*) from app.notification_summary((select id from public.v_my_notification_inbox limit 1))),0::bigint,'Direct summary does not grant outsider access');
set local role postgres;create temp table victim as select id from public.notifications where project_id=(select id from ctx) limit 1;grant select on victim to authenticated;
select pg_temp.login(5);select is(app.notification_visible((select id from victim)),false,'Direct helper denies another recipient');select is((select count(*) from app.notification_summary((select id from victim))),0::bigint,'Direct summary denies another recipient');
select pg_temp.login(1);select ok(pg_temp.inbox_matches(),'Read state and resolution: actor 1 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Read state and resolution: actor 1 unread contract');
select pg_temp.login(2);select ok(pg_temp.inbox_matches(),'Read state and resolution: actor 2 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Read state and resolution: actor 2 unread contract');
select pg_temp.login(3);select ok(pg_temp.inbox_matches(),'Read state and resolution: actor 3 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Read state and resolution: actor 3 unread contract');
select pg_temp.login(4);select ok(pg_temp.inbox_matches(),'Read state and resolution: actor 4 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Read state and resolution: actor 4 unread contract');
select pg_temp.login(5);select ok(pg_temp.inbox_matches(),'Read state and resolution: actor 5 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Read state and resolution: actor 5 unread contract');
select pg_temp.login(6);select ok(pg_temp.inbox_matches(),'Read state and resolution: actor 6 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Read state and resolution: actor 6 unread contract');
set local role postgres;update public.commitments set status='cancelled' where id=(select id from reminder);
select pg_temp.login(1);select ok(pg_temp.inbox_matches(),'Cancelled Activity: actor 1 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Cancelled Activity: actor 1 unread contract');
select pg_temp.login(2);select ok(pg_temp.inbox_matches(),'Cancelled Activity: actor 2 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Cancelled Activity: actor 2 unread contract');
select pg_temp.login(3);select ok(pg_temp.inbox_matches(),'Cancelled Activity: actor 3 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Cancelled Activity: actor 3 unread contract');
select pg_temp.login(4);select ok(pg_temp.inbox_matches(),'Cancelled Activity: actor 4 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Cancelled Activity: actor 4 unread contract');
select pg_temp.login(5);select ok(pg_temp.inbox_matches(),'Cancelled Activity: actor 5 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Cancelled Activity: actor 5 unread contract');
select pg_temp.login(6);select ok(pg_temp.inbox_matches(),'Cancelled Activity: actor 6 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Cancelled Activity: actor 6 unread contract');
set local role postgres;update public.projects set status='archived' where id=(select id from ctx);
select pg_temp.login(1);select ok(pg_temp.inbox_matches(),'Archived project: actor 1 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Archived project: actor 1 unread contract');
select pg_temp.login(2);select ok(pg_temp.inbox_matches(),'Archived project: actor 2 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Archived project: actor 2 unread contract');
select pg_temp.login(3);select ok(pg_temp.inbox_matches(),'Archived project: actor 3 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Archived project: actor 3 unread contract');
select pg_temp.login(4);select ok(pg_temp.inbox_matches(),'Archived project: actor 4 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Archived project: actor 4 unread contract');
select pg_temp.login(5);select ok(pg_temp.inbox_matches(),'Archived project: actor 5 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Archived project: actor 5 unread contract');
select pg_temp.login(6);select ok(pg_temp.inbox_matches(),'Archived project: actor 6 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Archived project: actor 6 unread contract');
select pg_temp.login(1);set local role postgres;update public.projects set status='active' where id=(select id from ctx);update public.project_members set status='removed' where id=(select id from members where n=2);
select pg_temp.login(1);select ok(pg_temp.inbox_matches(),'Removed member: actor 1 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Removed member: actor 1 unread contract');
select pg_temp.login(2);select ok(pg_temp.inbox_matches(),'Removed member: actor 2 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Removed member: actor 2 unread contract');
select pg_temp.login(3);select ok(pg_temp.inbox_matches(),'Removed member: actor 3 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Removed member: actor 3 unread contract');
select pg_temp.login(4);select ok(pg_temp.inbox_matches(),'Removed member: actor 4 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Removed member: actor 4 unread contract');
select pg_temp.login(5);select ok(pg_temp.inbox_matches(),'Removed member: actor 5 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Removed member: actor 5 unread contract');
select pg_temp.login(6);select ok(pg_temp.inbox_matches(),'Removed member: actor 6 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Removed member: actor 6 unread contract');
select pg_temp.login(2);select is(public.get_my_notification_unread_state(),false,'Removed member has no unread');select is((select count(*) from public.v_my_notification_inbox),0::bigint,'Removed member has no inbox');
set local role postgres;update public.commitments set deleted_at=now() where id=(select id from reminder);update public.decisions set deleted_at=now() where id=(select id from decision);
select pg_temp.login(1);select ok(pg_temp.inbox_matches(),'Deleted sources: actor 1 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Deleted sources: actor 1 unread contract');
select pg_temp.login(2);select ok(pg_temp.inbox_matches(),'Deleted sources: actor 2 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Deleted sources: actor 2 unread contract');
select pg_temp.login(3);select ok(pg_temp.inbox_matches(),'Deleted sources: actor 3 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Deleted sources: actor 3 unread contract');
select pg_temp.login(4);select ok(pg_temp.inbox_matches(),'Deleted sources: actor 4 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Deleted sources: actor 4 unread contract');
select pg_temp.login(5);select ok(pg_temp.inbox_matches(),'Deleted sources: actor 5 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Deleted sources: actor 5 unread contract');
select pg_temp.login(6);select ok(pg_temp.inbox_matches(),'Deleted sources: actor 6 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Deleted sources: actor 6 unread contract');
select pg_temp.login(1);select public.soft_delete_project((select id from ctx));
select pg_temp.login(1);select ok(pg_temp.inbox_matches(),'Deleted project: actor 1 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Deleted project: actor 1 unread contract');
select pg_temp.login(2);select ok(pg_temp.inbox_matches(),'Deleted project: actor 2 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Deleted project: actor 2 unread contract');
select pg_temp.login(3);select ok(pg_temp.inbox_matches(),'Deleted project: actor 3 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Deleted project: actor 3 unread contract');
select pg_temp.login(4);select ok(pg_temp.inbox_matches(),'Deleted project: actor 4 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Deleted project: actor 4 unread contract');
select pg_temp.login(5);select ok(pg_temp.inbox_matches(),'Deleted project: actor 5 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Deleted project: actor 5 unread contract');
select pg_temp.login(6);select ok(pg_temp.inbox_matches(),'Deleted project: actor 6 inbox contract');select is(public.get_my_notification_unread_state(),exists(select 1 from pg_temp.original_inbox where read_at is null),'Deleted project: actor 6 unread contract');
set local role anon;
select throws_ok($$select public.get_my_notification_unread_state()$$,'42501',null,'Anonymous unread denied');
select throws_ok($$select app.notification_visible(gen_random_uuid())$$,'42501',null,'Anonymous visibility denied');
select throws_ok($$select * from app.notification_summary(gen_random_uuid())$$,'42501',null,'Anonymous summary denied');
set local role postgres;
select ok((select bool_and(prosecdef and proconfig @> array['search_path=""']) from pg_proc where oid in('app.notification_visible(uuid)'::regprocedure,'app.notification_summary(uuid)'::regprocedure)),'Helpers fixed search path and definer');

select * from finish();
rollback;
