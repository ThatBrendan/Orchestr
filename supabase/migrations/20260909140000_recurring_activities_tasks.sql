-- ============================================================================
-- Recurring Activities and Tasks
-- Store recurrence on the source row; persist only per-occurrence state changes.
-- ============================================================================

create type public.recurrence_frequency as enum ('weekly', 'monthly');
create type public.occurrence_status as enum ('completed', 'skipped');

alter table public.commitments
  add column recurrence_frequency public.recurrence_frequency,
  add column recurrence_interval int,
  add column recurrence_start_date date,
  add column recurrence_end_date date,
  add column recurrence_active boolean not null default true,
  add constraint chk_commitment_recurrence check (
    (
      recurrence_frequency is null
      and recurrence_interval is null
      and recurrence_start_date is null
      and recurrence_end_date is null
    )
    or (
      recurrence_frequency is not null
      and recurrence_interval in (1, 2)
      and recurrence_start_date is not null
      and (recurrence_end_date is null or recurrence_end_date >= recurrence_start_date)
    )
  ),
  add constraint chk_commitment_recurrence_interval check (
    recurrence_frequency is null
    or (recurrence_frequency = 'weekly' and recurrence_interval in (1, 2))
    or (recurrence_frequency = 'monthly' and recurrence_interval = 1)
  ),
  add constraint chk_commitment_recurrence_stop check (
    recurrence_active or recurrence_end_date is not null
  );

alter table public.tasks
  add column recurrence_frequency public.recurrence_frequency,
  add column recurrence_interval int,
  add column recurrence_start_date date,
  add column recurrence_end_date date,
  add column recurrence_active boolean not null default true,
  add constraint chk_task_recurrence check (
    (
      recurrence_frequency is null
      and recurrence_interval is null
      and recurrence_start_date is null
      and recurrence_end_date is null
    )
    or (
      recurrence_frequency is not null
      and recurrence_interval in (1, 2)
      and recurrence_start_date is not null
      and (recurrence_end_date is null or recurrence_end_date >= recurrence_start_date)
    )
  ),
  add constraint chk_task_recurrence_interval check (
    recurrence_frequency is null
    or (recurrence_frequency = 'weekly' and recurrence_interval in (1, 2))
    or (recurrence_frequency = 'monthly' and recurrence_interval = 1)
  ),
  add constraint chk_task_recurrence_stop check (
    recurrence_active or recurrence_end_date is not null
  );

alter table public.tasks
  add constraint uq_task_project_id unique (project_id, id);

create table public.commitment_occurrences (
  id              uuid primary key default gen_random_uuid(),
  project_id      uuid not null references public.projects(id) on delete cascade,
  commitment_id   uuid not null,
  occurrence_date date not null,
  status          public.occurrence_status not null,
  completed_at    timestamptz,
  skipped_at      timestamptz,
  created_by      uuid,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint uq_commitment_occurrence unique (commitment_id, occurrence_date),
  constraint chk_commitment_occurrence_state check (
    (status = 'completed' and completed_at is not null and skipped_at is null)
    or (status = 'skipped' and skipped_at is not null and completed_at is null)
  ),
  constraint fk_commitment_occurrence_commitment
    foreign key (project_id, commitment_id) references public.commitments(project_id, id) on delete cascade,
  constraint fk_commitment_occurrence_creator
    foreign key (project_id, created_by) references public.project_members(project_id, id) on delete set null
);

create table public.task_occurrences (
  id              uuid primary key default gen_random_uuid(),
  project_id      uuid not null references public.projects(id) on delete cascade,
  task_id         uuid not null,
  occurrence_date date not null,
  status          public.occurrence_status not null,
  completed_at    timestamptz,
  skipped_at      timestamptz,
  created_by      uuid,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint uq_task_occurrence unique (task_id, occurrence_date),
  constraint chk_task_occurrence_state check (
    (status = 'completed' and completed_at is not null and skipped_at is null)
    or (status = 'skipped' and skipped_at is not null and completed_at is null)
  ),
  constraint fk_task_occurrence_task
    foreign key (project_id, task_id) references public.tasks(project_id, id) on delete cascade,
  constraint fk_task_occurrence_creator
    foreign key (project_id, created_by) references public.project_members(project_id, id) on delete set null
);

