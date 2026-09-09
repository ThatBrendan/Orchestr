-- Prevent sparse occurrence state from being stored for dates outside a series.
-- This remains enforced for direct table writes as well as the occurrence RPCs.

create or replace function app.validate_commitment_occurrence()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.commitments c
    join lateral app.recurrence_dates(
      c.recurrence_frequency, c.recurrence_interval, c.recurrence_start_date,
      c.recurrence_end_date, new.occurrence_date, new.occurrence_date
    ) rd on true
    where c.id = new.commitment_id
      and rd.occurrence_date = new.occurrence_date
  ) then
    raise exception 'orchestr:invalid_occurrence:date is not part of the active recurrence'
      using errcode = '22023';
  end if;
  return new;
end;
$$;

create or replace function app.validate_task_occurrence()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.tasks t
    join lateral app.recurrence_dates(
      t.recurrence_frequency, t.recurrence_interval, t.recurrence_start_date,
      t.recurrence_end_date, new.occurrence_date, new.occurrence_date
    ) rd on true
    where t.id = new.task_id
      and rd.occurrence_date = new.occurrence_date
  ) then
    raise exception 'orchestr:invalid_occurrence:date is not part of the active recurrence'
      using errcode = '22023';
  end if;
  return new;
end;
$$;

create trigger commitment_occurrences_validate
  before insert or update of commitment_id, occurrence_date
  on public.commitment_occurrences
  for each row execute function app.validate_commitment_occurrence();

create trigger task_occurrences_validate
  before insert or update of task_id, occurrence_date
  on public.task_occurrences
  for each row execute function app.validate_task_occurrence();

revoke execute on function app.validate_commitment_occurrence() from public;
revoke execute on function app.validate_task_occurrence() from public;
grant execute on function app.validate_commitment_occurrence() to authenticated, service_role;
grant execute on function app.validate_task_occurrence() to authenticated, service_role;