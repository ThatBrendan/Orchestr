-- Replay the actual migration against legacy fixtures inside a rolled-back
-- transaction. Run only through the local test suite, never on production.
begin;
create extension if not exists pgtap with schema extensions;
select plan(6);
-- Return this entity to its pre-migration state; transaction rollback restores it.
drop view public.v_project_notes;
drop function public.create_project_note(uuid,text,text);
drop function public.update_project_note(uuid,text,text);
drop function public.soft_delete_project_note(uuid);
drop table public.project_notes;
insert into public.projects(id,name,timezone,currency,notes) values
 ('ff190000-0000-0000-0000-000000000001','Legacy','UTC','GBP',E'  Existing content\nSecond line  '),
 ('ff190000-0000-0000-0000-000000000002','Blank','UTC','GBP',E' \n\t '),
 ('ff190000-0000-0000-0000-000000000003','Null','UTC','GBP',null),
 ('ff190000-0000-0000-0000-000000000004','Archived','UTC','GBP','Archived content');
update public.projects set status='archived' where id='ff190000-0000-0000-0000-000000000004';
\ir ../migrations/20260911130000_multi_project_notes.sql
select is((select count(*)::int from public.project_notes where project_id='ff190000-0000-0000-0000-000000000001'),1,'One legacy note migrated');
select is((select body from public.project_notes where project_id='ff190000-0000-0000-0000-000000000001'),E'  Existing content\nSecond line  ','Legacy content preserved exactly');
select ok((select created_by is null and title='Project note' from public.project_notes where project_id='ff190000-0000-0000-0000-000000000001'),'No invented author; sensible title');
select is((select count(*)::int from public.project_notes where project_id in ('ff190000-0000-0000-0000-000000000002','ff190000-0000-0000-0000-000000000003')),0,'Blank and null skipped');
select is((select body from public.project_notes where project_id='ff190000-0000-0000-0000-000000000004'),'Archived content','Archived notes preserved');
select is((select notes from public.projects where id='ff190000-0000-0000-0000-000000000001'),E'  Existing content\nSecond line  ','Legacy column remains intact');
select * from finish();
rollback;
