-- ============================================================================
-- Project profiles
-- One shared project domain; profiles configure presentation defaults only.
-- ============================================================================

create type public.project_profile as enum (
  'group_trip',
  'wedding_event',
  'house_move',
  'recurring_process',
  'team_project',
  'launch',
  'blank'
);

alter table public.projects
  add column profile public.project_profile not null default 'blank',
  add column module_visibility jsonb not null default '{}'::jsonb
    check (jsonb_typeof(module_visibility) = 'object');

-- Keep the dashboard/projects read model synchronized with project columns.
create or replace view public.v_my_projects
with (security_invoker = true) as
select
  pr.id as project_id,
  pr.name, pr.status, pr.starts_on, pr.ends_on, pr.timezone, pr.currency,
  me.role as my_role,
  fin.total_cost_minor, fin.committed_spend_minor, fin.net_actual_spend_minor,
  fin.outstanding_minor, fin.remaining_budget_minor, fin.progress_pct,
  h.status as health_status, h.attention_count,
  (select min(occurs_at) from public.v_timeline_events te
    where te.project_id = pr.id and te.occurs_at >= now()) as next_event_at,
  fin.total_target_minor,
  pr.profile,
  pr.module_visibility
from public.projects pr
join public.project_members me
  on me.project_id = pr.id and me.user_id = auth.uid()
 and me.status = 'active' and me.deleted_at is null
left join public.v_project_financials fin on fin.project_id = pr.id
left join lateral public.get_project_health_summary(pr.id) h on true
where pr.deleted_at is null;

grant select on public.v_my_projects to authenticated;

drop function public.create_project(text, text, text, date, date);

create function public.create_project(
  p_name text,
  p_timezone text,
  p_currency text,
  p_starts_on date default null,
  p_ends_on date default null,
  p_profile public.project_profile default 'blank'
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_project uuid;
  v_founders int;
begin
  if v_uid is null then
    raise exception 'orchestr:auth_required:you must be signed in' using errcode = '42501';
  end if;

  if p_name is null or char_length(btrim(p_name)) not between 1 and 120 then
    raise exception 'orchestr:invalid_project_name:project name must be between 1 and 120 characters'
      using errcode = 'P0001';
  end if;

  insert into public.projects (name, timezone, currency, profile, starts_on, ends_on)
  values (btrim(p_name), p_timezone, p_currency, coalesce(p_profile, 'blank'), p_starts_on, p_ends_on)
  returning id into v_project;

  select count(*)
    into v_founders
    from public.project_members
   where project_id = v_project
     and user_id = v_uid
     and role = 'organizer'
     and status = 'active'
     and deleted_at is null;

  if v_founders <> 1 then
    raise exception 'orchestr:project_bootstrap_failed:project founding membership was not created'
      using errcode = 'P0001';
  end if;

  return v_project;
end;
$$;

revoke execute on function public.create_project(text, text, text, date, date, public.project_profile) from public;
grant execute on function public.create_project(text, text, text, date, date, public.project_profile) to authenticated;
