begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
-- Exact signatures prevent overloads from silently escaping the ACL contract.

select ok(not has_function_privilege('anon','public.accept_invitation(text)','EXECUTE'),'accept_invitation: anon denied');
select ok(has_function_privilege('authenticated','public.accept_invitation(text)','EXECUTE'),'accept_invitation: authenticated allowed');
select is(has_function_privilege('service_role','public.accept_invitation(text)','EXECUTE'),false,'accept_invitation: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.accept_invitation(text)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'accept_invitation: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.cancel_item_settlement(uuid)','EXECUTE'),'cancel_item_settlement: anon denied');
select ok(has_function_privilege('authenticated','public.cancel_item_settlement(uuid)','EXECUTE'),'cancel_item_settlement: authenticated allowed');
select is(has_function_privilege('service_role','public.cancel_item_settlement(uuid)','EXECUTE'),false,'cancel_item_settlement: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.cancel_item_settlement(uuid)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'cancel_item_settlement: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.complete_assigned_item(uuid,date)','EXECUTE'),'complete_assigned_item: anon denied');
select ok(has_function_privilege('authenticated','public.complete_assigned_item(uuid,date)','EXECUTE'),'complete_assigned_item: authenticated allowed');
select is(has_function_privilege('service_role','public.complete_assigned_item(uuid,date)','EXECUTE'),false,'complete_assigned_item: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.complete_assigned_item(uuid,date)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'complete_assigned_item: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.complete_assigned_task(uuid,date)','EXECUTE'),'complete_assigned_task: anon denied');
select ok(has_function_privilege('authenticated','public.complete_assigned_task(uuid,date)','EXECUTE'),'complete_assigned_task: authenticated allowed');
select is(has_function_privilege('service_role','public.complete_assigned_task(uuid,date)','EXECUTE'),false,'complete_assigned_task: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.complete_assigned_task(uuid,date)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'complete_assigned_task: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.complete_commitment_occurrence(uuid,date)','EXECUTE'),'complete_commitment_occurrence: anon denied');
select ok(has_function_privilege('authenticated','public.complete_commitment_occurrence(uuid,date)','EXECUTE'),'complete_commitment_occurrence: authenticated allowed');
select is(has_function_privilege('service_role','public.complete_commitment_occurrence(uuid,date)','EXECUTE'),false,'complete_commitment_occurrence: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.complete_commitment_occurrence(uuid,date)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'complete_commitment_occurrence: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.complete_task_occurrence(uuid,date)','EXECUTE'),'complete_task_occurrence: anon denied');
select ok(has_function_privilege('authenticated','public.complete_task_occurrence(uuid,date)','EXECUTE'),'complete_task_occurrence: authenticated allowed');
select is(has_function_privilege('service_role','public.complete_task_occurrence(uuid,date)','EXECUTE'),false,'complete_task_occurrence: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.complete_task_occurrence(uuid,date)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'complete_task_occurrence: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.create_activity_in_category(uuid,uuid,jsonb,jsonb)','EXECUTE'),'create_activity_in_category: anon denied');
select ok(has_function_privilege('authenticated','public.create_activity_in_category(uuid,uuid,jsonb,jsonb)','EXECUTE'),'create_activity_in_category: authenticated allowed');
select is(has_function_privilege('service_role','public.create_activity_in_category(uuid,uuid,jsonb,jsonb)','EXECUTE'),false,'create_activity_in_category: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.create_activity_in_category(uuid,uuid,jsonb,jsonb)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'create_activity_in_category: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.create_invitation(uuid,text,public.member_role)','EXECUTE'),'create_invitation: anon denied');
select ok(has_function_privilege('authenticated','public.create_invitation(uuid,text,public.member_role)','EXECUTE'),'create_invitation: authenticated allowed');
select is(has_function_privilege('service_role','public.create_invitation(uuid,text,public.member_role)','EXECUTE'),false,'create_invitation: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.create_invitation(uuid,text,public.member_role)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'create_invitation: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.create_project(text,text,text,date,date,public.project_profile)','EXECUTE'),'create_project: anon denied');
select ok(has_function_privilege('authenticated','public.create_project(text,text,text,date,date,public.project_profile)','EXECUTE'),'create_project: authenticated allowed');
select is(has_function_privilege('service_role','public.create_project(text,text,text,date,date,public.project_profile)','EXECUTE'),false,'create_project: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.create_project(text,text,text,date,date,public.project_profile)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'create_project: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.create_project_note(uuid,text,text)','EXECUTE'),'create_project_note: anon denied');
select ok(has_function_privilege('authenticated','public.create_project_note(uuid,text,text)','EXECUTE'),'create_project_note: authenticated allowed');
select is(has_function_privilege('service_role','public.create_project_note(uuid,text,text)','EXECUTE'),false,'create_project_note: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.create_project_note(uuid,text,text)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'create_project_note: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.create_task_with_cost(uuid,jsonb,numeric)','EXECUTE'),'create_task_with_cost: anon denied');
select ok(has_function_privilege('authenticated','public.create_task_with_cost(uuid,jsonb,numeric)','EXECUTE'),'create_task_with_cost: authenticated allowed');
select is(has_function_privilege('service_role','public.create_task_with_cost(uuid,jsonb,numeric)','EXECUTE'),false,'create_task_with_cost: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.create_task_with_cost(uuid,jsonb,numeric)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'create_task_with_cost: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.decline_invitation(text)','EXECUTE'),'decline_invitation: anon denied');
select ok(has_function_privilege('authenticated','public.decline_invitation(text)','EXECUTE'),'decline_invitation: authenticated allowed');
select is(has_function_privilege('service_role','public.decline_invitation(text)','EXECUTE'),false,'decline_invitation: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.decline_invitation(text)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'decline_invitation: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.delete_project_category(uuid)','EXECUTE'),'delete_project_category: anon denied');
select ok(has_function_privilege('authenticated','public.delete_project_category(uuid)','EXECUTE'),'delete_project_category: authenticated allowed');
select is(has_function_privilege('service_role','public.delete_project_category(uuid)','EXECUTE'),false,'delete_project_category: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.delete_project_category(uuid)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'delete_project_category: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.get_admin_overview()','EXECUTE'),'get_admin_overview: anon denied');
select ok(has_function_privilege('authenticated','public.get_admin_overview()','EXECUTE'),'get_admin_overview: authenticated allowed');
select is(has_function_privilege('service_role','public.get_admin_overview()','EXECUTE'),true,'get_admin_overview: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.get_admin_overview()'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'get_admin_overview: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.get_admin_project_health_summary(uuid)','EXECUTE'),'get_admin_project_health_summary: anon denied');
select ok(has_function_privilege('authenticated','public.get_admin_project_health_summary(uuid)','EXECUTE'),'get_admin_project_health_summary: authenticated allowed');
select is(has_function_privilege('service_role','public.get_admin_project_health_summary(uuid)','EXECUTE'),true,'get_admin_project_health_summary: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.get_admin_project_health_summary(uuid)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'get_admin_project_health_summary: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.get_commitment_occurrences(uuid,date,date)','EXECUTE'),'get_commitment_occurrences: anon denied');
select ok(has_function_privilege('authenticated','public.get_commitment_occurrences(uuid,date,date)','EXECUTE'),'get_commitment_occurrences: authenticated allowed');
select is(has_function_privilege('service_role','public.get_commitment_occurrences(uuid,date,date)','EXECUTE'),false,'get_commitment_occurrences: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.get_commitment_occurrences(uuid,date,date)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'get_commitment_occurrences: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.get_invitation(text)','EXECUTE'),'get_invitation: anon denied');
select ok(has_function_privilege('authenticated','public.get_invitation(text)','EXECUTE'),'get_invitation: authenticated allowed');
select is(has_function_privilege('service_role','public.get_invitation(text)','EXECUTE'),false,'get_invitation: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.get_invitation(text)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'get_invitation: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.get_my_attention()','EXECUTE'),'get_my_attention: anon denied');
select ok(has_function_privilege('authenticated','public.get_my_attention()','EXECUTE'),'get_my_attention: authenticated allowed');
select is(has_function_privilege('service_role','public.get_my_attention()','EXECUTE'),false,'get_my_attention: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.get_my_attention()'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'get_my_attention: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.get_my_timeline_events(timestamp with time zone,timestamp with time zone)','EXECUTE'),'get_my_timeline_events: anon denied');
select ok(has_function_privilege('authenticated','public.get_my_timeline_events(timestamp with time zone,timestamp with time zone)','EXECUTE'),'get_my_timeline_events: authenticated allowed');
select is(has_function_privilege('service_role','public.get_my_timeline_events(timestamp with time zone,timestamp with time zone)','EXECUTE'),false,'get_my_timeline_events: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.get_my_timeline_events(timestamp with time zone,timestamp with time zone)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'get_my_timeline_events: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.get_project_health(uuid)','EXECUTE'),'get_project_health: anon denied');
select ok(has_function_privilege('authenticated','public.get_project_health(uuid)','EXECUTE'),'get_project_health: authenticated allowed');
select is(has_function_privilege('service_role','public.get_project_health(uuid)','EXECUTE'),false,'get_project_health: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.get_project_health(uuid)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'get_project_health: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.get_project_health_summary(uuid)','EXECUTE'),'get_project_health_summary: anon denied');
select ok(has_function_privilege('authenticated','public.get_project_health_summary(uuid)','EXECUTE'),'get_project_health_summary: authenticated allowed');
select is(has_function_privilege('service_role','public.get_project_health_summary(uuid)','EXECUTE'),false,'get_project_health_summary: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.get_project_health_summary(uuid)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'get_project_health_summary: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.get_project_timeline_events(uuid,timestamp with time zone,timestamp with time zone)','EXECUTE'),'get_project_timeline_events: anon denied');
select ok(has_function_privilege('authenticated','public.get_project_timeline_events(uuid,timestamp with time zone,timestamp with time zone)','EXECUTE'),'get_project_timeline_events: authenticated allowed');
select is(has_function_privilege('service_role','public.get_project_timeline_events(uuid,timestamp with time zone,timestamp with time zone)','EXECUTE'),false,'get_project_timeline_events: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.get_project_timeline_events(uuid,timestamp with time zone,timestamp with time zone)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'get_project_timeline_events: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.get_task_occurrences(uuid,date,date)','EXECUTE'),'get_task_occurrences: anon denied');
select ok(has_function_privilege('authenticated','public.get_task_occurrences(uuid,date,date)','EXECUTE'),'get_task_occurrences: authenticated allowed');
select is(has_function_privilege('service_role','public.get_task_occurrences(uuid,date,date)','EXECUTE'),false,'get_task_occurrences: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.get_task_occurrences(uuid,date,date)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'get_task_occurrences: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.list_my_invitations()','EXECUTE'),'list_my_invitations: anon denied');
select ok(has_function_privilege('authenticated','public.list_my_invitations()','EXECUTE'),'list_my_invitations: authenticated allowed');
select is(has_function_privilege('service_role','public.list_my_invitations()','EXECUTE'),false,'list_my_invitations: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.list_my_invitations()'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'list_my_invitations: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.mark_notification_read(uuid)','EXECUTE'),'mark_notification_read: anon denied');
select ok(has_function_privilege('authenticated','public.mark_notification_read(uuid)','EXECUTE'),'mark_notification_read: authenticated allowed');
select is(has_function_privilege('service_role','public.mark_notification_read(uuid)','EXECUTE'),false,'mark_notification_read: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.mark_notification_read(uuid)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'mark_notification_read: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.record_item_settlement(uuid,uuid,uuid,bigint,date)','EXECUTE'),'record_item_settlement: anon denied');
select ok(has_function_privilege('authenticated','public.record_item_settlement(uuid,uuid,uuid,bigint,date)','EXECUTE'),'record_item_settlement: authenticated allowed');
select is(has_function_privilege('service_role','public.record_item_settlement(uuid,uuid,uuid,bigint,date)','EXECUTE'),false,'record_item_settlement: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.record_item_settlement(uuid,uuid,uuid,bigint,date)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'record_item_settlement: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.record_member_payment(uuid,uuid,bigint,public.payment_type,boolean,date)','EXECUTE'),'record_member_payment: anon denied');
select ok(has_function_privilege('authenticated','public.record_member_payment(uuid,uuid,bigint,public.payment_type,boolean,date)','EXECUTE'),'record_member_payment: authenticated allowed');
select is(has_function_privilege('service_role','public.record_member_payment(uuid,uuid,bigint,public.payment_type,boolean,date)','EXECUTE'),false,'record_member_payment: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.record_member_payment(uuid,uuid,bigint,public.payment_type,boolean,date)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'record_member_payment: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.save_activity_with_split(uuid,uuid,jsonb,jsonb)','EXECUTE'),'save_activity_with_split: anon denied');
select ok(has_function_privilege('authenticated','public.save_activity_with_split(uuid,uuid,jsonb,jsonb)','EXECUTE'),'save_activity_with_split: authenticated allowed');
select is(has_function_privilege('service_role','public.save_activity_with_split(uuid,uuid,jsonb,jsonb)','EXECUTE'),false,'save_activity_with_split: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.save_activity_with_split(uuid,uuid,jsonb,jsonb)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'save_activity_with_split: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.save_commitment_occurrence_note(uuid,date,text)','EXECUTE'),'save_commitment_occurrence_note: anon denied');
select ok(has_function_privilege('authenticated','public.save_commitment_occurrence_note(uuid,date,text)','EXECUTE'),'save_commitment_occurrence_note: authenticated allowed');
select is(has_function_privilege('service_role','public.save_commitment_occurrence_note(uuid,date,text)','EXECUTE'),false,'save_commitment_occurrence_note: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.save_commitment_occurrence_note(uuid,date,text)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'save_commitment_occurrence_note: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.set_activity_cost_split(uuid,jsonb)','EXECUTE'),'set_activity_cost_split: anon denied');
select ok(has_function_privilege('authenticated','public.set_activity_cost_split(uuid,jsonb)','EXECUTE'),'set_activity_cost_split: authenticated allowed');
select is(has_function_privilege('service_role','public.set_activity_cost_split(uuid,jsonb)','EXECUTE'),false,'set_activity_cost_split: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.set_activity_cost_split(uuid,jsonb)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'set_activity_cost_split: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.set_actual_cost_with_split(uuid,numeric,boolean,jsonb)','EXECUTE'),'set_actual_cost_with_split: anon denied');
select ok(has_function_privilege('authenticated','public.set_actual_cost_with_split(uuid,numeric,boolean,jsonb)','EXECUTE'),'set_actual_cost_with_split: authenticated allowed');
select is(has_function_privilege('service_role','public.set_actual_cost_with_split(uuid,numeric,boolean,jsonb)','EXECUTE'),false,'set_actual_cost_with_split: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.set_actual_cost_with_split(uuid,numeric,boolean,jsonb)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'set_actual_cost_with_split: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.set_commitment_actual_cost(uuid,numeric,boolean)','EXECUTE'),'set_commitment_actual_cost: anon denied');
select ok(has_function_privilege('authenticated','public.set_commitment_actual_cost(uuid,numeric,boolean)','EXECUTE'),'set_commitment_actual_cost: authenticated allowed');
select is(has_function_privilege('service_role','public.set_commitment_actual_cost(uuid,numeric,boolean)','EXECUTE'),false,'set_commitment_actual_cost: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.set_commitment_actual_cost(uuid,numeric,boolean)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'set_commitment_actual_cost: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.set_project_budget(uuid,numeric)','EXECUTE'),'set_project_budget: anon denied');
select ok(has_function_privilege('authenticated','public.set_project_budget(uuid,numeric)','EXECUTE'),'set_project_budget: authenticated allowed');
select is(has_function_privilege('service_role','public.set_project_budget(uuid,numeric)','EXECUTE'),false,'set_project_budget: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.set_project_budget(uuid,numeric)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'set_project_budget: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.skip_commitment_occurrence(uuid,date,text)','EXECUTE'),'skip_commitment_occurrence: anon denied');
select ok(has_function_privilege('authenticated','public.skip_commitment_occurrence(uuid,date,text)','EXECUTE'),'skip_commitment_occurrence: authenticated allowed');
select is(has_function_privilege('service_role','public.skip_commitment_occurrence(uuid,date,text)','EXECUTE'),false,'skip_commitment_occurrence: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.skip_commitment_occurrence(uuid,date,text)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'skip_commitment_occurrence: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.skip_task_occurrence(uuid,date)','EXECUTE'),'skip_task_occurrence: anon denied');
select ok(has_function_privilege('authenticated','public.skip_task_occurrence(uuid,date)','EXECUTE'),'skip_task_occurrence: authenticated allowed');
select is(has_function_privilege('service_role','public.skip_task_occurrence(uuid,date)','EXECUTE'),false,'skip_task_occurrence: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.skip_task_occurrence(uuid,date)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'skip_task_occurrence: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.soft_delete_commitment(uuid)','EXECUTE'),'soft_delete_commitment: anon denied');
select ok(has_function_privilege('authenticated','public.soft_delete_commitment(uuid)','EXECUTE'),'soft_delete_commitment: authenticated allowed');
select is(has_function_privilege('service_role','public.soft_delete_commitment(uuid)','EXECUTE'),false,'soft_delete_commitment: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.soft_delete_commitment(uuid)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'soft_delete_commitment: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.soft_delete_project(uuid)','EXECUTE'),'soft_delete_project: anon denied');
select ok(has_function_privilege('authenticated','public.soft_delete_project(uuid)','EXECUTE'),'soft_delete_project: authenticated allowed');
select is(has_function_privilege('service_role','public.soft_delete_project(uuid)','EXECUTE'),false,'soft_delete_project: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.soft_delete_project(uuid)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'soft_delete_project: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.soft_delete_project_note(uuid)','EXECUTE'),'soft_delete_project_note: anon denied');
select ok(has_function_privilege('authenticated','public.soft_delete_project_note(uuid)','EXECUTE'),'soft_delete_project_note: authenticated allowed');
select is(has_function_privilege('service_role','public.soft_delete_project_note(uuid)','EXECUTE'),false,'soft_delete_project_note: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.soft_delete_project_note(uuid)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'soft_delete_project_note: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.soft_delete_task(uuid)','EXECUTE'),'soft_delete_task: anon denied');
select ok(has_function_privilege('authenticated','public.soft_delete_task(uuid)','EXECUTE'),'soft_delete_task: authenticated allowed');
select is(has_function_privilege('service_role','public.soft_delete_task(uuid)','EXECUTE'),false,'soft_delete_task: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.soft_delete_task(uuid)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'soft_delete_task: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.stop_commitment_recurrence(uuid,date)','EXECUTE'),'stop_commitment_recurrence: anon denied');
select ok(has_function_privilege('authenticated','public.stop_commitment_recurrence(uuid,date)','EXECUTE'),'stop_commitment_recurrence: authenticated allowed');
select is(has_function_privilege('service_role','public.stop_commitment_recurrence(uuid,date)','EXECUTE'),false,'stop_commitment_recurrence: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.stop_commitment_recurrence(uuid,date)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'stop_commitment_recurrence: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.stop_task_recurrence(uuid,date)','EXECUTE'),'stop_task_recurrence: anon denied');
select ok(has_function_privilege('authenticated','public.stop_task_recurrence(uuid,date)','EXECUTE'),'stop_task_recurrence: authenticated allowed');
select is(has_function_privilege('service_role','public.stop_task_recurrence(uuid,date)','EXECUTE'),false,'stop_task_recurrence: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.stop_task_recurrence(uuid,date)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'stop_task_recurrence: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.transfer_and_leave(uuid,uuid)','EXECUTE'),'transfer_and_leave: anon denied');
select ok(has_function_privilege('authenticated','public.transfer_and_leave(uuid,uuid)','EXECUTE'),'transfer_and_leave: authenticated allowed');
select is(has_function_privilege('service_role','public.transfer_and_leave(uuid,uuid)','EXECUTE'),false,'transfer_and_leave: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.transfer_and_leave(uuid,uuid)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'transfer_and_leave: no PUBLIC execute');

select ok(not has_function_privilege('anon','public.update_project_note(uuid,text,text)','EXECUTE'),'update_project_note: anon denied');
select ok(has_function_privilege('authenticated','public.update_project_note(uuid,text,text)','EXECUTE'),'update_project_note: authenticated allowed');
select is(has_function_privilege('service_role','public.update_project_note(uuid,text,text)','EXECUTE'),false,'update_project_note: service role contract');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.update_project_note(uuid,text,text)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'update_project_note: no PUBLIC execute');
select is(has_function_privilege('anon','app.calendar_projection_for_user(uuid)','EXECUTE'),false,'calendar_projection_for_user: anon preserved');
select is(has_function_privilege('authenticated','app.calendar_projection_for_user(uuid)','EXECUTE'),false,'calendar_projection_for_user: authenticated preserved');
select is(has_function_privilege('service_role','app.calendar_projection_for_user(uuid)','EXECUTE'),false,'calendar_projection_for_user: service_role preserved');
select is(has_function_privilege('anon','app.evaluate_scheduled_domain_events()','EXECUTE'),false,'evaluate_scheduled_domain_events: anon preserved');
select is(has_function_privilege('authenticated','app.evaluate_scheduled_domain_events()','EXECUTE'),false,'evaluate_scheduled_domain_events: authenticated preserved');
select is(has_function_privilege('service_role','app.evaluate_scheduled_domain_events()','EXECUTE'),false,'evaluate_scheduled_domain_events: service_role preserved');
select is(has_function_privilege('anon','app.guard_payment_settlement_member()','EXECUTE'),false,'guard_payment_settlement_member: anon preserved');
select is(has_function_privilege('authenticated','app.guard_payment_settlement_member()','EXECUTE'),false,'guard_payment_settlement_member: authenticated preserved');
select is(has_function_privilege('service_role','app.guard_payment_settlement_member()','EXECUTE'),false,'guard_payment_settlement_member: service_role preserved');
select is(has_function_privilege('anon','app.guard_settlement_identity()','EXECUTE'),false,'guard_settlement_identity: anon preserved');
select is(has_function_privilege('authenticated','app.guard_settlement_identity()','EXECUTE'),false,'guard_settlement_identity: authenticated preserved');
select is(has_function_privilege('service_role','app.guard_settlement_identity()','EXECUTE'),false,'guard_settlement_identity: service_role preserved');
select is(has_function_privilege('anon','app.guard_settlement_pair()','EXECUTE'),false,'guard_settlement_pair: anon preserved');
select is(has_function_privilege('authenticated','app.guard_settlement_pair()','EXECUTE'),false,'guard_settlement_pair: authenticated preserved');
select is(has_function_privilege('service_role','app.guard_settlement_pair()','EXECUTE'),false,'guard_settlement_pair: service_role preserved');
select is(has_function_privilege('anon','app.notification_summary(uuid)','EXECUTE'),false,'notification_summary: anon preserved');
select is(has_function_privilege('authenticated','app.notification_summary(uuid)','EXECUTE'),true,'notification_summary: authenticated preserved');
select is(has_function_privilege('service_role','app.notification_summary(uuid)','EXECUTE'),false,'notification_summary: service_role preserved');
select is(has_function_privilege('anon','app.notification_visible(uuid)','EXECUTE'),false,'notification_visible: anon preserved');
select is(has_function_privilege('authenticated','app.notification_visible(uuid)','EXECUTE'),true,'notification_visible: authenticated preserved');
select is(has_function_privilege('service_role','app.notification_visible(uuid)','EXECUTE'),false,'notification_visible: service_role preserved');
select is(has_function_privilege('anon','app.record_item_settlement(uuid,uuid,uuid,bigint,date,uuid)','EXECUTE'),false,'record_item_settlement: anon preserved');
select is(has_function_privilege('authenticated','app.record_item_settlement(uuid,uuid,uuid,bigint,date,uuid)','EXECUTE'),false,'record_item_settlement: authenticated preserved');
select is(has_function_privilege('service_role','app.record_item_settlement(uuid,uuid,uuid,bigint,date,uuid)','EXECUTE'),false,'record_item_settlement: service_role preserved');
select is(has_function_privilege('anon','app.request_external_calendar_worker()','EXECUTE'),false,'request_external_calendar_worker: anon preserved');
select is(has_function_privilege('authenticated','app.request_external_calendar_worker()','EXECUTE'),false,'request_external_calendar_worker: authenticated preserved');
select is(has_function_privilege('service_role','app.request_external_calendar_worker()','EXECUTE'),false,'request_external_calendar_worker: service_role preserved');
select is(has_function_privilege('anon','public.calendar_backend(text,jsonb)','EXECUTE'),false,'calendar_backend: anon preserved');
select is(has_function_privilege('authenticated','public.calendar_backend(text,jsonb)','EXECUTE'),false,'calendar_backend: authenticated preserved');
select is(has_function_privilege('service_role','public.calendar_backend(text,jsonb)','EXECUTE'),true,'calendar_backend: service_role preserved');
select is(has_function_privilege('anon','public.calendar_worker_wakeup()','EXECUTE'),false,'calendar_worker_wakeup: anon preserved');
select is(has_function_privilege('authenticated','public.calendar_worker_wakeup()','EXECUTE'),false,'calendar_worker_wakeup: authenticated preserved');
select is(has_function_privilege('service_role','public.calendar_worker_wakeup()','EXECUTE'),true,'calendar_worker_wakeup: service_role preserved');
select is(has_function_privilege('anon','public.get_my_notification_unread_state()','EXECUTE'),false,'get_my_notification_unread_state: anon preserved');
select is(has_function_privilege('authenticated','public.get_my_notification_unread_state()','EXECUTE'),true,'get_my_notification_unread_state: authenticated preserved');
select is(has_function_privilege('service_role','public.get_my_notification_unread_state()','EXECUTE'),false,'get_my_notification_unread_state: service_role preserved');
select ok(not exists(select 1 from pg_default_acl d, lateral aclexplode(d.defaclacl) a where d.defaclrole='postgres'::regrole and d.defaclnamespace='public'::regnamespace and d.defaclobjtype='f' and a.grantee in ('anon'::regrole,'authenticated'::regrole,'service_role'::regrole) and a.privilege_type='EXECUTE'),'No automatic client/service grants for future postgres public functions');
set local role anon;
select throws_ok($$select public.create_project('ACL denied','UTC','GBP',current_date,null,'blank')$$,'42501',null,'Anonymous create_project blocked by EXECUTE');
select throws_ok($$select public.create_invitation(null,'acl@example.test','member')$$,'42501',null,'Anonymous invitation blocked by EXECUTE');
select throws_ok($$select public.record_member_payment(null,null,100,'full',true,current_date)$$,'42501',null,'Anonymous payment blocked by EXECUTE');
set local role service_role;
select throws_ok($$select public.create_project('ACL denied','UTC','GBP',current_date,null,'blank')$$,'42501',null,'Service role cannot use client project RPC');
set local role postgres;
select * from finish();
rollback;
