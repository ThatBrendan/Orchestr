-- pgTAP: recurring activities/tasks use bounded derived occurrences plus exception state.
begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

create function pg_temp.login(p_uid uuid, p_email text) returns void language plpgsql as $$
begin
  perform set_config('role','authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub',p_uid,'email',p_email,'role','authenticated')::text, true);
end $$;

insert into auth.users (instance_id,id,aud,role,email,raw_app_meta_data,raw_user_meta_data,
  created_at,updated_at,confirmation_token,email_change,email_change_token_new,recovery_token)
values
 ('00000000-0000-0000-0000-000000000000','aa140000-0000-0000-0000-000000000014','authenticated','authenticated','recurrence-a@t.co','{}','{"display_name":"Recurrence A"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','bb140000-0000-0000-0000-000000000014','authenticated','authenticated','recurrence-b@t.co','{}','{"display_name":"Recurrence B"}',now(),now(),'','','','');

select pg_temp.login('aa140000-0000-0000-0000-000000000014','recurrence-a@t.co');

select set_eq(
  $$select occurrence_date::text from app.recurrence_dates('weekly', 1, '2026-09-09', null, '2026-09-01', '2026-09-30')$$,
  $$values ('2026-09-09'), ('2026-09-16'), ('2026-09-23'), ('2026-09-30')$$,
  'weekly recurrence generates September dates'
);

select set_eq(
  $$select occurrence_date::text from app.recurrence_dates('weekly', 2, '2026-09-09', null, '2026-09-01', '2026-09-30')$$,
  $$values ('2026-09-09'), ('2026-09-23')$$,
  'fortnightly recurrence generates every 2 weeks'
);

select set_eq(
  $$select occurrence_date::text from app.recurrence_dates('monthly', 1, '2026-09-15', null, '2026-09-01', '2026-11-30')$$,
  $$values ('2026-09-15'), ('2026-10-15'), ('2026-11-15')$$,
  'monthly recurrence keeps day-of-month'
);

select set_eq(
  $$select occurrence_date::text from app.recurrence_dates('monthly', 1, '2026-01-31', null, '2026-01-01', '2026-04-30')$$,
  $$values ('2026-01-31'), ('2026-02-28'), ('2026-03-31'), ('2026-04-30')$$,
  'month-end recurrence clamps to last valid day'
);

create temporary table pg_temp.tz_projects (id uuid, timezone text) on commit drop;
insert into pg_temp.tz_projects (id, timezone)
values
  (public.create_project('UTC recurrence', 'UTC', 'GBP', '2026-09-01', '2026-09-30', 'recurring_process'), 'UTC'),
  (public.create_project('London recurrence', 'Europe/London', 'GBP', '2026-09-01', '2026-09-30', 'recurring_process'), 'Europe/London'),
  (public.create_project('NY recurrence', 'America/New_York', 'GBP', '2026-09-01', '2026-09-30', 'recurring_process'), 'America/New_York');

insert into public.commitments (
  project_id, title, kind, activity_type, starts_at, is_all_day,
  recurrence_frequency, recurrence_interval, recurrence_start_date
)
select
  id, 'Contact potential creators', 'other', 'task',
  ('2026-09-09'::timestamp at time zone timezone), true,
  'weekly', 1, '2026-09-09'
from pg_temp.tz_projects;

select results_eq(
  $$select (te.occurs_at at time zone p.timezone)::date::text
    from pg_temp.tz_projects p
    cross join lateral public.get_project_timeline_events(p.id, '2026-09-01', '2026-09-30') te
    where te.event_type = 'recurring_commitment_due' and te.occurrence_date = '2026-09-09'
    order by p.timezone$$,
  $$values ('2026-09-09'), ('2026-09-09'), ('2026-09-09')$$,
  'recurring occurrence dates do not shift across project timezones'
);

select public.complete_commitment_occurrence(
  (select c.id from public.commitments c join pg_temp.tz_projects p on p.id = c.project_id where p.timezone = 'UTC'),
  '2026-09-09'
);

select is(
  (select status from public.get_commitment_occurrences(
    (select c.id from public.commitments c join pg_temp.tz_projects p on p.id = c.project_id where p.timezone = 'UTC'),
    '2026-09-09',
    '2026-09-16'
  ) where occurrence_date = '2026-09-09'),
  'completed',
  'completing one occurrence stores completed state'
);

select is(
  (select status from public.get_commitment_occurrences(
    (select c.id from public.commitments c join pg_temp.tz_projects p on p.id = c.project_id where p.timezone = 'UTC'),
    '2026-09-09',
    '2026-09-16'
  ) where occurrence_date = '2026-09-16'),
  case when '2026-09-16'::date < (now() at time zone 'UTC')::date then 'overdue' else 'upcoming' end,
  'completing one occurrence does not complete the next'
);

select throws_ok(
  $$select public.complete_commitment_occurrence(
    (select c.id from public.commitments c join pg_temp.tz_projects p on p.id = c.project_id where p.timezone = 'UTC'),
    '2026-09-10'
  )$$,
  '22023', null,
  'cannot persist a commitment occurrence outside the recurrence'
);

insert into public.tasks (project_id, title, due_on, recurrence_frequency, recurrence_interval, recurrence_start_date)
select id, 'Recurring follow-up task', '2026-09-09', 'weekly', 1, '2026-09-09'
from pg_temp.tz_projects
where timezone = 'UTC';

select throws_ok(
  $$insert into public.task_occurrences (project_id, task_id, occurrence_date, status, completed_at)
    select t.project_id, t.id, '2026-09-10', 'completed', now()
    from public.tasks t
    join pg_temp.tz_projects p on p.id = t.project_id
    where p.timezone = 'UTC'
      and t.title = 'Recurring follow-up task'$$,
  '22023', null,
  'cannot persist a task occurrence outside the recurrence'
);

select public.skip_commitment_occurrence(
  (select c.id from public.commitments c join pg_temp.tz_projects p on p.id = c.project_id where p.timezone = 'UTC'),
  '2026-09-16', 'Waiting for shortlist'
);

select is(
  (select count(*)::int
   from public.get_project_timeline_events(
     (select id from pg_temp.tz_projects where timezone = 'UTC'),
     '2026-09-16',
     '2026-09-16 23:59:59+00'
   )
   where occurrence_date = '2026-09-16' and status = 'skipped'),
  1,
  'skipped occurrence remains visible with skipped status'
);

select public.stop_commitment_recurrence(
  (select c.id from public.commitments c join pg_temp.tz_projects p on p.id = c.project_id where p.timezone = 'UTC'),
  '2026-09-23'
);

select is(
  (select count(*)::int
   from public.get_project_timeline_events(
     (select id from pg_temp.tz_projects where timezone = 'UTC'),
     '2026-09-24',
     '2026-09-30 23:59:59+00'
   )
   where event_type = 'recurring_commitment_due'),
  0,
  'stopped recurrence does not generate future occurrences after stop date'
);

select pg_temp.login('bb140000-0000-0000-0000-000000000014','recurrence-b@t.co');
select is(
  (select count(*)::int
   from public.get_project_timeline_events(
     (select id from pg_temp.tz_projects where timezone = 'Europe/London'),
     '2026-09-01',
     '2026-09-30'
   )),
  0,
  'non-member cannot read recurring timeline events'
);

select * from finish();
rollback;
