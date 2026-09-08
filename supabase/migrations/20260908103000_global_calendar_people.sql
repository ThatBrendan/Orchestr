-- ============================================================================
-- Global Calendar + People read models
-- Additive, read-only, cross-project views for authenticated users.
-- ============================================================================

-- Global timeline: same event semantics as v_timeline_events, enriched with
-- project context and payment amount for display. Archived projects are excluded
-- from the global calendar per BUSINESS_RULES PRJ-19.
create view public.v_my_timeline_events
with (security_invoker = true) as
select
  te.project_id,
  p.name as project_name,
  p.timezone as project_timezone,
  p.currency,
  te.occurs_at,
  case
    when te.subject_type = 'commitment' then coalesce(c.is_all_day, te.all_day)
    else te.all_day
  end as all_day,
  te.event_type,
  te.title,
  te.subject_type,
  te.subject_id,
  te.status,
  pay.amount_minor
from public.v_timeline_events te
join public.projects p on p.id = te.project_id
left join public.payments pay
  on te.subject_type = 'payment'
 and pay.id = te.subject_id
 and pay.deleted_at is null
left join public.commitments c
  on te.subject_type = 'commitment'
 and c.id = te.subject_id
 and c.deleted_at is null
where p.deleted_at is null
  and p.status <> 'archived';

-- Global people: derived from project_members across projects the caller can
-- access. Real users are grouped by user_id; name-only rows remain distinct by
-- project_members.id. No email/private profile fields are exposed.
create view public.v_my_people
with (security_invoker = false) as
with visible_members as (
  select
    pm.id as member_id,
    pm.project_id,
    pr.name as project_name,
    pm.user_id,
    coalesce(u.display_name, pm.display_name) as display_name,
    u.avatar_url,
    pm.role,
    pm.status
  from public.project_members pm
  join public.projects pr on pr.id = pm.project_id
  left join public.users u on u.id = pm.user_id
  where pm.deleted_at is null
    and pm.status <> 'removed'
    and pr.deleted_at is null
    and app.is_member(pm.project_id)
)
select
  case
    when user_id is not null then 'user:' || user_id::text
    else 'member:' || member_id::text
  end as person_key,
  user_id,
  min(display_name) as display_name,
  min(avatar_url) as avatar_url,
  bool_or(user_id = (select auth.uid())) as is_current_user,
  count(distinct project_id)::int as project_count,
  array_agg(distinct role order by role) as roles,
  jsonb_agg(
    jsonb_build_object(
      'project_id', project_id,
      'project_name', project_name,
      'member_id', member_id,
      'role', role,
      'status', status
    )
    order by project_name, project_id, member_id
  ) as projects
from visible_members
group by
  case
    when user_id is not null then 'user:' || user_id::text
    else 'member:' || member_id::text
  end,
  user_id;

grant select on public.v_my_timeline_events, public.v_my_people to authenticated;