create index commitments_recurrence_idx
  on public.commitments (project_id, recurrence_active, recurrence_start_date)
  where deleted_at is null and recurrence_frequency is not null;
create index tasks_recurrence_idx
  on public.tasks (project_id, recurrence_active, recurrence_start_date)
  where deleted_at is null and recurrence_frequency is not null;
create index commitment_occurrences_lookup_idx
  on public.commitment_occurrences (project_id, commitment_id, occurrence_date);
create index task_occurrences_lookup_idx
  on public.task_occurrences (project_id, task_id, occurrence_date);

create trigger commitment_occurrences_set_updated_at before update on public.commitment_occurrences
  for each row execute function app.tg_set_updated_at();
create trigger task_occurrences_set_updated_at before update on public.task_occurrences
  for each row execute function app.tg_set_updated_at();
create trigger audit after insert or update or delete on public.commitment_occurrences
  for each row execute function app.tg_audit_row();
create trigger audit after insert or update or delete on public.task_occurrences
  for each row execute function app.tg_audit_row();

alter table public.commitment_occurrences enable row level security;
alter table public.commitment_occurrences force row level security;
alter table public.task_occurrences enable row level security;
alter table public.task_occurrences force row level security;

grant select, insert, update on public.commitment_occurrences to authenticated;
grant select, insert, update on public.task_occurrences to authenticated;

create policy commitment_occurrences_select on public.commitment_occurrences
  for select to authenticated using (app.is_member(project_id));
create policy commitment_occurrences_insert on public.commitment_occurrences
  for insert to authenticated
  with check (
    app.has_role(project_id, array['organizer','member']::public.member_role[])
    and app.is_writable_project(project_id)
  );
create policy commitment_occurrences_update on public.commitment_occurrences
  for update to authenticated
  using (app.has_role(project_id, array['organizer','member']::public.member_role[]))
  with check (
    app.has_role(project_id, array['organizer','member']::public.member_role[])
    and app.is_writable_project(project_id)
  );

create policy task_occurrences_select on public.task_occurrences
  for select to authenticated using (app.is_member(project_id));
create policy task_occurrences_insert on public.task_occurrences
  for insert to authenticated
  with check (
    app.has_role(project_id, array['organizer','member']::public.member_role[])
    and app.is_writable_project(project_id)
  );
create policy task_occurrences_update on public.task_occurrences
  for update to authenticated
  using (app.has_role(project_id, array['organizer','member']::public.member_role[]))
  with check (
    app.has_role(project_id, array['organizer','member']::public.member_role[])
    and app.is_writable_project(project_id)
  );

create or replace function app.recurrence_dates(
  p_frequency public.recurrence_frequency,
  p_interval int,
  p_series_start date,
  p_series_end date,
  p_window_start date,
  p_window_end date
)
returns table (occurrence_date date)
language plpgsql stable set search_path = ''
as $$
declare
  v_date date;
  v_limit date;
  v_month_index int := 0;
  v_month_start date;
  v_day int;
  v_last_day int;
  v_guard int := 0;
begin
  if p_frequency is null or p_interval is null or p_series_start is null
     or p_window_start is null or p_window_end is null or p_window_end < p_window_start then
    return;
  end if;

  v_limit := least(coalesce(p_series_end, p_window_end), p_window_end);
  if v_limit < p_series_start then
    return;
  end if;

  if p_frequency = 'weekly' then
    v_date := p_series_start;
    while v_date < p_window_start loop
      v_date := v_date + (p_interval * 7);
      v_guard := v_guard + 1;
      if v_guard > 1000 then return; end if;
    end loop;

    while v_date <= v_limit loop
      occurrence_date := v_date;
      return next;
      v_date := v_date + (p_interval * 7);
      v_guard := v_guard + 1;
      if v_guard > 1000 then return; end if;
    end loop;
  elsif p_frequency = 'monthly' then
    v_day := extract(day from p_series_start)::int;
    loop
      v_month_start := (date_trunc('month', p_series_start)::date + (v_month_index * p_interval || ' months')::interval)::date;
      v_last_day := extract(day from (v_month_start + interval '1 month - 1 day'))::int;
      v_date := v_month_start + (least(v_day, v_last_day) - 1);

      exit when v_date > v_limit;
      if v_date >= p_window_start then
        occurrence_date := v_date;
        return next;
      end if;

      v_month_index := v_month_index + 1;
      v_guard := v_guard + 1;
      if v_guard > 1000 then return; end if;
    end loop;
  end if;
