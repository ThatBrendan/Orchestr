-- Personal read models must use project membership, not the caller's full RLS
-- visibility. Platform admins intentionally have broader table SELECT policies.

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
  where app.is_member(p.id)
    and p.deleted_at is null
    and p.status <> 'archived';
$$;

-- Keep the existing recurring occurrence columns and delegate personal scope
-- to the explicitly membership-scoped function above.
create or replace view public.v_my_timeline_events
with (security_invoker = true) as
select *
from public.get_my_timeline_events(now() - interval '1 year', now() + interval '2 years');

grant select on public.v_my_timeline_events to authenticated;
revoke execute on function public.get_my_timeline_events(timestamptz, timestamptz) from public;
grant execute on function public.get_my_timeline_events(timestamptz, timestamptz) to authenticated;