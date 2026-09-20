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
create temporary table pg_temp.ctx as select public.create_project('Completion gating','UTC','GBP','2026-01-01',null,'team_project') as project_id;
set local role postgres;
insert into public.project_members(project_id,user_id,display_name,role)
select project_id,'bb270000-0000-0000-0000-000000000027','Completion B','member' from pg_temp.ctx;
select pg_temp.login('aa270000-0000-0000-0000-000000000027','completion-a@t.co');

create temporary table cat as with c as (insert into public.project_areas(project_id,title) select project_id,'Category' from ctx returning id) select * from c;
create temporary table item as select (public.create_activity_in_category((select project_id from ctx),(select id from cat),'{"title":"Event activity","kind":"other","activity_type":"task","estimated_cost_minor":100}',null)).id;
select throws_ok($$insert into app.domain_events(event_type,project_id,resource_type,resource_id,deduplication_key) select 'payment.confirmed',project_id,'activity',item.id,'spoof' from ctx,item$$,'42501',null,'Client cannot insert privileged facts');
select throws_ok($$select app.emit_domain_event('activity.completed',(select project_id from ctx),(select id from item),'{}','spoof')$$,'42501',null,'Client cannot emit');
select throws_ok($$select app.process_domain_event(gen_random_uuid())$$,'42501',null,'Client cannot dispatch');
select throws_ok($$select * from app.domain_events$$,'42501',null,'Member cannot read raw events');
select throws_ok($$update app.automation_rules set enabled=false$$,'42501',null,'Client cannot configure rules');
select throws_ok($$update app.domain_events set actor_user_id=gen_random_uuid()$$,'42501',null,'Client cannot spoof actor');
select throws_ok($$update public.commitments set status='completed' where id=(select id from item)$$,'P0001',null,'Financial gate rejects completion');
select throws_ok($$select public.create_activity_in_category((select project_id from ctx),null,'{}',null)$$,'22023',null,'Invalid category fails creation');
set local role postgres;
select is((select count(*)::int from app.domain_events where project_id=(select project_id from ctx)),1,'Failed creation and blocked completion emit nothing');
select is((select actor_user_id from app.domain_events where resource_id=(select id from item)),'aa270000-0000-0000-0000-000000000027'::uuid,'Actor comes from auth');
select is((select payload from app.domain_events where resource_id=(select id from item)),jsonb_build_object('category_id',(select id from cat)),'Minimal category context');
select is((select count(*)::int from app.automation_action_runs r join app.domain_events e on e.id=r.event_id where e.resource_id=(select id from item)),1,'Matching rule executes once');
select is((select count(*)::int from public.notifications where commitment_id=(select id from item)),1,'One collaborator notification');
select app.process_domain_event(id) from app.domain_events where resource_id=(select id from item);
select app.emit_domain_event('activity.created',(select project_id from ctx),(select id from item),jsonb_build_object('category_id',(select id from cat)),'created');
select is((select count(*)::int from app.domain_events where resource_id=(select id from item)),1,'Emitter retry deduplicates');
select is((select count(*)::int from public.notifications where commitment_id=(select id from item)),1,'Dispatcher retry does not duplicate');
select throws_ok($$update app.domain_events set actor_user_id=gen_random_uuid() where resource_id=(select id from item)$$,'P0001',null,'Facts immutable even for owner');
select throws_ok($$delete from app.domain_events where resource_id=(select id from item)$$,'P0001',null,'Facts retained');
select throws_ok($$select app.emit_domain_event('activity.created',gen_random_uuid(),(select id from item),jsonb_build_object('category_id',(select id from cat)),'bad')$$,'22023',null,'Cross-project reference rejected');
select pg_temp.login('aa270000-0000-0000-0000-000000000027','completion-a@t.co');
insert into public.payments(project_id,commitment_id,type,amount_minor,status,paid_on) select project_id,id,'full',100,'paid',current_date from ctx,item;
update public.commitments set status='completed' where id=(select id from item);
update public.commitments set status='completed' where id=(select id from item);
set local role postgres;
select is((select count(*)::int from app.domain_events where resource_id=(select id from item) and event_type='activity.completed'),1,'Successful completion and repeated save produce one fact');
select is((select count(*)::int from app.automation_action_runs r join app.domain_events e on e.id=r.event_id where e.resource_id=(select id from item)),1,'Nonmatching completed event performs no action');
select is((select count(*)::int from app.domain_event_processing p join app.domain_events e on e.id=p.event_id where e.resource_id=(select id from item)),2,'Both event types processed');
update public.commitments set status='researching' where id=(select id from item);
update public.commitments set status='completed' where id=(select id from item);
select is((select count(*)::int from app.domain_events where resource_id=(select id from item) and event_type='activity.completed'),2,'Recompletion is a new transition');
update app.automation_rules set enabled=false where id='activity_created_collaborators';
create temporary table disabled_item as select (public.create_activity_in_category((select project_id from ctx),(select id from cat),'{"title":"Disabled rule","kind":"other","activity_type":"task"}',null)).id;
select is((select count(*)::int from public.notifications where commitment_id=(select id from disabled_item)),0,'Disabled rule does not execute');
select ok((select bool_and(relrowsecurity and relforcerowsecurity) from pg_class where oid in ('app.domain_events'::regclass,'app.domain_event_types'::regclass,'app.automation_rules'::regclass,'app.domain_event_processing'::regclass,'app.automation_action_runs'::regclass)),'All internal tables FORCE RLS');
select ok(not has_table_privilege('authenticated','app.domain_events','INSERT') and not has_table_privilege('service_role','app.domain_events','INSERT'),'No direct event writer grants');
select ok(exists(select 1 from public.audit_log where entity_id=(select id from item) and action='update'),'Audit remains independent');
-- The INSERT trigger runs before the surrounding statement subsequently fails.
create function pg_temp.fail_after_activity() returns void language plpgsql as $$ begin
 perform public.create_activity_in_category((select project_id from ctx),(select id from cat),'{"title":"Rollback fixture","kind":"other","activity_type":"task"}',null);
 raise exception 'Deliberate later failure' using errcode='22023';
