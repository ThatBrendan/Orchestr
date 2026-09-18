-- pgTAP: project notes permissions, length limit, blank values, and isolation.
begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

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
select public.create_project('Project notes','UTC','GBP','2026-01-01',null,'team_project') as project_id;

insert into public.project_members (project_id, user_id, display_name, role)
select project_id, 'bb120000-0000-0000-0000-000000000012', 'Notes B', 'member' from pg_temp.ctx;
insert into public.project_members (project_id, user_id, display_name, role)
select project_id, 'cc120000-0000-0000-0000-000000000012', 'Notes C', 'viewer' from pg_temp.ctx;

update public.projects set notes = 'Client prefers Friday updates.' where id = (select project_id from pg_temp.ctx);
select is(
  (select notes from public.projects where id = (select project_id from pg_temp.ctx)),
  'Client prefers Friday updates.',
  'organizer can edit project notes'
);

update public.projects set notes = repeat('x', 10000) where id = (select project_id from pg_temp.ctx);
select is(
  char_length((select notes from public.projects where id = (select project_id from pg_temp.ctx))),
  10000,
  '10000 characters accepted'
);

select throws_ok(
  $$update public.projects set notes = repeat('x', 10001) where id = (select project_id from pg_temp.ctx)$$,
  '23514',
  null,
  'more than 10000 characters rejected'
);

update public.projects set notes = null where id = (select project_id from pg_temp.ctx);
select is(
  (select notes from public.projects where id = (select project_id from pg_temp.ctx)),
  null,
  'blank notes allowed'
);

select pg_temp.login('bb120000-0000-0000-0000-000000000012','notes-b@t.co');
select is(
  pg_temp.wc($$update public.projects set notes = 'member edit' where id = (select project_id from pg_temp.ctx)$$),
  0,
  'member cannot edit project notes under current project settings permissions'
);

select pg_temp.login('cc120000-0000-0000-0000-000000000012','notes-c@t.co');
select is(
  pg_temp.wc($$update public.projects set notes = 'viewer edit' where id = (select project_id from pg_temp.ctx)$$),
  0,
  'viewer cannot edit project notes'
);

select pg_temp.login('aa120000-0000-0000-0000-000000000012','notes-a@t.co');
update public.projects set status = 'archived' where id = (select project_id from pg_temp.ctx);
select throws_ok(
  $$update public.projects set notes = 'archived edit' where id = (select project_id from pg_temp.ctx)$$,
  '42501',
  null,
  'archived project notes are read-only'
);

select pg_temp.login('dd120000-0000-0000-0000-000000000012','notes-d@t.co');
select is(
  (select count(*)::int from public.projects where id = (select project_id from pg_temp.ctx)),
  0,
  'non-member cannot read project notes'
);

select * from finish();
rollback;
