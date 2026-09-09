-- ============================================================================
-- Dynamic overview + profile-aware health
-- One configurable overview read model and deterministic health applicability.
-- ============================================================================

create view public.v_project_overview
with (security_invoker = true) as
select
  pr.id as project_id,
  pr.profile,
  pr.starts_on,
  pr.ends_on,
  ((pr.starts_on - ((now() at time zone pr.timezone)::date)))::int as days_until_start,
  ((pr.ends_on - ((now() at time zone pr.timezone)::date)))::int as days_until_end,
  coalesce(c.activity_count, 0)::int as activity_count,
  coalesce(c.open_activity_count, 0)::int as open_activity_count,
  coalesce(c.completed_activity_count, 0)::int as completed_activity_count,
  coalesce(c.booking_count, 0)::int as booking_count,
  coalesce(c.booked_booking_count, 0)::int as booked_booking_count,
  coalesce(c.task_count, 0)::int as task_count,
  coalesce(c.purchase_count, 0)::int as purchase_count,
  coalesce(c.event_count, 0)::int as event_count,
  coalesce(c.overdue_activity_count, 0)::int as overdue_activity_count,
  coalesce(c.unowned_activity_count, 0)::int as unowned_activity_count,
  coalesce(c.supplier_count, 0)::int as supplier_count,
  coalesce(m.active_member_count, 0)::int as active_member_count,
  coalesce(ms.milestone_count, 0)::int as milestone_count,
  coalesce(ms.upcoming_milestone_count, 0)::int as upcoming_milestone_count,
  ms.next_milestone_on,
  coalesce(p.payment_overdue_count, 0)::int as payment_overdue_count,
  coalesce(p.payment_due_soon_count, 0)::int as payment_due_soon_count,
  fin.total_cost_minor,
  fin.committed_spend_minor,
  fin.net_actual_spend_minor,
  fin.outstanding_minor,
  fin.total_target_minor,
  fin.remaining_budget_minor,
  fin.progress_pct,
  h.status as health_status,
  h.attention_count
from public.projects pr
left join public.v_project_financials fin on fin.project_id = pr.id
left join lateral public.get_project_health_summary(pr.id) h on true
left join lateral (
  select
    count(*) filter (where c.status <> 'cancelled') as activity_count,
    count(*) filter (where c.status not in ('cancelled','completed')) as open_activity_count,
    count(*) filter (where c.status = 'completed') as completed_activity_count,
    count(*) filter (where c.activity_type = 'booking' and c.status <> 'cancelled') as booking_count,
    count(*) filter (where c.activity_type = 'booking' and c.status in ('booked','completed')) as booked_booking_count,
    count(*) filter (where c.activity_type = 'task' and c.status <> 'cancelled') as task_count,
    count(*) filter (where c.activity_type = 'purchase' and c.status <> 'cancelled') as purchase_count,
    count(*) filter (where c.activity_type = 'event' and c.status <> 'cancelled') as event_count,
    count(*) filter (
      where c.status not in ('cancelled','completed')
        and c.starts_at is not null
        and (c.starts_at at time zone pr.timezone)::date < ((now() at time zone pr.timezone)::date)
    ) as overdue_activity_count,
    count(*) filter (
      where c.status in ('researching','confirmed','booked')
        and c.owner_member_id is null
    ) as unowned_activity_count,
    count(distinct c.supplier_name) filter (where c.supplier_name is not null and btrim(c.supplier_name) <> '') as supplier_count
  from public.commitments c
  where c.project_id = pr.id and c.deleted_at is null
) c on true
left join lateral (
  select count(*) filter (where pm.status = 'active' and pm.deleted_at is null) as active_member_count
  from public.project_members pm
  where pm.project_id = pr.id
) m on true
left join lateral (
  select
    count(*) as milestone_count,
    count(*) filter (where ms.on_date >= ((now() at time zone pr.timezone)::date)) as upcoming_milestone_count,
    min(ms.on_date) filter (where ms.on_date >= ((now() at time zone pr.timezone)::date)) as next_milestone_on
  from public.milestones ms
  where ms.project_id = pr.id
) ms on true
left join lateral (
  select
    count(*) filter (where pay.status = 'scheduled' and pay.due_on < ((now() at time zone pr.timezone)::date)) as payment_overdue_count,
    count(*) filter (
      where pay.status = 'scheduled'
        and pay.due_on between ((now() at time zone pr.timezone)::date)
                           and ((now() at time zone pr.timezone)::date) + 7
    ) as payment_due_soon_count
  from public.payments pay
  where pay.project_id = pr.id and pay.deleted_at is null
) p on true
where pr.deleted_at is null;

grant select on public.v_project_overview to authenticated;