end $$;
update app.automation_rules set enabled=true where id='activity_created_collaborators';
create temporary table counts_before as select
 (select count(*) from app.domain_events) events,
 (select count(*) from public.notifications) notifications;
select throws_ok($$select pg_temp.fail_after_activity()$$,'22023',null,'Later failure rolls back domain and side effects');
select is((select count(*) from app.domain_events),(select events from counts_before),'No event survives later failure');
select is((select count(*) from public.notifications),(select notifications from counts_before),'No notification survives later failure');
-- Construct an unprocessed internal fixture to test a false condition.
update public.commitments set deleted_at=now() where id=(select id from disabled_item);
insert into app.domain_events(event_type,project_id,resource_type,resource_id,payload,deduplication_key)
select 'activity.created',project_id,'activity',disabled_item.id,'{}','condition-fixture' from ctx,disabled_item;
select app.process_domain_event(id) from app.domain_events where deduplication_key='condition-fixture' and project_id=(select project_id from ctx);
select is((select count(*)::int from app.automation_action_runs r join app.domain_events e on e.id=r.event_id where e.deduplication_key='condition-fixture' and e.project_id=(select project_id from ctx)),0,'False activity_live condition skips action');
-- Additional persisted-schema verification; all fixtures remain rollback-only.
select pg_temp.login('aa270000-0000-0000-0000-000000000027','completion-a@t.co');
select throws_ok($$delete from app.domain_events$$,'42501',null,'Authenticated users cannot delete private events');
select throws_ok($$select * from app.domain_event_types$$,'42501',null,'Registry is private');
select throws_ok($$select * from app.automation_rules$$,'42501',null,'Rules are private');
select throws_ok($$select * from app.domain_event_processing$$,'42501',null,'Processing receipts are private');
select throws_ok($$select * from app.automation_action_runs$$,'42501',null,'Action receipts are private');
select throws_ok($$select app.emit_domain_event('payment.confirmed',(select project_id from ctx),(select id from item),'{}','spoof')$$,'42501',null,'Future privileged emitter denied');
update public.commitments set title='Re-saved Activity' where id=(select id from item);
create temporary table recurring_item as select (public.create_activity_in_category(
 (select project_id from ctx),(select id from cat),
 '{"title":"Recurring event check","kind":"other","activity_type":"task","recurrence_frequency":"weekly","recurrence_interval":1,"recurrence_start_date":"2026-09-09","starts_at":"2026-09-09T09:00:00Z"}',null)).id;
select public.complete_commitment_occurrence((select id from recurring_item),'2026-09-09');
set local role postgres;
select is((select count(*)::int from app.domain_events where resource_id=(select id from recurring_item) and event_type='activity.completed'),0,'Occurrence completion does not complete parent');
select is((select count(*)::int from app.domain_events where resource_id=(select id from item) and event_type='activity.created'),1,'Re-saving does not recreate creation event');
select is((select count(*)::int from public.notifications where commitment_id=(select id from item) and recipient_user_id='aa270000-0000-0000-0000-000000000027'),0,'Creator excluded from notification');
select is((select count(*)::int from public.notifications where commitment_id=(select id from item) and recipient_user_id='bb270000-0000-0000-0000-000000000027'),1,'Eligible collaborator receives exactly one');
select ok((select bool_and(e.project_id=c.project_id and e.resource_type='activity' and e.actor_user_id='aa270000-0000-0000-0000-000000000027'::uuid) from app.domain_events e join public.commitments c on c.id=e.resource_id where e.resource_id=(select id from item)),'Event project, actor and resource references match');
create temporary table deleted_fixture as with c as (
 insert into public.commitments(project_id,title,kind,activity_type,area_id,deleted_at)
 select project_id,'Already deleted','other','task',(select id from cat),now() from ctx returning id
) select * from c;
update public.commitments set status='completed' where id=(select id from deleted_fixture);
select is((select count(*)::int from app.domain_events where resource_id=(select id from deleted_fixture)),0,'Soft-deleted inserts and completion emit no events');
-- Re-enabling a rule does not replay a previously processed disabled event.
update public.commitments set deleted_at=null where id=(select id from disabled_item);
select app.process_domain_event(id) from app.domain_events where resource_id=(select id from disabled_item) and deduplication_key='created';
select is((select count(*)::int from app.automation_action_runs r join app.domain_events e on e.id=r.event_id where e.resource_id=(select id from disabled_item) and e.deduplication_key='created'),0,'Changing rule does not replay history');
select ok(exists(select 1 from app.domain_event_processing p join app.domain_events e on e.id=p.event_id where e.resource_id=(select id from disabled_item) and e.deduplication_key='created'),'Disabled-rule event was marked processed');
select is((select count(*)::int from pg_trigger where tgrelid='public.commitments'::regclass and tgname='activity_domain_events' and not tgisinternal),1,'One event delivery trigger');
select is((select count(*)::int from pg_trigger where tgrelid='public.commitments'::regclass and tgname='activity_created_notifications'),0,'Old direct trigger removed');
select ok(to_regprocedure('app.tg_activity_created_notifications()') is null,'Old notification trigger function removed');

select * from finish();
rollback;
