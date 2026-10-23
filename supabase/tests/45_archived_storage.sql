begin;
-- Only synthetic object metadata is touched, and the entire suite rolls back.
-- Match the Storage API's transaction flag while retaining all object RLS.
set local storage.allow_delete_query='true';
create extension if not exists pgtap with schema extensions;
select no_plan();
create function pg_temp.login(i integer) returns void language plpgsql as $$ begin
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub','45000000-0000-4000-8000-'||lpad(i::text,12,'0'),'role','authenticated')::text,true);
end $$;
create function pg_temp.changed(sql text) returns integer language plpgsql as $$ declare n integer; begin execute sql; get diagnostics n=row_count; return n; end $$;
insert into auth.users(instance_id,id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,confirmation_token,email_change,email_change_token_new,recovery_token)
select '00000000-0000-0000-0000-000000000000',('45000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'authenticated','authenticated','storage-test-'||i||'@example.test','{}','{}',now(),now(),'','','','' from generate_series(1,3) i;
select pg_temp.login(1);
create temp table ctx as select public.create_project('Storage rollback fixture','UTC','GBP',current_date) id;
grant select on ctx to authenticated;
insert into storage.objects(bucket_id,name) select bucket,id::text||'/file' from ctx,unnest(array['project-media','attachments']) bucket;
select is((select count(*)::int from storage.objects where name=(select id::text||'/file' from ctx)),2,'Organizer reads own objects');
select is(pg_temp.changed($$update storage.objects set metadata='{"test":true}' where name=(select id::text||'/file' from ctx)$$),2,'Active organizer can update both buckets');
select pg_temp.login(2);
select is((select count(*)::int from storage.objects where name=(select id::text||'/file' from ctx)),0,'Outsider cannot read objects');
select is(pg_temp.changed($$delete from storage.objects where name=(select id::text||'/file' from ctx)$$),0,'Outsider cannot delete objects');
select throws_ok($$insert into storage.objects(bucket_id,name) select 'attachments',id::text||'/foreign' from ctx$$,'42501',null,'Outsider cannot insert into project path');
select pg_temp.login(1);
select throws_ok($$insert into storage.objects(bucket_id,name) values('attachments','malformed/file')$$,'42501',null,'Malformed path fails closed');
set local role postgres;
insert into public.project_members(project_id,user_id,display_name,role,status) select id,'45000000-0000-4000-8000-000000000003','Storage viewer','viewer','active' from ctx;
select pg_temp.login(3);
select is((select count(*)::int from storage.objects where name=(select id::text||'/file' from ctx)),2,'Viewer may read project objects');
select is(pg_temp.changed($$update storage.objects set metadata='{}' where name=(select id::text||'/file' from ctx)$$),0,'Viewer cannot update objects');
select is(pg_temp.changed($$delete from storage.objects where name=(select id::text||'/file' from ctx)$$),0,'Viewer cannot delete objects');
select pg_temp.login(1);
update public.projects set status='archived' where id=(select id from ctx);
select is((select count(*)::int from storage.objects where name=(select id::text||'/file' from ctx)),2,'Archived objects remain readable');
select is(pg_temp.changed($$update storage.objects set metadata='{}' where bucket_id='attachments' and name=(select id::text||'/file' from ctx)$$),0,'Archived organizer cannot update attachments');
select is(pg_temp.changed($$update storage.objects set metadata='{}' where bucket_id='project-media' and name=(select id::text||'/file' from ctx)$$),0,'Archived organizer cannot update media');
select is(pg_temp.changed($$delete from storage.objects where bucket_id='attachments' and name=(select id::text||'/file' from ctx)$$),0,'Archived organizer cannot delete attachments');
select is(pg_temp.changed($$delete from storage.objects where bucket_id='project-media' and name=(select id::text||'/file' from ctx)$$),0,'Archived organizer cannot delete media');
select throws_ok($$insert into storage.objects(bucket_id,name) select 'attachments',id::text||'/new' from ctx$$,'42501',null,'Archived attachment insert denied');
select throws_ok($$insert into storage.objects(bucket_id,name) select 'project-media',id::text||'/new' from ctx$$,'42501',null,'Archived media insert denied');
set local role postgres;
-- Unarchive separately: the project guard intentionally rejects editing archived fields.
update public.projects set status='active' where id=(select id from ctx);
update public.projects set deleted_at=now() where id=(select id from ctx);
select pg_temp.login(1);
select is(pg_temp.changed($$update storage.objects set metadata='{}' where bucket_id='attachments' and name=(select id::text||'/file' from ctx)$$),0,'Deleted organizer cannot update attachments');
select is(pg_temp.changed($$update storage.objects set metadata='{}' where bucket_id='project-media' and name=(select id::text||'/file' from ctx)$$),0,'Deleted organizer cannot update media');
select is(pg_temp.changed($$delete from storage.objects where bucket_id='attachments' and name=(select id::text||'/file' from ctx)$$),0,'Deleted organizer cannot delete attachments');
select is(pg_temp.changed($$delete from storage.objects where bucket_id='project-media' and name=(select id::text||'/file' from ctx)$$),0,'Deleted organizer cannot delete media');
select throws_ok($$insert into storage.objects(bucket_id,name) select 'attachments',id::text||'/deleted' from ctx$$,'42501',null,'Deleted attachment insert denied');
select throws_ok($$insert into storage.objects(bucket_id,name) select 'project-media',id::text||'/deleted' from ctx$$,'42501',null,'Deleted media insert denied');
select * from finish();
rollback;