end;
$$;

comment on function app.recurrence_dates(public.recurrence_frequency, int, date, date, date, date) is
  'Bounded recurrence generator. Monthly dates clamp to the last valid day of the target month.';
revoke execute on function app.recurrence_dates(public.recurrence_frequency, int, date, date, date, date) from public;
grant execute on function app.recurrence_dates(public.recurrence_frequency, int, date, date, date, date) to authenticated, service_role;

create or replace function public.get_project_timeline_events(p_project uuid, p_start timestamptz, p_end timestamptz)
returns table (
  project_id uuid,
  occurs_at timestamptz,
  all_day boolean,
  event_type text,
  title text,
  subject_type text,
  subject_id uuid,
  status text,
  occurrence_date date,
  series_id uuid,
  is_recurring_occurrence boolean,
  occurrence_status text
)
language sql stable security invoker set search_path = ''
as $$
  with bounds as (
    select p_start as starts_at, p_end as ends_at
  )
  select c.project_id, c.starts_at, false, 'commitment_start', c.title,
         'commitment', c.id, c.status::text, null::date, null::uuid, false, null::text
  from public.commitments c, bounds b
  where c.project_id = p_project and c.deleted_at is null and c.status <> 'cancelled'
    and c.starts_at is not null and c.recurrence_frequency is null
    and c.starts_at between b.starts_at and b.ends_at
union all
  select c.project_id, c.ends_at, false, 'commitment_end', c.title,
         'commitment', c.id, c.status::text, null::date, null::uuid, false, null::text
  from public.commitments c, bounds b
  where c.project_id = p_project and c.deleted_at is null and c.status <> 'cancelled'
    and c.ends_at is not null and c.recurrence_frequency is null
    and c.ends_at between b.starts_at and b.ends_at
union all
  select pay.project_id, (pay.due_on::timestamp at time zone pr.timezone), true, 'payment_due',
         'Payment due - ' || c.title, 'payment', pay.id, pay.status::text,
         null::date, null::uuid, false, null::text
  from public.payments pay
  join public.commitments c on c.id = pay.commitment_id and c.deleted_at is null
  join public.projects pr on pr.id = pay.project_id
  cross join bounds b
  where pay.project_id = p_project and pay.deleted_at is null and pay.status = 'scheduled' and pay.due_on is not null
    and (pay.due_on::timestamp at time zone pr.timezone) between b.starts_at and b.ends_at
union all
  select pay.project_id, (pay.paid_on::timestamp at time zone pr.timezone), true, 'payment_made',
         'Payment made - ' || c.title, 'payment', pay.id, pay.status::text,
         null::date, null::uuid, false, null::text
  from public.payments pay
  join public.commitments c on c.id = pay.commitment_id and c.deleted_at is null
  join public.projects pr on pr.id = pay.project_id
  cross join bounds b
  where pay.project_id = p_project and pay.deleted_at is null and pay.status = 'paid' and pay.paid_on is not null
    and (pay.paid_on::timestamp at time zone pr.timezone) between b.starts_at and b.ends_at
union all
  select t.project_id, (t.due_on::timestamp at time zone pr.timezone), true, 'task_due',
         'Task: ' || t.title, 'task', t.id, t.status::text,
         null::date, null::uuid, false, null::text
  from public.tasks t
  join public.projects pr on pr.id = t.project_id
  cross join bounds b
  where t.project_id = p_project and t.deleted_at is null and t.status in ('open','in_progress')
    and t.due_on is not null and t.recurrence_frequency is null
    and (t.due_on::timestamp at time zone pr.timezone) between b.starts_at and b.ends_at
union all
  select m.project_id, (m.on_date::timestamp at time zone pr.timezone), true, 'milestone',
         m.title, 'milestone', m.id, null::text,
         null::date, null::uuid, false, null::text
  from public.milestones m
  join public.projects pr on pr.id = m.project_id
  cross join bounds b
  where m.project_id = p_project
    and (m.on_date::timestamp at time zone pr.timezone) between b.starts_at and b.ends_at
