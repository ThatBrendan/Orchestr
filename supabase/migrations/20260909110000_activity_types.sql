-- ============================================================================
-- Activity types
-- Activity Type is separate from commitment kind/category and controls UI workflow.
-- Existing commitments default conservatively to "other".
-- ============================================================================

create type public.activity_type as enum (
  'task',
  'booking',
  'purchase',
  'event',
  'other'
);

alter table public.commitments
  add column activity_type public.activity_type not null default 'other';

create index commitments_activity_type_idx
  on public.commitments (project_id, activity_type)
  where deleted_at is null;

create or replace function app.tg_commitment_status_transition()
returns trigger language plpgsql as $$
declare
  v_type public.activity_type := coalesce(new.activity_type, old.activity_type, 'other'::public.activity_type);
begin
  if new.status = old.status then
    return new;
  end if;

  if v_type = 'booking' then
    if not (
         (old.status = 'idea'       and new.status in ('researching','cancelled'))
      or (old.status = 'researching' and new.status in ('idea','confirmed','cancelled'))
      or (old.status = 'confirmed'  and new.status in ('researching','booked','cancelled'))
      or (old.status = 'booked'     and new.status in ('confirmed','completed','cancelled'))
      or (old.status = 'completed'  and new.status in ('booked'))
      or (old.status = 'cancelled'  and new.status in ('researching'))
    ) then
      raise exception 'orchestr:bad_status_transition:commitment % -> %', old.status, new.status using errcode = 'P0001';
    end if;
  else
    if not (
         (old.status = 'idea'       and new.status in ('researching','completed','cancelled'))
      or (old.status = 'researching' and new.status in ('idea','confirmed','completed','cancelled'))
      or (old.status = 'confirmed'  and new.status in ('researching','completed','cancelled'))
      or (old.status = 'booked'     and new.status in ('confirmed','completed','cancelled'))
      or (old.status = 'completed'  and new.status in ('researching'))
      or (old.status = 'cancelled'  and new.status in ('researching'))
    ) then
      raise exception 'orchestr:bad_status_transition:commitment % -> %', old.status, new.status using errcode = 'P0001';
    end if;
  end if;

  return new;
end;
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
  from app._health_findings(p_project) f
  left join public.finding_dismissals d
    on d.project_id = p_project
   and d.code = f.code
   and d.subject_type = f.subject_type
   and d.subject_id is not distinct from f.subject_id
  where not (
    f.code = 'missing_booking_reference'
    and exists (
      select 1
      from public.commitments c
      where c.id = f.subject_id
        and c.activity_type <> 'booking'
    )
  );
end;
$$;

comment on function public.get_project_health(uuid) is
  'Phase 2 suppresses booking-reference health findings for non-booking activities. Other commitment health rules still use the original MVP semantics and should be revisited in the profile-aware Health phase.';
