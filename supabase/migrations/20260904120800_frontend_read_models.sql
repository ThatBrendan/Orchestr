-- ============================================================================
-- 20260904120800_frontend_read_models
-- Additive read-model support for the frontend foundation pass. No behaviour,
-- policy, or formula change — everything below is derived from the existing
-- financial derivation (v_project_financials) and health engine (app._health_findings).
--
--   1. v_my_projects gains `total_target_minor` so the client never re-derives
--      the budget target (was: remaining_budget + total_cost in Vue).
--   2. public.get_my_attention() — one set-based call for the dashboard
--      "Needs attention" list across all of the caller's projects, replacing
--      an N+1 (get_project_health once per project) on the client.
--
-- Source of truth: docs/BUSINESS_RULES.md §8-9 ; docs/TECHNICAL_ARCHITECTURE.md §7-8
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. v_my_projects + total_target_minor  (appended column — create or replace OK)
-- ---------------------------------------------------------------------------
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
  fin.total_target_minor
from public.projects pr
join public.project_members me
  on me.project_id = pr.id and me.user_id = auth.uid()
 and me.status = 'active' and me.deleted_at is null
left join public.v_project_financials fin on fin.project_id = pr.id
left join lateral public.get_project_health_summary(pr.id) h on true
where pr.deleted_at is null;

grant select on public.v_my_projects to authenticated;

-- ---------------------------------------------------------------------------
-- 2. get_my_attention()  — dashboard "Needs attention", all projects, one call.
-- SECURITY INVOKER: RLS on projects/project_members constrains which projects
-- are visited; app._health_findings is itself SECURITY INVOKER + RLS-safe.
-- Mirrors public.get_project_health's dismissal logic exactly (HLT-E / HLT-F).
-- ---------------------------------------------------------------------------
create or replace function public.get_my_attention()
returns table (
  project_id uuid,
  project_name text,
  code text,
  severity text,
  subject_type text,
  subject_id uuid,
  subject_label text,
  params jsonb,
  message text,
  resolution text
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    p.id            as project_id,
    p.name          as project_name,
    f.code, f.severity, f.subject_type, f.subject_id, f.subject_label,
    f.params, f.message, f.resolution
  from public.projects p
  join public.project_members m
    on m.project_id = p.id
   and m.user_id = auth.uid()
   and m.status = 'active'
   and m.deleted_at is null
  cross join lateral app._health_findings(p.id) f
  left join public.finding_dismissals d
    on d.project_id = p.id
   and d.code = f.code
   and d.subject_type = f.subject_type
   and d.subject_id is not distinct from f.subject_id
  where p.deleted_at is null
    and f.severity in ('blocker', 'warning')
    and case
          when not f.dismissible then false
          when d.state = 'dismissed' then true
          when d.state = 'snoozed'
            and d.snoozed_until >= (now() at time zone p.timezone)::date then true
          else false
        end = false
  order by
    case f.severity when 'blocker' then 0 else 1 end,
    p.name,
    f.subject_label;
$$;

revoke execute on function public.get_my_attention() from public;
grant execute on function public.get_my_attention() to authenticated;
