begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
create function pg_temp.login(i integer) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', '29000000-0000-0000-0000-' || lpad(i::text,12,'0'), 'email','milestone-' || i || '@example.test','role','authenticated')::text, true);
end $$;
create function pg_temp.wc(sql text) returns integer language plpgsql as $$
declare n integer; begin execute sql; get diagnostics n = row_count; return n; end $$;
insert into auth.users(instance_id,id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,confirmation_token,email_change,email_change_token_new,recovery_token)
select '00000000-0000-0000-0000-000000000000',('29000000-0000-0000-0000-' || lpad(i::text,12,'0'))::uuid,
  'authenticated','authenticated','milestone-' || i || '@example.test','{}','{}',now(),now(),'','','',''
from generate_series(1,8) i;
select pg_temp.login(1);
create temporary table ctx as select public.create_project('Beta Trip','UTC','GBP','2026-01-01',null,'group_trip') as id;
set local role postgres;
insert into public.project_members(project_id,user_id,display_name,role,status,removed_at,deleted_at)
select ctx.id,('29000000-0000-0000-0000-' || lpad(i::text,12,'0'))::uuid,'Collaborator ' || i,
  case i when 2 then 'organizer' when 4 then 'viewer' else 'member' end::public.member_role,
  case when i=5 then 'removed' else 'active' end::public.member_status,
  case when i=5 then now() end, case when i=6 then now() end
from ctx cross join generate_series(2,6) i;
select pg_temp.login(7);
create temporary table other_project as select public.create_project('Unrelated','UTC','GBP','2026-01-01') as id;
select pg_temp.login(1);
create temporary table created_activity as
select (public.save_activity_with_split((select id from ctx),null,
  jsonb_build_object('title','Book restaurant','kind','other','activity_type','booking','owner_member_id',(select id from public.project_members where project_id=(select id from ctx) and user_id='29000000-0000-0000-0000-000000000003')),null)).id;