union all
  select pr.id, (pr.starts_on::timestamp at time zone pr.timezone), true,
         'project_start', pr.name || ' starts', 'project', pr.id, pr.status::text,
         null::date, null::uuid, false, null::text
  from public.projects pr, bounds b
  where pr.id = p_project and pr.deleted_at is null and pr.starts_on is not null
    and (pr.starts_on::timestamp at time zone pr.timezone) between b.starts_at and b.ends_at
union all
  select pr.id, (pr.ends_on::timestamp at time zone pr.timezone), true,
         'project_end', pr.name || ' ends', 'project', pr.id, pr.status::text,
         null::date, null::uuid, false, null::text
  from public.projects pr, bounds b
  where pr.id = p_project and pr.deleted_at is null and pr.ends_on is not null
    and (pr.ends_on::timestamp at time zone pr.timezone) between b.starts_at and b.ends_at
union all
  select c.project_id, (rd.occurrence_date::timestamp at time zone pr.timezone), true,
         'recurring_commitment_due', c.title, 'commitment', c.id,
         coalesce(co.status::text, case when rd.occurrence_date < ((now() at time zone pr.timezone)::date) then 'overdue' else 'upcoming' end),
         rd.occurrence_date, c.id, true, co.status::text
  from public.commitments c
  join public.projects pr on pr.id = c.project_id
  cross join bounds b
  join lateral app.recurrence_dates(
    c.recurrence_frequency,
    c.recurrence_interval,
    c.recurrence_start_date,
    case when c.recurrence_active then c.recurrence_end_date else c.recurrence_end_date end,
    (b.starts_at at time zone pr.timezone)::date,
    (b.ends_at at time zone pr.timezone)::date
  ) rd on true
  left join public.commitment_occurrences co
    on co.commitment_id = c.id and co.occurrence_date = rd.occurrence_date
  where c.project_id = p_project and c.deleted_at is null and c.status <> 'cancelled'
    and c.recurrence_frequency is not null
    and coalesce(co.status, 'completed'::public.occurrence_status) <> 'skipped'
union all
  select t.project_id, (rd.occurrence_date::timestamp at time zone pr.timezone), true,
         'recurring_task_due', 'Task: ' || t.title, 'task', t.id,
         coalesce(tocc.status::text, case when rd.occurrence_date < ((now() at time zone pr.timezone)::date) then 'overdue' else 'upcoming' end),
         rd.occurrence_date, t.id, true, tocc.status::text
  from public.tasks t
  join public.projects pr on pr.id = t.project_id
  cross join bounds b
  join lateral app.recurrence_dates(
    t.recurrence_frequency,
    t.recurrence_interval,
    t.recurrence_start_date,
    case when t.recurrence_active then t.recurrence_end_date else t.recurrence_end_date end,
    (b.starts_at at time zone pr.timezone)::date,
    (b.ends_at at time zone pr.timezone)::date
  ) rd on true
  left join public.task_occurrences tocc
    on tocc.task_id = t.id and tocc.occurrence_date = rd.occurrence_date
  where t.project_id = p_project and t.deleted_at is null and t.status <> 'cancelled'
    and t.recurrence_frequency is not null
    and coalesce(tocc.status, 'completed'::public.occurrence_status) <> 'skipped';
$$;

create or replace function public.get_my_timeline_events(p_start timestamptz, p_end timestamptz)
returns table (
  project_id uuid,
  project_name text,
  project_timezone text,
  currency text,
  occurs_at timestamptz,
  all_day boolean,
  event_type text,
  title text,
  subject_type text,
  subject_id uuid,
  status text,
  amount_minor bigint,
  occurrence_date date,
  series_id uuid,
  is_recurring_occurrence boolean,
  occurrence_status text
)
language sql stable security invoker set search_path = ''
as $$
  select
    te.project_id,
    p.name,
    p.timezone,
    p.currency,
    te.occurs_at,
    case when te.subject_type = 'commitment' then coalesce(c.is_all_day, te.all_day) else te.all_day end,
    te.event_type,
    te.title,
    te.subject_type,
    te.subject_id,
    te.status,
    pay.amount_minor,
    te.occurrence_date,
    te.series_id,
    te.is_recurring_occurrence,
    te.occurrence_status
  from public.projects p
  cross join lateral public.get_project_timeline_events(p.id, p_start, p_end) te
  left join public.payments pay
    on te.subject_type = 'payment' and pay.id = te.subject_id and pay.deleted_at is null
  left join public.commitments c
    on te.subject_type = 'commitment' and c.id = te.subject_id and c.deleted_at is null
  where p.deleted_at is null
    and p.status <> 'archived';
