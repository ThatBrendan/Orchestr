-- Remove optional booking-reference metadata from actionable Health output.
-- Keep the existing engine intact and filter this non-actionable rule at the
-- authoritative app layer used by project and dashboard summaries.
alter function app._health_findings(uuid) rename to _health_findings_with_optional_metadata;

create function app._health_findings(p_project uuid)
returns table (
  code text, severity text, subject_type text, subject_id uuid, subject_label text,
  params jsonb, message text, resolution text, affects_health boolean, dismissible boolean
)
language sql stable security invoker set search_path = ''
as $$
  select *
  from app._health_findings_with_optional_metadata(p_project)
  where code <> 'missing_booking_reference';
$$;
revoke all on function app._health_findings(uuid) from public;
grant execute on function app._health_findings(uuid) to authenticated, service_role;

create or replace view public.v_member_directory
with (security_invoker = false) as
select
  pm.project_id,
  pm.id as member_id,
  coalesce(u.display_name, pm.display_name) as display_name,
  u.avatar_url,
  pm.role,
  pm.status
from public.project_members pm
left join public.users u on u.id = pm.user_id
where pm.deleted_at is null
  and app.is_member(pm.project_id);

create or replace view public.v_my_people
with (security_invoker = false) as
with visible_members as (
  select pm.id as member_id, pm.project_id, pr.name as project_name, pm.user_id,
         coalesce(u.display_name, pm.display_name) as display_name, u.avatar_url,
         pm.role, pm.status
  from public.project_members pm
  join public.projects pr on pr.id = pm.project_id
  left join public.users u on u.id = pm.user_id
  where pm.deleted_at is null and pm.status <> 'removed'
    and pr.deleted_at is null and app.is_member(pm.project_id)
)
select case when user_id is not null then 'user:' || user_id::text else 'member:' || member_id::text end as person_key,
       user_id, min(display_name) as display_name, min(avatar_url) as avatar_url,
       bool_or(user_id = (select auth.uid())) as is_current_user,
       count(distinct project_id)::int as project_count,
       array_agg(distinct role order by role) as roles,
       jsonb_agg(jsonb_build_object('project_id', project_id, 'project_name', project_name,
         'member_id', member_id, 'role', role, 'status', status)
         order by project_name, project_id, member_id) as projects
from visible_members
group by case when user_id is not null then 'user:' || user_id::text else 'member:' || member_id::text end, user_id;

create or replace view public.v_activity_member_settlements
with (security_invoker=true) as
with pairs as (
  select project_id,commitment_id,member_id from public.v_activity_cost_shares
  union
  select project_id,commitment_id,paid_by_member_id from public.payments where deleted_at is null and paid_by_member_id is not null
)
select k.project_id,k.commitment_id,k.member_id,coalesce(u.display_name,m.display_name) as display_name,
 m.status as member_status,coalesce(s.amount_minor,0)::bigint as allocated_minor,
 coalesce(p.paid,0)::bigint as paid_minor,(coalesce(s.amount_minor,0)-coalesce(p.paid,0))::bigint as remaining_minor
from pairs k join public.commitments c on c.id=k.commitment_id and c.deleted_at is null
join public.project_members m on m.id=k.member_id and m.project_id=k.project_id
left join public.users u on u.id=m.user_id
left join public.v_activity_cost_shares s on s.commitment_id=k.commitment_id and s.member_id=k.member_id
left join lateral (
  select sum(case when direction='outgoing' then amount_minor else -amount_minor end) as paid
  from public.payments where commitment_id=k.commitment_id and paid_by_member_id=k.member_id and status='paid' and deleted_at is null
) p on true;

create or replace view public.v_project_member_settlements
with (security_invoker=true) as
select s.project_id,s.member_id,s.display_name,s.member_status,p.currency,
 sum(case when c.status='cancelled' then 0 else s.allocated_minor end)::bigint as allocated_minor,
 sum(s.paid_minor)::bigint as paid_minor,
 sum(case when c.status='cancelled' then 0 else s.allocated_minor end-s.paid_minor)::bigint as remaining_minor
from public.v_activity_member_settlements s join public.commitments c on c.id=s.commitment_id
join public.projects p on p.id=s.project_id where c.deleted_at is null and p.deleted_at is null
group by s.project_id,s.member_id,s.display_name,s.member_status,p.currency;
