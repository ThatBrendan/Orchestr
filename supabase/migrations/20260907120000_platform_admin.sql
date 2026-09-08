-- ============================================================================
-- 20260907120000_platform_admin
-- Global platform-administration role + read-only admin inspection models.
-- Project roles remain project-scoped; do not add admin to public.member_role.
-- ============================================================================

create type public.platform_role as enum ('user','admin');

alter table public.users
  add column platform_role public.platform_role not null default 'user';

create index users_platform_role_idx on public.users (platform_role);

create or replace function app.is_platform_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and u.platform_role = 'admin'
  );
$$;

revoke execute on function app.is_platform_admin() from public;
grant execute on function app.is_platform_admin() to authenticated, service_role;

create or replace function app.tg_block_client_platform_role_change()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.platform_role is distinct from old.platform_role and auth.uid() is not null then
    raise exception 'orchestr:platform_role_locked:platform role changes must be performed from the administrative database environment'
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

revoke execute on function app.tg_block_client_platform_role_change() from public;

create trigger users_block_client_platform_role_change
  before update of platform_role on public.users
  for each row execute function app.tg_block_client_platform_role_change();

create policy users_select_platform_admin on public.users
  for select to authenticated using (app.is_platform_admin());
create policy projects_select_platform_admin on public.projects
  for select to authenticated using (app.is_platform_admin());
create policy members_select_platform_admin on public.project_members
  for select to authenticated using (app.is_platform_admin());
create policy invitations_select_platform_admin on public.invitations
  for select to authenticated using (app.is_platform_admin());
create policy commitments_select_platform_admin on public.commitments
  for select to authenticated using (app.is_platform_admin());
create policy payments_select_platform_admin on public.payments
  for select to authenticated using (app.is_platform_admin());
create policy budgets_select_platform_admin on public.budgets
  for select to authenticated using (app.is_platform_admin());
create policy findings_select_platform_admin on public.finding_dismissals
  for select to authenticated using (app.is_platform_admin());
create policy audit_select_platform_admin on public.audit_log
  for select to authenticated using (app.is_platform_admin());

create view public.v_admin_users
with (security_invoker = true) as
select
  u.id,
  u.email,
  u.display_name,
  u.avatar_url,
  u.timezone,
  u.default_currency,
  u.platform_role,
  u.created_at,
  u.updated_at,
  count(pm.id) filter (where pm.deleted_at is null)::int as membership_count,
  count(pm.id) filter (where pm.status = 'active' and pm.deleted_at is null)::int as active_membership_count
from public.users u
left join public.project_members pm on pm.user_id = u.id
where app.is_platform_admin()
group by u.id;

create view public.v_admin_user_memberships
with (security_invoker = true) as
select
  pm.id as member_id,
  pm.project_id,
  p.name as project_name,
  p.status as project_status,
  pm.user_id,
  pm.display_name,
  pm.email,
  pm.role,
  pm.status,
  pm.joined_at,
  pm.created_at,
  pm.updated_at,
  pm.deleted_at
from public.project_members pm
join public.projects p on p.id = pm.project_id
where app.is_platform_admin();

create view public.v_admin_projects
with (security_invoker = true) as
select
  p.id,
  p.name,
  p.description,
  p.status,
  p.starts_on,
  p.ends_on,
  p.timezone,
  p.currency,
  p.created_by,
  creator.display_name as created_by_display_name,
  creator.email as created_by_email,
  p.created_at,
  p.updated_at,
  p.archived_at,
  p.deleted_at,
  coalesce(member_counts.member_count, 0)::int as member_count,
  coalesce(member_counts.active_member_count, 0)::int as active_member_count,
  coalesce(commitment_counts.commitment_count, 0)::int as commitment_count,
  coalesce(commitment_counts.total_cost_minor, 0)::bigint as total_cost_minor,
  coalesce(payment_counts.gross_paid_minor, 0)::bigint as gross_paid_minor
from public.projects p
left join public.project_members creator_member on creator_member.id = p.created_by
left join public.users creator on creator.id = creator_member.user_id
left join lateral (
  select
    count(*) filter (where pm.deleted_at is null)::int as member_count,
    count(*) filter (where pm.status = 'active' and pm.deleted_at is null)::int as active_member_count
  from public.project_members pm
  where pm.project_id = p.id
) member_counts on true
left join lateral (
  select
    count(*) filter (where c.deleted_at is null)::int as commitment_count,
    sum(coalesce(c.confirmed_cost_minor, c.estimated_cost_minor, 0)) filter (where c.deleted_at is null and c.status <> 'cancelled')::bigint as total_cost_minor
  from public.commitments c
  where c.project_id = p.id
) commitment_counts on true
left join lateral (
  select
    sum(pay.amount_minor) filter (where pay.status = 'paid' and pay.direction = 'outgoing' and pay.deleted_at is null)::bigint as gross_paid_minor
  from public.payments pay
  where pay.project_id = p.id
) payment_counts on true
where app.is_platform_admin()
;