$$;

create or replace view public.v_timeline_events
with (security_invoker = true) as
select te.*
from public.projects pr
cross join lateral public.get_project_timeline_events(
  pr.id,
  now() - interval '1 year',
  now() + interval '2 years'
) te
where pr.deleted_at is null;

create or replace view public.v_my_timeline_events
with (security_invoker = true) as
select *
from public.get_my_timeline_events(now() - interval '1 year', now() + interval '2 years');

grant select on public.v_timeline_events, public.v_my_timeline_events to authenticated;
revoke execute on function public.get_project_timeline_events(uuid, timestamptz, timestamptz) from public;
revoke execute on function public.get_my_timeline_events(timestamptz, timestamptz) from public;
grant execute on function public.get_project_timeline_events(uuid, timestamptz, timestamptz) to authenticated;
grant execute on function public.get_my_timeline_events(timestamptz, timestamptz) to authenticated;

create or replace function public.get_commitment_occurrences(p_commitment uuid, p_start date, p_end date)
returns table (
  project_id uuid,
  commitment_id uuid,
  occurrence_date date,
  status text,
  completed_at timestamptz,
  skipped_at timestamptz
)
language sql stable security invoker set search_path = ''
as $$
  select c.project_id, c.id, rd.occurrence_date,
         coalesce(co.status::text, case when rd.occurrence_date < ((now() at time zone pr.timezone)::date) then 'overdue' else 'upcoming' end),
         co.completed_at,
         co.skipped_at
  from public.commitments c
  join public.projects pr on pr.id = c.project_id
  join lateral app.recurrence_dates(c.recurrence_frequency, c.recurrence_interval, c.recurrence_start_date, c.recurrence_end_date, p_start, p_end) rd on true
  left join public.commitment_occurrences co on co.commitment_id = c.id and co.occurrence_date = rd.occurrence_date
  where c.id = p_commitment and c.deleted_at is null and c.recurrence_frequency is not null
  order by rd.occurrence_date;
$$;

revoke execute on function public.get_commitment_occurrences(uuid, date, date) from public;
grant execute on function public.get_commitment_occurrences(uuid, date, date) to authenticated;

create or replace function public.get_task_occurrences(p_task uuid, p_start date, p_end date)
returns table (
  project_id uuid,
  task_id uuid,
  occurrence_date date,
  status text,
  completed_at timestamptz,
  skipped_at timestamptz
)
language sql stable security invoker set search_path = ''
as $$
  select t.project_id, t.id, rd.occurrence_date,
         coalesce(tocc.status::text, case when rd.occurrence_date < ((now() at time zone pr.timezone)::date) then 'overdue' else 'upcoming' end),
         tocc.completed_at,
         tocc.skipped_at
  from public.tasks t
  join public.projects pr on pr.id = t.project_id
  join lateral app.recurrence_dates(t.recurrence_frequency, t.recurrence_interval, t.recurrence_start_date, t.recurrence_end_date, p_start, p_end) rd on true
  left join public.task_occurrences tocc on tocc.task_id = t.id and tocc.occurrence_date = rd.occurrence_date
  where t.id = p_task and t.deleted_at is null and t.recurrence_frequency is not null
  order by rd.occurrence_date;
$$;

revoke execute on function public.get_task_occurrences(uuid, date, date) from public;
grant execute on function public.get_task_occurrences(uuid, date, date) to authenticated;

create or replace function public.complete_commitment_occurrence(p_commitment uuid, p_occurrence_date date)
returns void
language plpgsql volatile security invoker set search_path = ''
as $$
declare
  v_project uuid;
  v_member uuid;
  v_valid boolean;
