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
 ('00000000-0000-0000-0000-000000000000','aa120000-0000-0000-0000-000000000012','authenticated','authenticated','notes-a@t.co','{}','{"display_name":"Notes A"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','bb120000-0000-0000-0000-000000000012','authenticated','authenticated','notes-b@t.co','{}','{"display_name":"Notes B"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','cc120000-0000-0000-0000-000000000012','authenticated','authenticated','notes-c@t.co','{}','{"display_name":"Notes C"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','dd120000-0000-0000-0000-000000000012','authenticated','authenticated','notes-d@t.co','{}','{"display_name":"Notes D"}',now(),now(),'','','','');

select pg_temp.login('aa120000-0000-0000-0000-000000000012','notes-a@t.co');
create temporary table pg_temp.ctx as
select public.create_project('Project notes','UTC','GBP',null,null,'team_project') as project_id;

insert into public.project_members (project_id, user_id, display_name, role)
select project_id, 'bb120000-0000-0000-0000-000000000012', 'Notes B', 'member' from pg_temp.ctx;
insert into public.project_members (project_id, user_id, display_name, role)
select project_id, 'cc120000-0000-0000-0000-000000000012', 'Notes C', 'viewer' from pg_temp.ctx;

create temporary table pg_temp.note_ids(label text,id uuid);
insert into pg_temp.note_ids values('organizer',public.create_project_note((select project_id from pg_temp.ctx),' Organizer title ',' Body '));
select is((select title from public.v_project_notes where id=(select id from pg_temp.note_ids where label='organizer')),'Organizer title','Create trims title');
select is((select body from public.v_project_notes where id=(select id from pg_temp.note_ids where label='organizer')),'Body','Create trims body');
select is((select creator_name from public.v_project_notes where id=(select id from pg_temp.note_ids where label='organizer')),'Notes A','Creator included in one read model');
select lives_ok($$select public.update_project_note((select id from pg_temp.note_ids where label='organizer'),'Edited','Edited body')$$,'Organizer edits own');
select throws_ok($$select public.create_project_note((select project_id from pg_temp.ctx),repeat('x',121),'Body')$$,'23514',null,'Title length enforced');
select throws_ok($$select public.create_project_note((select project_id from pg_temp.ctx),'Title',repeat('x',10001))$$,'23514',null,'Body length enforced');
select throws_ok($$select public.create_project_note((select project_id from pg_temp.ctx),E' \t\n ','Body')$$,'23514',null,'Blank title rejected');
select throws_ok($$select public.create_project_note((select project_id from pg_temp.ctx),'Title',E' \t\n ')$$,'23514',null,'Blank body rejected');
select lives_ok($$select public.create_project_note((select project_id from pg_temp.ctx),repeat('x',120),repeat('x',10000))$$,'Maximum lengths accepted');
select pg_temp.login('bb120000-0000-0000-0000-000000000012','notes-b@t.co');
select lives_ok($$insert into pg_temp.note_ids values('member',public.create_project_note((select project_id from pg_temp.ctx),'Member title','Member body'))$$,'Member creates own');
select lives_ok($$select public.update_project_note((select id from pg_temp.note_ids where label='member'),'Edited','Edited body')$$,'Member edits own');
select throws_ok($$select public.update_project_note((select id from pg_temp.note_ids where label='organizer'),'Edited','Edited body')$$,'42501',null,'Member cannot edit others');
select throws_ok($$select public.soft_delete_project_note((select id from pg_temp.note_ids where label='organizer'))$$,'42501',null,'Member cannot delete others');
select lives_ok($$select public.soft_delete_project_note((select id from pg_temp.note_ids where label='member'))$$,'Member deletes own');
select is((select count(*)::int from public.v_project_notes where id=(select id from pg_temp.note_ids where label='member')),0,'Deleted note hidden');
select pg_temp.login('cc120000-0000-0000-0000-000000000012','notes-c@t.co');
select ok((select count(*) from public.v_project_notes)>0,'Viewer reads notes');
select throws_ok($$select public.create_project_note((select project_id from pg_temp.ctx),'Title','Body')$$,'42501',null,'Viewer cannot create');
select throws_ok($$select public.update_project_note((select id from pg_temp.note_ids where label='organizer'),'Edited','Edited body')$$,'42501',null,'Viewer cannot edit');
select throws_ok($$select public.soft_delete_project_note((select id from pg_temp.note_ids where label='organizer'))$$,'42501',null,'Viewer cannot delete');
select pg_temp.login('dd120000-0000-0000-0000-000000000012','notes-d@t.co');
select is((select count(*)::int from public.v_project_notes),0,'Nonmember cannot read notes');
select throws_ok($$select public.create_project_note((select project_id from pg_temp.ctx),'Title','Body')$$,'42501',null,'Nonmember cannot create');
select throws_ok($$select public.update_project_note((select id from pg_temp.note_ids where label='organizer'),'Edited','Edited body')$$,'42501',null,'Nonmember cannot edit');
select pg_temp.login('aa120000-0000-0000-0000-000000000012','notes-a@t.co');
insert into pg_temp.note_ids values('organizer-delete',public.create_project_note((select project_id from pg_temp.ctx),'Remove','Body'));
select lives_ok($$select public.soft_delete_project_note((select id from pg_temp.note_ids where label='organizer-delete'))$$,'Organizer deletes own');
select pg_temp.login('bb120000-0000-0000-0000-000000000012','notes-b@t.co');
insert into pg_temp.note_ids values('member-other',public.create_project_note((select project_id from pg_temp.ctx),'Member','Body'));
select pg_temp.login('aa120000-0000-0000-0000-000000000012','notes-a@t.co');
select lives_ok($$select public.update_project_note((select id from pg_temp.note_ids where label='member-other'),'Edited','Edited body')$$,'Organizer edits others');
select lives_ok($$select public.soft_delete_project_note((select id from pg_temp.note_ids where label='member-other'))$$,'Organizer deletes others');
select public.create_project_note((select project_id from pg_temp.ctx),'Fill '||n,'Body') from generate_series(1,18) n;
select is((select count(*)::int from public.v_project_notes),20,'20 active notes per project');
select throws_ok($$select public.create_project_note((select project_id from pg_temp.ctx),'Title','Body')$$,'P0001',null,'Twenty-first note rejected');
select lives_ok($$select public.soft_delete_project_note((select id from pg_temp.note_ids where label='organizer'))$$,'Delete at limit');
select lives_ok($$select public.create_project_note((select project_id from pg_temp.ctx),'Title','Body')$$,'Deleted notes no longer count toward limit');
update public.projects set status='archived' where id=(select project_id from pg_temp.ctx);
select is((select count(*)::int from public.v_project_notes),20,'Archived notes readable');
select throws_ok($$select public.create_project_note((select project_id from pg_temp.ctx),'Title','Body')$$,'P0001',null,'Archived create rejected');
select throws_ok($$select public.update_project_note((select id from public.v_project_notes limit 1),'No','No')$$,'P0001',null,'Archived edit rejected');
select throws_ok($$select public.soft_delete_project_note((select id from public.v_project_notes limit 1))$$,'P0001',null,'Archived delete rejected');
select throws_ok($$insert into public.project_notes(project_id,title,body) values((select project_id from pg_temp.ctx),'Bypass','Bypass')$$,'42501',null,'Direct write cannot bypass limit or attribution');
set local role postgres;
select set_config('request.jwt.claims','',true);
select ok(exists(select 1 from public.audit_log where entity_type='project_notes' and action='create'),'Create audited');
select ok(exists(select 1 from public.audit_log where entity_type='project_notes' and action='update'),'Edit audited');
select ok(exists(select 1 from public.audit_log where entity_type='project_notes' and action='soft_delete'),'Delete audited');
insert into public.projects(id,name,timezone,currency) values('ee180000-0000-0000-0000-000000000018','Other','UTC','GBP');
select throws_ok($$insert into public.project_notes(project_id,created_by,title,body) select 'ee180000-0000-0000-0000-000000000018',created_by,'Cross project','Body' from public.project_notes where created_by is not null limit 1$$,'23503',null,'Creator cannot belong to another project');
select * from finish();
rollback;