select is((select count(*)::int from public.v_my_activity_notifications),0,'Creator receives no self-notification');
set local role postgres;
select is((select count(*)::int from public.notifications where commitment_id=(select id from created_activity)),3,'Exactly Organizer, Member and Viewer receive one event each');
select is((select count(*)::int from public.notifications where commitment_id=(select id from created_activity) and read_at is null),3,'Notifications initially unread');
select is((select count(*)::int from public.notifications where commitment_id=(select id from created_activity) and recipient_user_id in ('29000000-0000-0000-0000-000000000005','29000000-0000-0000-0000-000000000006','29000000-0000-0000-0000-000000000007')),0,'Removed, deleted and wrong-project users excluded');
select pg_temp.login(2);
select is((select count(*)::int from public.v_my_activity_notifications where commitment_id=(select id from created_activity)),1,'Other Organizer gets one notification');
select pg_temp.login(3);
select is((select count(*)::int from public.v_my_activity_notifications where commitment_id=(select id from created_activity)),1,'Assigned Member gets exactly one notification');
select is((select activity_title from public.v_my_activity_notifications where commitment_id=(select id from created_activity)),'Book restaurant','Human-readable activity title');
select is((select project_name from public.v_my_activity_notifications where commitment_id=(select id from created_activity)),'Beta Trip','Human-readable project name');
select is((select project_id from public.v_my_activity_notifications where commitment_id=(select id from created_activity)),(select id from ctx),'Deep-link project preserved');
select lives_ok($$select public.mark_notification_read(id) from public.v_my_activity_notifications where commitment_id=(select id from created_activity)$$,'Recipient can mark read');
select is((select count(*)::int from public.v_my_activity_notifications where read_at is null),0,'Read removes unread count');
select is((select count(*)::int from public.v_my_activity_notifications where read_at is not null),1,'Read state persists');
select throws_ok($$insert into public.notifications(project_id,commitment_id,recipient_user_id) select ctx.id,c.id,'29000000-0000-0000-0000-000000000007' from ctx,created_activity c$$,'42501',null,'Client cannot choose recipients or insert notifications');
select throws_ok($$update public.notifications set recipient_user_id='29000000-0000-0000-0000-000000000007'$$,'42501',null,'Client cannot retarget notification');
select is(pg_temp.wc($$update public.projects set status='completed' where id=(select id from ctx)$$),0,'Member cannot complete');
select pg_temp.login(4);
select is((select count(*)::int from public.v_my_activity_notifications),1,'Active Viewer receives one event');
select is(pg_temp.wc($$update public.projects set status='completed' where id=(select id from ctx)$$),0,'Viewer cannot complete');
select pg_temp.login(7);
select is((select count(*)::int from public.v_my_activity_notifications),0,'Non-member sees no notifications');
select pg_temp.login(1);
select lives_ok($$update public.commitments set title='Book restaurant updated',notes='Edited' where id=(select id from created_activity)$$,'Activity edits succeed');
select lives_ok($$insert into public.commitment_participants(project_id,commitment_id,member_id) select ctx.id,c.id,m.id from ctx,created_activity c,public.project_members m where m.project_id=ctx.id and m.user_id='29000000-0000-0000-0000-000000000003'$$,'Adding assigned participant succeeds');
set local role postgres;
select is((select count(*)::int from public.notifications where commitment_id=(select id from created_activity)),3,'Edits and participants do not duplicate notifications');
select lives_ok($$insert into public.notifications(project_id,commitment_id,recipient_user_id) select project_id,commitment_id,recipient_user_id from public.notifications on conflict(recipient_user_id,commitment_id,kind) do nothing$$,'Fan-out retry is idempotent');
select is((select count(*)::int from public.notifications where commitment_id=(select id from created_activity)),3,'Unique event/recipient constraint prevents duplicates');
select pg_temp.login(1);
create temporary table project_before as select to_jsonb(p) - array['status','updated_at'] as fields from public.projects p where id=(select id from ctx);
select lives_ok($$update public.projects set status='completed' where id=(select id from ctx) and status='active'$$,'Organizer completes an undated active project');
select is((select status::text from public.projects where id=(select id from ctx)),'completed','Completed persisted');
select ok((select ends_on is null from public.projects where id=(select id from ctx)),'Completion does not require or change end date');
select is((select to_jsonb(p) - array['status','updated_at'] from public.projects p where id=(select id from ctx)),(select fields from project_before),'Completion preserves all other project fields');
select is((select count(*)::int from public.v_my_projects where project_id=(select id from ctx) and status in ('draft','active')),0,'Completed disappears from active read model selection');
select is((select count(*)::int from public.v_my_projects where project_id=(select id from ctx) and status='completed'),1,'Completed remains readable in Past selection');
select is((select attention_count from public.v_my_projects where project_id=(select id from ctx)),0,'Completed summary has no active attention noise');
select is((select count(*)::int from public.get_my_attention() where project_id=(select id from ctx)),0,'Completed absent from dashboard attention');
select lives_ok($$select * from public.get_project_health((select id from ctx))$$,'Historical project health still accessible');
select lives_ok($$update public.commitments set notes='History remains editable' where id=(select id from created_activity)$$,'Completed projects retain existing writable behavior');
select ok(exists(select 1 from public.audit_log where project_id=(select id from ctx) and entity_type='projects' and "before"->>'status'='active' and "after"->>'status'='completed'),'Project completion audit attached to project');
select pg_temp.login(3);
select is(pg_temp.wc($$update public.projects set status='active' where id=(select id from ctx) and status='completed'$$),0,'Member cannot reopen');
select pg_temp.login(4);
select is(pg_temp.wc($$update public.projects set status='active' where id=(select id from ctx) and status='completed'$$),0,'Viewer cannot reopen');
select pg_temp.login(1);
select lives_ok($$update public.projects set status='active' where id=(select id from ctx) and status='completed'$$,'Organizer can reopen');
select is((select count(*)::int from public.v_my_projects where project_id=(select id from ctx) and status in ('draft','active')),1,'Reopened returns to Active');
select ok(exists(select 1 from public.audit_log where project_id=(select id from ctx) and entity_type='projects' and "before"->>'status'='completed' and "after"->>'status'='active'),'Reopen audit written');
select lives_ok($$update public.projects set ends_on=current_date-1 where id=(select id from ctx)$$,'End date can pass');
select is((select status::text from public.projects where id=(select id from ctx)),'active','Past end date does not auto-complete');
select lives_ok($$update public.projects set status='archived' where id=(select id from ctx)$$,'Existing archive behavior retained');
select is(pg_temp.wc($$update public.projects set status='active' where id=(select id from ctx) and status='completed'$$),0,'Stale reopen cannot restore archived project');
select lives_ok($$update public.projects set status='active' where id=(select id from ctx)$$,'Separate unarchive still works');
set local role postgres;
update public.project_members set status='removed',removed_at=now() where project_id=(select id from ctx) and user_id='29000000-0000-0000-0000-000000000004';
select pg_temp.login(4);
select is((select count(*)::int from public.v_my_activity_notifications),0,'Removal revokes previously delivered notification visibility');
select pg_temp.login(1);
select public.soft_delete_commitment((select id from created_activity));
select pg_temp.login(2);
select is((select count(*)::int from public.v_my_activity_notifications),0,'Deleted Activity disappears from inbox');
select * from finish();
rollback;