begin
  select project_id into v_project
  from public.commitments
  where id = p_commitment and deleted_at is null and recurrence_frequency is not null;

  if v_project is null or not app.has_role(v_project, array['organizer','member']::public.member_role[]) then
    raise exception 'orchestr:not_authorised:not authorised for this occurrence' using errcode = '42501';
  end if;

  select exists (
    select 1
    from public.commitments c
    join lateral app.recurrence_dates(
      c.recurrence_frequency, c.recurrence_interval, c.recurrence_start_date,
      c.recurrence_end_date, p_occurrence_date, p_occurrence_date
    ) rd on true
    where c.id = p_commitment and rd.occurrence_date = p_occurrence_date
  ) into v_valid;
  if not v_valid then
    raise exception 'orchestr:invalid_occurrence:date is not part of the active recurrence' using errcode = '22023';
  end if;

  v_member := app.current_member_id(v_project);

  insert into public.commitment_occurrences
    (project_id, commitment_id, occurrence_date, status, completed_at, skipped_at, created_by)
  values (v_project, p_commitment, p_occurrence_date, 'completed', now(), null, v_member)
  on conflict (commitment_id, occurrence_date) do update
    set status = 'completed', completed_at = now(), skipped_at = null;
end;
$$;

create or replace function public.skip_commitment_occurrence(p_commitment uuid, p_occurrence_date date)
returns void
language plpgsql volatile security invoker set search_path = ''
as $$
declare
  v_project uuid;
  v_member uuid;
  v_valid boolean;
begin
  select project_id into v_project
  from public.commitments
  where id = p_commitment and deleted_at is null and recurrence_frequency is not null;

  if v_project is null or not app.has_role(v_project, array['organizer','member']::public.member_role[]) then
    raise exception 'orchestr:not_authorised:not authorised for this occurrence' using errcode = '42501';
  end if;

  select exists (
    select 1
    from public.commitments c
    join lateral app.recurrence_dates(
      c.recurrence_frequency, c.recurrence_interval, c.recurrence_start_date,
      c.recurrence_end_date, p_occurrence_date, p_occurrence_date
    ) rd on true
    where c.id = p_commitment and rd.occurrence_date = p_occurrence_date
  ) into v_valid;
  if not v_valid then
    raise exception 'orchestr:invalid_occurrence:date is not part of the active recurrence' using errcode = '22023';
  end if;

  v_member := app.current_member_id(v_project);

  insert into public.commitment_occurrences
    (project_id, commitment_id, occurrence_date, status, completed_at, skipped_at, created_by)
  values (v_project, p_commitment, p_occurrence_date, 'skipped', null, now(), v_member)
  on conflict (commitment_id, occurrence_date) do update
    set status = 'skipped', completed_at = null, skipped_at = now();
end;
$$;

create or replace function public.stop_commitment_recurrence(p_commitment uuid, p_stop_after date)
returns void
language plpgsql volatile security invoker set search_path = ''
as $$
declare
  v_project uuid;
  v_start date;
begin
  select project_id into v_project
  from public.commitments
  where id = p_commitment and deleted_at is null and recurrence_frequency is not null;

  if v_project is null or not app.has_role(v_project, array['organizer','member']::public.member_role[]) then
    raise exception 'orchestr:not_authorised:not authorised for this recurrence' using errcode = '42501';
  end if;

  select recurrence_start_date into v_start from public.commitments where id = p_commitment;
  if p_stop_after < v_start then
    raise exception 'orchestr:invalid_recurrence_end:stop date cannot precede recurrence start' using errcode = '22023';
  end if;

  update public.commitments
  set recurrence_active = false,
      recurrence_end_date = p_stop_after
  where id = p_commitment;
end;
$$;

revoke execute on function public.complete_commitment_occurrence(uuid, date) from public;
revoke execute on function public.skip_commitment_occurrence(uuid, date) from public;
revoke execute on function public.stop_commitment_recurrence(uuid, date) from public;
grant execute on function public.complete_commitment_occurrence(uuid, date) to authenticated;
grant execute on function public.skip_commitment_occurrence(uuid, date) to authenticated;
grant execute on function public.stop_commitment_recurrence(uuid, date) to authenticated;

create or replace function public.complete_task_occurrence(p_task uuid, p_occurrence_date date)
returns void
language plpgsql volatile security invoker set search_path = ''
as $$
declare
  v_project uuid;
  v_member uuid;
  v_valid boolean;
