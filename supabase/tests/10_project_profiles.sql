-- pgTAP: project profiles persist through secure project creation and updates.
begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

create function pg_temp.login(p_uid uuid, p_email text) returns void language plpgsql as $$
begin
  perform set_config('role','authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub',p_uid,'email',p_email,'role','authenticated')::text, true);
end $$;
create function pg_temp.logout() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims','', true);
  perform set_config('role','postgres', true);
end $$;

insert into auth.users (instance_id,id,aud,role,email,raw_app_meta_data,raw_user_meta_data,
  created_at,updated_at,confirmation_token,email_change,email_change_token_new,recovery_token)
values
 ('00000000-0000-0000-0000-000000000000','ab000000-0000-0000-0000-000000000010','authenticated','authenticated','profile-a@t.co','{}','{"display_name":"Profile A"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','bc000000-0000-0000-0000-000000000020','authenticated','authenticated','profile-b@t.co','{}','{"display_name":"Profile B"}',now(),now(),'','','','');

select set_config('role','anon', true); select set_config('request.jwt.claims','', true);
select throws_ok(
  $$select public.create_project('Anon profile project','UTC','GBP',null,null,'blank')$$,
  '42501',
  null,
  'anon: cannot create project with profile'
);
select pg_temp.logout();

select pg_temp.login('ab000000-0000-0000-0000-000000000010','profile-a@t.co');
create temporary table pg_temp.profile_projects (id uuid, profile public.project_profile) on commit drop;

insert into pg_temp.profile_projects (id, profile)
select public.create_project('Profile ' || p::text, 'UTC', 'GBP', null, null, p), p
from unnest(enum_range(null::public.project_profile)) p;

select set_eq(
  $$select profile::text from public.projects where id in (select id from pg_temp.profile_projects)$$,
  $$select profile::text from pg_temp.profile_projects$$,
  'create_project persists every supported profile'
);

select is(
  (select profile::text from public.projects where id = public.create_project('Default profile','UTC','GBP',null,null)),
  'blank',
  'create_project defaults omitted profile to blank'
);

select is(
  (select profile::text from public.v_my_projects where project_id = (select id from pg_temp.profile_projects where profile = 'group_trip')),
  'group_trip',
  'v_my_projects exposes profile'
);

select ok(
  (select jsonb_typeof(module_visibility) = 'object' from public.projects where id = (select id from pg_temp.profile_projects limit 1)),
  'module_visibility defaults to an object'
);

insert into public.commitments (id, project_id, title, kind, status, estimated_cost_minor)
values (
  'ac100000-0000-0000-0000-000000000010',
  (select id from pg_temp.profile_projects where profile = 'group_trip'),
  'Preserved activity',
  'other',
  'researching',
  5000
);

update public.projects
set profile = 'team_project',
    module_visibility = '{"budget":false}'::jsonb
where id = (select id from pg_temp.profile_projects where profile = 'group_trip');

select is(
  (select count(*)::int from public.commitments where id = 'ac100000-0000-0000-0000-000000000010'),
  1,
  'changing profile preserves commitments'
);

select is(
  (select module_visibility->>'budget' from public.projects where id = (select project_id from public.commitments where id = 'ac100000-0000-0000-0000-000000000010')),
  'false',
  'module visibility override persists'
);
select pg_temp.logout();

select pg_temp.login('bc000000-0000-0000-0000-000000000020','profile-b@t.co');
select is(
  (select count(*)::int from public.v_my_projects where project_id in (select id from pg_temp.profile_projects)),
  0,
  'non-member cannot see profile projects'
);
select pg_temp.logout();

select * from finish();
rollback;