create view public.v_admin_project_members
with (security_invoker = true) as
select
  pm.id,
  pm.project_id,
  pm.user_id,
  pm.display_name,
  pm.email,
  pm.role,
  pm.status,
  u.platform_role,
  pm.joined_at,
  pm.created_at,
  pm.updated_at,
  pm.deleted_at
from public.project_members pm
left join public.users u on u.id = pm.user_id
where app.is_platform_admin();

create view public.v_admin_invitations
with (security_invoker = true) as
select
  i.id,
  i.project_id,
  p.name as project_name,
  i.email,
  i.role,
  i.status,
  inviter.display_name as inviter_display_name,
  inviter.email as inviter_email,
  i.created_at,
  i.updated_at,
  i.expires_at,
  i.accepted_at
from public.invitations i
join public.projects p on p.id = i.project_id
left join public.project_members invited_by_member on invited_by_member.id = i.invited_by
left join public.users inviter on inviter.id = invited_by_member.user_id
where app.is_platform_admin();

create view public.v_admin_audit_log
with (security_invoker = true) as
select
  a.id,
  a.project_id,
  p.name as project_name,
  a.at,
  a.actor_user_id,
  u.email as actor_email,
  u.display_name as actor_display_name,
  a.actor_member_id,
  a.source,
  a.action,
  a.entity_type,
  a.entity_id,
  a.request_id,
  a.before,
  a.after
from public.audit_log a
left join public.projects p on p.id = a.project_id
left join public.users u on u.id = a.actor_user_id
where app.is_platform_admin();

create or replace function public.get_admin_overview()
returns table (
  total_users int,
  admin_users int,
  total_projects int,
  active_projects int,
  archived_projects int,
  deleted_projects int,
  pending_invitations int,
  active_invitations int
)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not app.is_platform_admin() then
    raise exception 'orchestr:platform_admin_required:platform admin access is required' using errcode = 'P0001';
  end if;

  return query
  select
    (select count(*)::int from public.users),
    (select count(*)::int from public.users where platform_role = 'admin'),
    (select count(*)::int from public.projects),
    (select count(*)::int from public.projects where status = 'active' and deleted_at is null),
    (select count(*)::int from public.projects where status = 'archived' and deleted_at is null),
    (select count(*)::int from public.projects where deleted_at is not null),
    (select count(*)::int from public.invitations where status = 'pending'),
    (select count(*)::int from public.invitations where status in ('pending','accepted'));
end;
$$;

revoke execute on function public.get_admin_overview() from public;
grant execute on function public.get_admin_overview() to authenticated, service_role;

create or replace function public.get_admin_project_health_summary(p_project uuid)
returns table (status text, blocker_count int, warning_count int, info_count int, attention_count int)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_today date;
begin
  if not app.is_platform_admin() then
    raise exception 'orchestr:platform_admin_required:platform admin access is required' using errcode = 'P0001';
  end if;

  select (now() at time zone p.timezone)::date
  into v_today
  from public.projects p
  where p.id = p_project;

  return query
  select
    case
      when count(*) filter (where f.severity = 'blocker' and not coalesce((
        d.state = 'dismissed' or (d.state = 'snoozed' and d.snoozed_until >= v_today)
      ), false)) > 0 then 'needs_attention'
      when count(*) filter (where f.severity = 'warning' and not coalesce((
        d.state = 'dismissed' or (d.state = 'snoozed' and d.snoozed_until >= v_today)
      ), false)) > 0 then 'at_risk'
      else 'healthy'
    end,
    count(*) filter (where f.severity = 'blocker' and not coalesce((
      d.state = 'dismissed' or (d.state = 'snoozed' and d.snoozed_until >= v_today)
    ), false))::int,
    count(*) filter (where f.severity = 'warning' and not coalesce((
      d.state = 'dismissed' or (d.state = 'snoozed' and d.snoozed_until >= v_today)
    ), false))::int,
    count(*) filter (where f.severity = 'info' and not coalesce((
      d.state = 'dismissed' or (d.state = 'snoozed' and d.snoozed_until >= v_today)
    ), false))::int,
    count(*) filter (where f.severity in ('blocker','warning') and not coalesce((
      d.state = 'dismissed' or (d.state = 'snoozed' and d.snoozed_until >= v_today)
    ), false))::int
  from app._health_findings(p_project) f
  left join public.finding_dismissals d
    on d.project_id = p_project
   and d.code = f.code
   and d.subject_type = f.subject_type
   and d.subject_id is not distinct from f.subject_id;
end;
$$;

revoke execute on function public.get_admin_project_health_summary(uuid) from public;
grant execute on function public.get_admin_project_health_summary(uuid) to authenticated, service_role;

grant select on
  public.v_admin_users,
  public.v_admin_user_memberships,
  public.v_admin_projects,
  public.v_admin_project_members,
  public.v_admin_invitations,
  public.v_admin_audit_log
to authenticated;

comment on column public.users.platform_role is
  'Global platform role for Orchestr application administration. Separate from project-scoped public.member_role.';