create or replace function app._health_findings(p_project uuid)
returns table (
  code text, severity text, subject_type text, subject_id uuid, subject_label text,
  params jsonb, message text, resolution text, affects_health boolean, dismissible boolean
)
language plpgsql stable security invoker set search_path = ''
as $$
declare
  v_tz  text;
  cfg   jsonb;
  v_now timestamptz := now();
  v_today date;
  v_ccy text;
  v_profile public.project_profile;
  v_budget_visible boolean;
  inactive_days int; due_soon_days int; tight_min int; near_days int; on_budget_window int;
begin
  select
    timezone,
    health_config,
    currency,
    profile,
    case
      when jsonb_typeof(module_visibility->'budget') = 'boolean' then (module_visibility->>'budget')::boolean
      else profile in ('group_trip','wedding_event','launch','blank')
    end
  into v_tz, cfg, v_ccy, v_profile, v_budget_visible
  from public.projects
  where id = p_project and deleted_at is null;

  if v_tz is null then return; end if;
  v_today := (v_now at time zone v_tz)::date;
  inactive_days    := coalesce((cfg->>'inactive_days')::int, 7);
  due_soon_days    := coalesce((cfg->>'due_soon_days')::int, 7);
  tight_min        := coalesce((cfg->>'tight_connection_minutes')::int, 20);
  near_days        := coalesce((cfg->>'unconfirmed_near_days')::int, 14);
  on_budget_window := coalesce((cfg->>'on_budget_window_days')::int, 30);

  return query
  -- HLT-1 missing_owner: globally relevant to in-progress/committed activity ownership.
  select 'missing_owner','warning','commitment',c.id,c.title,
         jsonb_build_object('status',c.status,'activity_type',c.activity_type),
         c.title || ' has no owner','Assign an owner',true,true
  from public.commitments c
  where c.project_id = p_project and c.deleted_at is null
    and c.status in ('researching','confirmed','booked') and c.owner_member_id is null

  union all
  -- HLT-2 orphaned_owner: globally relevant.
  select 'orphaned_owner','warning','commitment',c.id,c.title,
         jsonb_build_object('owner',m.display_name,'activity_type',c.activity_type),
         c.title || '''s owner (' || m.display_name || ') has left the project',
         'Assign a new owner',true,true
  from public.commitments c
  join public.project_members m on m.id = c.owner_member_id
  where c.project_id = p_project and c.deleted_at is null and c.status <> 'cancelled'
    and m.status = 'removed'

  union all
  -- HLT-3 payment_overdue: globally relevant when payment rows exist; blocker/non-dismissible.
  select 'payment_overdue','blocker','payment',pay.id,c.title,
         jsonb_build_object('amount_minor',pay.amount_minor,'currency',v_ccy,'due_on',pay.due_on),
         app.format_money(pay.amount_minor,v_ccy) || ' for ' || c.title || ' was due on ' || pay.due_on::text,
         'Record it as paid, or reschedule / cancel it',true,false
  from public.payments pay
  join public.commitments c on c.id = pay.commitment_id and c.deleted_at is null
  where pay.project_id = p_project and pay.deleted_at is null
    and c.status <> 'cancelled' and pay.status = 'scheduled'
    and pay.due_on is not null and pay.due_on < v_today

  union all
  -- HLT-4 payment_due_soon: globally relevant when payment rows exist.
  select 'payment_due_soon','warning','payment',pay.id,c.title,
         jsonb_build_object('amount_minor',pay.amount_minor,'currency',v_ccy,'due_on',pay.due_on),
         app.format_money(pay.amount_minor,v_ccy) || ' for ' || c.title || ' is due ' || pay.due_on::text,
         'Pay it, or snooze if on track',true,true
  from public.payments pay
  join public.commitments c on c.id = pay.commitment_id and c.deleted_at is null
  where pay.project_id = p_project and pay.deleted_at is null
    and c.status <> 'cancelled' and pay.status = 'scheduled'
    and pay.due_on is not null and pay.due_on between v_today and v_today + due_soon_days

  union all
  -- HLT-5 missing_booking_reference: booking activities only.
  select 'missing_booking_reference','warning','commitment',c.id,c.title,
         jsonb_build_object('status',c.status,'activity_type',c.activity_type),
         c.title || ' is ' || c.status || ' but has no confirmed booking reference',
         'Add the reference and mark the booking confirmed',true,true
  from public.commitments c
  where c.project_id = p_project and c.deleted_at is null
    and c.activity_type = 'booking'
    and c.status in ('confirmed','booked','completed')
    and (c.booking_reference is null or c.booking_confirmed = false)

  union all
  -- HLT-6 unconfirmed_near_date: globally relevant date readiness signal.
  select 'unconfirmed_near_date','warning','commitment',c.id,c.title,
         jsonb_build_object('status',c.status,'starts_at',c.starts_at,'activity_type',c.activity_type),
         c.title || ' is still ' || c.status || ' but happens soon',
         'Confirm it, complete it, or cancel it',true,true
  from public.commitments c
  where c.project_id = p_project and c.deleted_at is null
    and c.status in ('idea','researching') and c.starts_at is not null
    and c.starts_at <= v_now + (near_days || ' days')::interval

  union all
  -- HLT-7 commitment_inactive: globally relevant for stale planning/execution.
  select 'commitment_inactive','warning','commitment',c.id,c.title,
         jsonb_build_object('updated_at',c.updated_at,'days',inactive_days,'activity_type',c.activity_type),
         c.title || ' hasn''t been updated in ' || inactive_days || ' days',
         'Update it, advance its status, or cancel it',true,true
  from public.commitments c
  where c.project_id = p_project and c.deleted_at is null
    and c.status in ('idea','researching')
    and c.updated_at < v_now - (inactive_days || ' days')::interval

  union all
  -- HLT-8 missing_cost: financially relevant activity types only.
  select 'missing_cost','warning','commitment',c.id,c.title,
         jsonb_build_object('status',c.status,'activity_type',c.activity_type),
         c.title || ' is ' || c.status || ' but has no cost recorded',
         'Add the cost, or note that it''s free',true,true
  from public.commitments c
  where c.project_id = p_project and c.deleted_at is null
    and c.activity_type in ('booking','purchase')
    and c.status in ('confirmed','booked','completed')
    and coalesce(c.confirmed_cost_minor, c.estimated_cost_minor, 0) = 0

  union all
  -- HLT-9 budget_exceeded: only relevant when the Budget module is visible.
  select 'budget_exceeded','warning','project',p_project,pr.name,
         jsonb_build_object('total_cost_minor',f.total_cost_minor,'target_minor',f.total_target_minor,'currency',v_ccy,'profile',v_profile),
         'Projected spend (' || app.format_money(f.total_cost_minor,v_ccy) || ') is over the '
           || app.format_money(f.total_target_minor,v_ccy) || ' budget',
         'Raise the budget, reduce costs, or cancel activities',true,true
  from public.v_project_financials f
  join public.projects pr on pr.id = f.project_id
  where v_budget_visible
    and f.project_id = p_project and f.total_target_minor is not null
    and f.total_cost_minor > f.total_target_minor

  union all
  -- HLT-10 category_over_target: only relevant when the Budget module is visible.
  select 'category_over_target','info','budget_category',
         md5(p_project::text || a.kind::text)::uuid, a.kind::text,
         jsonb_build_object('kind',a.kind,'actual_minor',a.actual_minor,'target_minor',a.target_minor,'currency',v_ccy,'profile',v_profile),
         a.kind || ' spend (' || app.format_money(a.actual_minor,v_ccy) || ') is over its '
           || app.format_money(a.target_minor,v_ccy) || ' target',
         'Adjust the target or the activities',false,true
  from public.v_budget_category_actuals a
  where v_budget_visible
    and a.project_id = p_project and a.target_minor is not null and a.actual_minor > a.target_minor

  union all
  -- HLT-11 schedule_conflict: globally relevant when activities have explicit time ranges.
  select 'schedule_conflict','warning','commitment_pair',
         md5(least(c1.id::text,c2.id::text) || greatest(c1.id::text,c2.id::text))::uuid,
         c1.title || ' / ' || c2.title,
         jsonb_build_object('a',c1.id,'b',c2.id),
         c1.title || ' overlaps ' || c2.title,
         'Adjust the times, or snooze if intentional',true,true
  from public.commitments c1
  join public.commitments c2
    on c2.project_id = c1.project_id and c1.id < c2.id
   and c1.deleted_at is null and c2.deleted_at is null
   and c1.status <> 'cancelled' and c2.status <> 'cancelled'
   and c1.starts_at is not null and c1.ends_at is not null
   and c2.starts_at is not null and c2.ends_at is not null
   and tstzrange(c1.starts_at,c1.ends_at) && tstzrange(c2.starts_at,c2.ends_at)
  where c1.project_id = p_project

  union all
  -- HLT-12 tight_connection: event/booking sequencing for event-like profiles only.
  select 'tight_connection','info','commitment_pair',
         md5(least(c1.id::text,c2.id::text) || greatest(c1.id::text,c2.id::text))::uuid,
         c1.title || ' -> ' || c2.title,
         jsonb_build_object('gap_minutes', extract(epoch from (c2.starts_at - c1.ends_at))/60,'profile',v_profile),
         'Only ' || round(extract(epoch from (c2.starts_at - c1.ends_at))/60)::text
           || ' min between ' || c1.title || ' and ' || c2.title,
         'Adjust times or acknowledge',false,true
  from public.commitments c1
  join public.commitments c2
    on c2.project_id = c1.project_id and c1.id <> c2.id
   and c1.deleted_at is null and c2.deleted_at is null
   and c1.status <> 'cancelled' and c2.status <> 'cancelled'
   and c1.activity_type in ('booking','event')
   and c2.activity_type in ('booking','event')
   and c1.ends_at is not null and c2.starts_at is not null
   and c2.starts_at >= c1.ends_at
   and c2.starts_at - c1.ends_at < (tight_min || ' minutes')::interval
   and (c1.starts_at at time zone v_tz)::date = (c2.starts_at at time zone v_tz)::date
  where c1.project_id = p_project
    and v_profile in ('group_trip','wedding_event','launch')

  union all
  -- HLT-13 task_overdue: globally relevant task-table signal.
  select 'task_overdue','warning','task',t.id,t.title,
         jsonb_build_object('due_on',t.due_on),
         'Task ''' || t.title || ''' was due ' || t.due_on::text,
         'Complete it, reschedule it, or cancel it',true,true
  from public.tasks t
  where t.project_id = p_project and t.deleted_at is null
    and t.status in ('open','in_progress') and t.due_on is not null and t.due_on < v_today

  union all
  -- HLT-14 task_unassigned_due_soon: globally relevant task-table signal.
  select 'task_unassigned_due_soon','info','task',t.id,t.title,
         jsonb_build_object('due_on',t.due_on),
         'Task ''' || t.title || ''' is due soon with no assignee','Assign it',false,true
  from public.tasks t
  where t.project_id = p_project and t.deleted_at is null
    and t.status in ('open','in_progress') and t.assignee_member_id is null
    and t.due_on is not null and t.due_on <= v_today + 7

  union all
  -- HLT-15 outside_project_dates: globally relevant when project boundaries exist.
  select 'outside_project_dates','info','commitment',c.id,c.title,
         jsonb_build_object('starts_at',c.starts_at,'activity_type',c.activity_type),
         c.title || ' is scheduled outside the project dates',
         'Adjust the activity or project dates',false,true
  from public.commitments c
  join public.projects pr on pr.id = c.project_id
  where c.project_id = p_project and c.deleted_at is null and c.status <> 'cancelled'
    and c.starts_at is not null and pr.starts_on is not null and pr.ends_on is not null
    and ( (c.starts_at at time zone v_tz)::date < pr.starts_on
       or (c.starts_at at time zone v_tz)::date > pr.ends_on )

  union all
  -- HLT-16 unallocated_cost: shared-cost signal only when Budget is visible.
  select 'unallocated_cost','info','commitment',c.id,c.title,
         jsonb_build_object('activity_type',c.activity_type,'profile',v_profile),
         c.title || '''s cost isn''t split between anyone',
         'Add participants or set a cost split',false,true
  from public.commitments c
  where v_budget_visible
    and c.project_id = p_project and c.deleted_at is null and c.status <> 'cancelled'
    and coalesce(c.confirmed_cost_minor,c.estimated_cost_minor,0) > 0
    and not exists (select 1 from public.commitment_participants p where p.commitment_id = c.id)
    and not exists (select 1 from public.cost_shares s where s.commitment_id = c.id)

  union all
  -- HLT-17 on_budget: only relevant when the Budget module is visible.
  select 'on_budget','ok','project',p_project,pr.name,
         jsonb_build_object('variance_minor', f.total_target_minor - f.total_cost_minor,'currency',v_ccy,'profile',v_profile),
         'Projected spend is ' || app.format_money(f.total_target_minor - f.total_cost_minor, v_ccy)
           || ' under budget - on track','',false,true
  from public.v_project_financials f
  join public.projects pr on pr.id = f.project_id
  where v_budget_visible
    and f.project_id = p_project and f.total_target_minor is not null
    and f.total_cost_minor <= f.total_target_minor
    and ( f.progress_pct >= 50
       or (pr.ends_on is not null and pr.ends_on <= v_today + on_budget_window) )

  union all
  -- HLT-18 activity_overdue: profile/activity-aware execution signal for dated activities.
  select 'activity_overdue','warning','commitment',c.id,c.title,
         jsonb_build_object('starts_at',c.starts_at,'activity_type',c.activity_type,'profile',v_profile),
         c.title || ' is overdue',
         'Complete it, reschedule it, or cancel it',true,true
  from public.commitments c
  where c.project_id = p_project and c.deleted_at is null
    and c.status not in ('completed','cancelled')
    and c.starts_at is not null
    and (c.starts_at at time zone v_tz)::date < v_today
    and (
      v_profile in ('recurring_process','team_project','house_move','launch')
      or c.activity_type in ('task','purchase','event')
    );
end;
$$;

comment on function app._health_findings(uuid) is
  'Deterministic planning health with Project Profile and Activity Type applicability gates. HLT-18 covers overdue dated activities; recurrence-specific occurrences are deferred until a recurrence model exists.';
