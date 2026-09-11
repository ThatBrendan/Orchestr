-- pgTAP: dynamic overview read model and profile/activity-aware health gates.
begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

create function pg_temp.login(p_uid uuid, p_email text) returns void language plpgsql as $$
begin
  perform set_config('role','authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub',p_uid,'email',p_email,'role','authenticated')::text, true);
end $$;

insert into auth.users (instance_id,id,aud,role,email,raw_app_meta_data,raw_user_meta_data,
  created_at,updated_at,confirmation_token,email_change,email_change_token_new,recovery_token)
values
 ('00000000-0000-0000-0000-000000000000','aa130000-0000-0000-0000-000000000013','authenticated','authenticated','overview-a@t.co','{}','{"display_name":"Overview A"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','bb130000-0000-0000-0000-000000000013','authenticated','authenticated','overview-b@t.co','{}','{"display_name":"Overview B"}',now(),now(),'','','','');

select pg_temp.login('aa130000-0000-0000-0000-000000000013','overview-a@t.co');

create temporary table pg_temp.profile_projects (id uuid, profile public.project_profile) on commit drop;
insert into pg_temp.profile_projects (id, profile)
select public.create_project('Overview ' || p::text, 'UTC', 'GBP', current_date, current_date + 30, p), p
from unnest(enum_range(null::public.project_profile)) p;

select set_eq(
  $$select profile::text from public.v_project_overview where project_id in (select id from pg_temp.profile_projects)$$,
  $$select profile::text from pg_temp.profile_projects$$,
  'overview read model covers every project profile'
);

insert into public.commitments (project_id, title, kind, activity_type, status, starts_at)
select id, 'Set up social media pages', 'other', 'task', 'confirmed', now() - interval '1 day'
from pg_temp.profile_projects where profile = 'team_project';

insert into public.commitments (project_id, title, kind, activity_type, status)
select id, 'Book hotel', 'accommodation', 'booking', 'confirmed'
from pg_temp.profile_projects where profile = 'group_trip';

insert into public.payments (project_id, commitment_id, type, status, amount_minor, due_on)
select project_id, id, 'deposit', 'scheduled', 10000, current_date - 1
from public.commitments where title = 'Book hotel';

select is(
  (select count(*)::int from public.get_project_health((select id from pg_temp.profile_projects where profile = 'team_project'))
   where subject_label = 'Set up social media pages'
     and code in ('missing_booking_reference','missing_cost')),
  0,
  'task activity does not receive booking/cost health warnings'
);

select is(
  (select count(*)::int from public.get_project_health((select id from pg_temp.profile_projects where profile = 'group_trip'))
   where subject_label = 'Book hotel' and code = 'missing_booking_reference'),
  0,
  'booking reference is optional metadata and creates no Health warning'
);

select is(
  (select dismissible from public.get_project_health((select id from pg_temp.profile_projects where profile = 'group_trip')) where code = 'payment_overdue' limit 1),
  false,
  'payment overdue blocker remains non-dismissible'
);

insert into public.budgets (project_id, total_target_minor)
select id, 1 from pg_temp.profile_projects where profile = 'team_project';
insert into public.commitments (project_id, title, kind, activity_type, status, estimated_cost_minor)
select id, 'Buy test equipment', 'services', 'purchase', 'confirmed', 50000
from pg_temp.profile_projects where profile = 'team_project';

select is(
  (select count(*)::int from public.get_project_health((select id from pg_temp.profile_projects where profile = 'team_project'))
   where code = 'budget_exceeded'),
  0,
  'budget health is hidden when Budget module is hidden by profile'
);

update public.projects
set module_visibility = '{"budget":true}'::jsonb
where id = (select id from pg_temp.profile_projects where profile = 'team_project');

select is(
  (select count(*)::int from public.get_project_health((select id from pg_temp.profile_projects where profile = 'team_project'))
   where code = 'budget_exceeded'),
  1,
  'budget health appears when Budget module is explicitly enabled'
);

select ok(
  (
    select overdue_activity_count
    from public.v_project_overview
    where project_id = (select id from pg_temp.profile_projects where profile = 'team_project')
  ) >= 1,
  'overview exposes overdue activity count'
);

select pg_temp.login('bb130000-0000-0000-0000-000000000013','overview-b@t.co');
select is(
  (select count(*)::int from public.v_project_overview where project_id in (select id from pg_temp.profile_projects)),
  0,
  'non-member cannot read overview rows for another project'
);

select * from finish();
rollback;