begin
  select project_id into v_project
  from public.tasks
  where id = p_task and deleted_at is null and recurrence_frequency is not null;

  if v_project is null or not app.has_role(v_project, array['organizer','member']::public.member_role[]) then
    raise exception 'orchestr:not_authorised:not authorised for this occurrence' using errcode = '42501';
  end if;

  select exists (
    select 1
    from public.tasks t
    join lateral app.recurrence_dates(
      t.recurrence_frequency, t.recurrence_interval, t.recurrence_start_date,
      t.recurrence_end_date, p_occurrence_date, p_occurrence_date
    ) rd on true
    where t.id = p_task and rd.occurrence_date = p_occurrence_date
  ) into v_valid;
  if not v_valid then
    raise exception 'orchestr:invalid_occurrence:date is not part of the active recurrence' using errcode = '22023';
  end if;

  v_member := app.current_member_id(v_project);

  insert into public.task_occurrences
    (project_id, task_id, occurrence_date, status, completed_at, skipped_at, created_by)
  values (v_project, p_task, p_occurrence_date, 'completed', now(), null, v_member)
  on conflict (task_id, occurrence_date) do update
    set status = 'completed', completed_at = now(), skipped_at = null;
end;
$$;

create or replace function public.skip_task_occurrence(p_task uuid, p_occurrence_date date)
returns void
language plpgsql volatile security invoker set search_path = ''
as $$
declare
  v_project uuid;
  v_member uuid;
  v_valid boolean;
begin
  select project_id into v_project
  from public.tasks
  where id = p_task and deleted_at is null and recurrence_frequency is not null;

  if v_project is null or not app.has_role(v_project, array['organizer','member']::public.member_role[]) then
    raise exception 'orchestr:not_authorised:not authorised for this occurrence' using errcode = '42501';
  end if;

  select exists (
    select 1
    from public.tasks t
    join lateral app.recurrence_dates(
      t.recurrence_frequency, t.recurrence_interval, t.recurrence_start_date,
      t.recurrence_end_date, p_occurrence_date, p_occurrence_date
    ) rd on true
    where t.id = p_task and rd.occurrence_date = p_occurrence_date
  ) into v_valid;
  if not v_valid then
    raise exception 'orchestr:invalid_occurrence:date is not part of the active recurrence' using errcode = '22023';
  end if;

  v_member := app.current_member_id(v_project);

  insert into public.task_occurrences
    (project_id, task_id, occurrence_date, status, completed_at, skipped_at, created_by)
  values (v_project, p_task, p_occurrence_date, 'skipped', null, now(), v_member)
  on conflict (task_id, occurrence_date) do update
    set status = 'skipped', completed_at = null, skipped_at = now();
end;
$$;

create or replace function public.stop_task_recurrence(p_task uuid, p_stop_after date)
returns void
language plpgsql volatile security invoker set search_path = ''
as $$
declare
  v_project uuid;
  v_start date;
begin
  select project_id into v_project
  from public.tasks
  where id = p_task and deleted_at is null and recurrence_frequency is not null;

  if v_project is null or not app.has_role(v_project, array['organizer','member']::public.member_role[]) then
    raise exception 'orchestr:not_authorised:not authorised for this recurrence' using errcode = '42501';
  end if;

  select recurrence_start_date into v_start from public.tasks where id = p_task;
  if p_stop_after < v_start then
    raise exception 'orchestr:invalid_recurrence_end:stop date cannot precede recurrence start' using errcode = '22023';
  end if;

  update public.tasks
  set recurrence_active = false,
      recurrence_end_date = p_stop_after
  where id = p_task;
end;
$$;

revoke execute on function public.complete_task_occurrence(uuid, date) from public;
revoke execute on function public.skip_task_occurrence(uuid, date) from public;
revoke execute on function public.stop_task_recurrence(uuid, date) from public;
grant execute on function public.complete_task_occurrence(uuid, date) to authenticated;
grant execute on function public.skip_task_occurrence(uuid, date) to authenticated;
grant execute on function public.stop_task_recurrence(uuid, date) to authenticated;

