-- NULL status represents a note-only occurrence; date still determines upcoming/overdue.
alter table public.commitment_occurrences
  add column note text check(note is null or char_length(note)<=10000),
  add column skip_reason text check(skip_reason is null or (char_length(skip_reason) between 1 and 500 and skip_reason !~ '^[[:space:]]*$')),
  alter column status drop not null,
  drop constraint chk_commitment_occurrence_state,
  add constraint chk_commitment_occurrence_state check (
    (status is null and completed_at is null and skipped_at is null)
    or (status is not null and status='completed' and completed_at is not null and skipped_at is null)
    or (status is not null and status='skipped' and skipped_at is not null and completed_at is null)
  );

-- Existing skipped rows have unknown reasons. Require a reason on new skips,
-- while allowing a note edit on an unchanged legacy skipped row.
create function app.require_occurrence_skip_reason() returns trigger
language plpgsql set search_path='' as $$
begin
  if new.status='skipped' and new.skip_reason is null then
    if tg_op='INSERT' then
      raise exception 'orchestr:skip_reason_required:Enter a reason for skipping.' using errcode='23514';
    elsif old.status is distinct from new.status or old.skip_reason is distinct from new.skip_reason then
      raise exception 'orchestr:skip_reason_required:Enter a reason for skipping.' using errcode='23514';
    end if;
  end if;
  return new;
end $$;
revoke all on function app.require_occurrence_skip_reason() from public;
create trigger require_skip_reason before insert or update on public.commitment_occurrences
for each row execute function app.require_occurrence_skip_reason();

drop function public.get_commitment_occurrences(uuid,date,date);
create or replace function public.get_commitment_occurrences(p_commitment uuid, p_start date, p_end date)
returns table (
  project_id uuid,
  commitment_id uuid,
  occurrence_date date,
  status text,
  completed_at timestamptz,
  skipped_at timestamptz,
  note text,
  skip_reason text
)
language sql stable security invoker set search_path = ''
as $$
  select c.project_id, c.id, rd.occurrence_date,
         coalesce(co.status::text, case when rd.occurrence_date < ((now() at time zone pr.timezone)::date) then 'overdue' else 'upcoming' end),
         co.completed_at,
         co.skipped_at, co.note, co.skip_reason
  from public.commitments c
  join public.projects pr on pr.id = c.project_id
  join lateral app.recurrence_dates(c.recurrence_frequency, c.recurrence_interval, c.recurrence_start_date, c.recurrence_end_date, p_start, p_end) rd on true
  left join public.commitment_occurrences co on co.commitment_id = c.id and co.occurrence_date = rd.occurrence_date
  where c.id = p_commitment and c.deleted_at is null and c.recurrence_frequency is not null
  order by rd.occurrence_date;
$$;

revoke execute on function public.get_commitment_occurrences(uuid, date, date) from public;
grant execute on function public.get_commitment_occurrences(uuid, date, date) to authenticated;

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
    set status = 'completed', completed_at = now(), skipped_at = null, skip_reason=null;
end;
$$;

drop function public.skip_commitment_occurrence(uuid,date);
create or replace function public.skip_commitment_occurrence(p_commitment uuid, p_occurrence_date date, p_reason text)
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

  p_reason := nullif(regexp_replace(p_reason,'^[[:space:]]+|[[:space:]]+$','','g'),'');
  if p_reason is null or char_length(p_reason)>500 then
    raise exception 'orchestr:skip_reason_required:Enter a reason of 1 to 500 characters.' using errcode='23514'; end if;
  v_member := app.current_member_id(v_project);

  insert into public.commitment_occurrences
    (project_id, commitment_id, occurrence_date, status, completed_at, skipped_at, created_by, skip_reason)
  values (v_project, p_commitment, p_occurrence_date, 'skipped', null, now(), v_member, p_reason)
  on conflict (commitment_id, occurrence_date) do update
    set status = 'skipped', completed_at = null, skipped_at = now(), skip_reason=p_reason;
end;
$$;

create or replace function public.save_commitment_occurrence_note(p_commitment uuid, p_occurrence_date date, p_note text)
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

  p_note := nullif(regexp_replace(p_note,'^[[:space:]]+|[[:space:]]+$','','g'),'');
  if p_note is null then
    update public.commitment_occurrences set note=null where commitment_id=p_commitment and occurrence_date=p_occurrence_date;
  else
    insert into public.commitment_occurrences(project_id,commitment_id,occurrence_date,status,note,created_by)
    values(v_project,p_commitment,p_occurrence_date,null,p_note,v_member)
    on conflict(commitment_id,occurrence_date) do update set note=excluded.note;
  end if;
end $$;
revoke all on function public.save_commitment_occurrence_note(uuid,date,text), public.skip_commitment_occurrence(uuid,date,text) from public;
grant execute on function public.save_commitment_occurrence_note(uuid,date,text), public.skip_commitment_occurrence(uuid,date,text) to authenticated;

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