create or replace function app._recurring_health_findings(p_project uuid)
returns table (
  code text, severity text, subject_type text, subject_id uuid, subject_label text,
  params jsonb, message text, resolution text, affects_health boolean, dismissible boolean
)
language sql stable security invoker set search_path = ''
as $$
  select
    'activity_occurrence_overdue',
    'warning',
    'commitment',
    md5(c.id::text || rd.occurrence_date::text)::uuid,
    c.title,
    jsonb_build_object('commitment_id', c.id, 'occurrence_date', rd.occurrence_date, 'activity_type', c.activity_type),
    c.title || ' was due on ' || rd.occurrence_date::text,
    'Complete, skip, or reschedule this occurrence',
    true,
    true
  from public.commitments c
  join public.projects pr on pr.id = c.project_id
  join lateral app.recurrence_dates(
    c.recurrence_frequency,
    c.recurrence_interval,
    c.recurrence_start_date,
    c.recurrence_end_date,
    greatest(c.recurrence_start_date, ((now() at time zone pr.timezone)::date - 365)),
    ((now() at time zone pr.timezone)::date - 1)
  ) rd on true
  left join public.commitment_occurrences co
    on co.commitment_id = c.id and co.occurrence_date = rd.occurrence_date
  where c.project_id = p_project
    and c.deleted_at is null
    and c.status not in ('completed','cancelled')
    and c.recurrence_frequency is not null
    and co.status is null

  union all
  select
    'task_occurrence_overdue',
    'warning',
    'task',
    md5(t.id::text || rd.occurrence_date::text)::uuid,
    t.title,
    jsonb_build_object('task_id', t.id, 'occurrence_date', rd.occurrence_date),
    t.title || ' was due on ' || rd.occurrence_date::text,
    'Complete, skip, or reschedule this occurrence',
    true,
    true
  from public.tasks t
  join public.projects pr on pr.id = t.project_id
  join lateral app.recurrence_dates(
    t.recurrence_frequency,
    t.recurrence_interval,
    t.recurrence_start_date,
    t.recurrence_end_date,
    greatest(t.recurrence_start_date, ((now() at time zone pr.timezone)::date - 365)),
    ((now() at time zone pr.timezone)::date - 1)
  ) rd on true
  left join public.task_occurrences tocc
    on tocc.task_id = t.id and tocc.occurrence_date = rd.occurrence_date
  where t.project_id = p_project
    and t.deleted_at is null
    and t.status not in ('done','cancelled')
    and t.recurrence_frequency is not null
    and tocc.status is null;
$$;

create or replace function public.get_project_health(p_project uuid)
returns table (
  code text, severity text, subject_type text, subject_id uuid, subject_label text,
  params jsonb, message text, resolution text, affects_health boolean,
  dismissible boolean, dismissed boolean, snoozed_until date
)
language plpgsql stable security invoker set search_path = ''
as $$
declare v_today date;
begin
  if not app.is_member(p_project) then
    raise exception 'orchestr:not_a_member:not authorised for this project' using errcode = '42501';
  end if;
  select (now() at time zone timezone)::date into v_today from public.projects where id = p_project;

  return query
  select f.code, f.severity, f.subject_type, f.subject_id, f.subject_label, f.params,
         f.message, f.resolution, f.affects_health, f.dismissible,
         case
           when not f.dismissible then false
           when d.state = 'dismissed' then true
           when d.state = 'snoozed' and d.snoozed_until >= v_today then true
           else false
         end as dismissed,
         d.snoozed_until
  from (
    select *
    from app._health_findings(p_project) f0
    where not (
      f0.code = 'activity_overdue'
      and exists (
        select 1
        from public.commitments c
        where c.id = f0.subject_id and c.recurrence_frequency is not null
      )
    )
    union all
    select * from app._recurring_health_findings(p_project)
  ) f
  left join public.finding_dismissals d
    on d.project_id = p_project
   and d.code = f.code
   and d.subject_type = f.subject_type
   and d.subject_id is not distinct from f.subject_id;
end;
$$;

revoke execute on function app._recurring_health_findings(uuid) from public;
grant execute on function app._recurring_health_findings(uuid) to authenticated, service_role;
revoke execute on function public.get_project_health(uuid) from public;
grant execute on function public.get_project_health(uuid) to authenticated;
