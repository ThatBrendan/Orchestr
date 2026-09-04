-- ============================================================================
-- 20260904120500_functions_rpcs
-- The health engine (docs/BUSINESS_RULES.md §9), client RPCs (docs/SECURITY_RLS.md §6),
-- and v_my_projects (depends on the health summary).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Money formatting helper (message strings only)
-- ---------------------------------------------------------------------------
create or replace function app.format_money(p_minor bigint, p_currency text)
returns text language sql stable set search_path = '' as $$
  select coalesce(c.symbol, c.code || ' ') ||
         trim(to_char(
           p_minor::numeric / power(10, c.minor_unit)::numeric,
           'FM999999999990' || case when c.minor_unit > 0 then '.' || repeat('0', c.minor_unit) else '' end
         ))
  from public.currencies c where c.code = p_currency;
$$;

-- ---------------------------------------------------------------------------
-- app._health_findings(project)  - deterministic rule engine, SECURITY INVOKER.
-- Thresholds from projects.health_config with documented defaults (HLT-I / D-6).
-- ---------------------------------------------------------------------------
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
  inactive_days int; due_soon_days int; tight_min int; near_days int; on_budget_window int;
begin
  select timezone, health_config, currency into v_tz, cfg, v_ccy
  from public.projects where id = p_project and deleted_at is null;
  if v_tz is null then return; end if;
  v_today := (v_now at time zone v_tz)::date;
  inactive_days    := coalesce((cfg->>'inactive_days')::int, 7);
  due_soon_days    := coalesce((cfg->>'due_soon_days')::int, 7);
  tight_min        := coalesce((cfg->>'tight_connection_minutes')::int, 20);
  near_days        := coalesce((cfg->>'unconfirmed_near_days')::int, 14);
  on_budget_window := coalesce((cfg->>'on_budget_window_days')::int, 30);

  return query
  -- HLT-1 missing_owner
  select 'missing_owner','warning','commitment',c.id,c.title,
         jsonb_build_object('status',c.status),
         c.title || ' has no owner','Assign an owner',true,true
  from public.commitments c
  where c.project_id = p_project and c.deleted_at is null
    and c.status in ('researching','confirmed','booked') and c.owner_member_id is null

  union all
  -- HLT-2 orphaned_owner
  select 'orphaned_owner','warning','commitment',c.id,c.title,
         jsonb_build_object('owner',m.display_name),
         c.title || '''s owner (' || m.display_name || ') has left the project',
         'Assign a new owner',true,true
  from public.commitments c
  join public.project_members m on m.id = c.owner_member_id
  where c.project_id = p_project and c.deleted_at is null and c.status <> 'cancelled'
    and m.status = 'removed'

  union all
  -- HLT-3 payment_overdue  (blocker, not dismissible)
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
  -- HLT-4 payment_due_soon
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
  -- HLT-5 missing_booking_reference
  select 'missing_booking_reference','warning','commitment',c.id,c.title,
         jsonb_build_object('status',c.status),
         c.title || ' is ' || c.status || ' but has no confirmed booking reference',
         'Add the reference and mark the booking confirmed',true,true
  from public.commitments c
  where c.project_id = p_project and c.deleted_at is null
    and c.status in ('confirmed','booked','completed')
    and (c.booking_reference is null or c.booking_confirmed = false)

  union all
  -- HLT-6 unconfirmed_near_date
  select 'unconfirmed_near_date','warning','commitment',c.id,c.title,
         jsonb_build_object('status',c.status,'starts_at',c.starts_at),
         c.title || ' is still ' || c.status || ' but happens soon',
         'Confirm it or cancel it',true,true
  from public.commitments c
  where c.project_id = p_project and c.deleted_at is null
    and c.status in ('idea','researching') and c.starts_at is not null
    and c.starts_at <= v_now + (near_days || ' days')::interval

  union all
  -- HLT-7 commitment_inactive
  select 'commitment_inactive','warning','commitment',c.id,c.title,
         jsonb_build_object('updated_at',c.updated_at,'days',inactive_days),
         c.title || ' hasn''t been updated in ' || inactive_days || ' days',
         'Update it, advance its status, or cancel it',true,true
  from public.commitments c
  where c.project_id = p_project and c.deleted_at is null
    and c.status in ('idea','researching')
    and c.updated_at < v_now - (inactive_days || ' days')::interval

  union all
  -- HLT-8 missing_cost
  select 'missing_cost','warning','commitment',c.id,c.title,
         jsonb_build_object('status',c.status),
         c.title || ' is ' || c.status || ' but has no cost recorded',
         'Add the cost, or note that it''s free',true,true
  from public.commitments c
  where c.project_id = p_project and c.deleted_at is null
    and c.status in ('confirmed','booked','completed')
    and coalesce(c.confirmed_cost_minor, c.estimated_cost_minor, 0) = 0

  union all
  -- HLT-9 budget_exceeded
  select 'budget_exceeded','warning','project',p_project,pr.name,
         jsonb_build_object('total_cost_minor',f.total_cost_minor,'target_minor',f.total_target_minor,'currency',v_ccy),
         'Projected spend (' || app.format_money(f.total_cost_minor,v_ccy) || ') is over the '
           || app.format_money(f.total_target_minor,v_ccy) || ' budget',
         'Raise the budget, cut costs, or cancel commitments',true,true
  from public.v_project_financials f
  join public.projects pr on pr.id = f.project_id
  where f.project_id = p_project and f.total_target_minor is not null
    and f.total_cost_minor > f.total_target_minor

  union all
  -- HLT-10 category_over_target  (info)
  select 'category_over_target','info','budget_category',
         md5(p_project::text || a.kind::text)::uuid, a.kind::text,
         jsonb_build_object('kind',a.kind,'actual_minor',a.actual_minor,'target_minor',a.target_minor,'currency',v_ccy),
         a.kind || ' spend (' || app.format_money(a.actual_minor,v_ccy) || ') is over its '
           || app.format_money(a.target_minor,v_ccy) || ' target',
         'Adjust the target or the commitments',false,true
  from public.v_budget_category_actuals a
  where a.project_id = p_project and a.target_minor is not null and a.actual_minor > a.target_minor

  union all
  -- HLT-11 schedule_conflict
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
  -- HLT-12 tight_connection  (info)
  select 'tight_connection','info','commitment_pair',
         md5(least(c1.id::text,c2.id::text) || greatest(c1.id::text,c2.id::text))::uuid,
         c1.title || ' -> ' || c2.title,
         jsonb_build_object('gap_minutes', extract(epoch from (c2.starts_at - c1.ends_at))/60),
         'Only ' || round(extract(epoch from (c2.starts_at - c1.ends_at))/60)::text
           || ' min between ' || c1.title || ' and ' || c2.title,
         'Adjust times or acknowledge',false,true
  from public.commitments c1
  join public.commitments c2
    on c2.project_id = c1.project_id and c1.id <> c2.id
   and c1.deleted_at is null and c2.deleted_at is null
   and c1.status <> 'cancelled' and c2.status <> 'cancelled'
   and c1.ends_at is not null and c2.starts_at is not null
   and c2.starts_at >= c1.ends_at
   and c2.starts_at - c1.ends_at < (tight_min || ' minutes')::interval
   and (c1.starts_at at time zone v_tz)::date = (c2.starts_at at time zone v_tz)::date
  where c1.project_id = p_project

  union all
  -- HLT-13 task_overdue
  select 'task_overdue','warning','task',t.id,t.title,
         jsonb_build_object('due_on',t.due_on),
         'Task ''' || t.title || ''' was due ' || t.due_on::text,
         'Complete it, reschedule it, or cancel it',true,true
  from public.tasks t
  where t.project_id = p_project and t.deleted_at is null
    and t.status in ('open','in_progress') and t.due_on is not null and t.due_on < v_today

  union all
  -- HLT-14 task_unassigned_due_soon  (info)
  select 'task_unassigned_due_soon','info','task',t.id,t.title,
         jsonb_build_object('due_on',t.due_on),
         'Task ''' || t.title || ''' is due soon with no assignee','Assign it',false,true
  from public.tasks t
  where t.project_id = p_project and t.deleted_at is null
    and t.status in ('open','in_progress') and t.assignee_member_id is null
    and t.due_on is not null and t.due_on <= v_today + 7

  union all
  -- HLT-15 outside_project_dates  (info)
  select 'outside_project_dates','info','commitment',c.id,c.title,
         jsonb_build_object('starts_at',c.starts_at),
         c.title || ' is scheduled outside the project dates',
         'Adjust the commitment or project dates',false,true
  from public.commitments c
  join public.projects pr on pr.id = c.project_id
  where c.project_id = p_project and c.deleted_at is null and c.status <> 'cancelled'
    and c.starts_at is not null and pr.starts_on is not null and pr.ends_on is not null
    and ( (c.starts_at at time zone v_tz)::date < pr.starts_on
       or (c.starts_at at time zone v_tz)::date > pr.ends_on )

  union all
  -- HLT-16 unallocated_cost  (info)
  select 'unallocated_cost','info','commitment',c.id,c.title,
         '{}'::jsonb,
         c.title || '''s cost isn''t split between anyone',
         'Add participants or set a cost split',false,true
  from public.commitments c
  where c.project_id = p_project and c.deleted_at is null and c.status <> 'cancelled'
    and coalesce(c.confirmed_cost_minor,c.estimated_cost_minor,0) > 0
    and not exists (select 1 from public.commitment_participants p where p.commitment_id = c.id)
    and not exists (select 1 from public.cost_shares s where s.commitment_id = c.id)

  union all
  -- HLT-17 on_budget  (ok)
  select 'on_budget','ok','project',p_project,pr.name,
         jsonb_build_object('variance_minor', f.total_target_minor - f.total_cost_minor,'currency',v_ccy),
         'Projected spend is ' || app.format_money(f.total_target_minor - f.total_cost_minor, v_ccy)
           || ' under budget - on track','',false,true
  from public.v_project_financials f
  join public.projects pr on pr.id = f.project_id
  where f.project_id = p_project and f.total_target_minor is not null
    and f.total_cost_minor <= f.total_target_minor
    and ( f.progress_pct >= 50
       or (pr.ends_on is not null and pr.ends_on <= v_today + on_budget_window) );
end;
$$;

revoke execute on function app._health_findings(uuid) from public;
grant execute on function app._health_findings(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- public.get_project_health(project)  - SECURITY INVOKER; own membership check.
-- ---------------------------------------------------------------------------
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
   and d.subject_id is not distinct from f.subject_id;
end;
$$;

revoke execute on function public.get_project_health(uuid) from public;
grant execute on function public.get_project_health(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- public.get_project_health_summary(project)  - rollup (HLT-C / HLT-E)
-- ---------------------------------------------------------------------------
create or replace function public.get_project_health_summary(p_project uuid)
returns table (status text, blocker_count int, warning_count int, info_count int, attention_count int)
language sql stable security invoker set search_path = ''
as $$
  select
    case
      when count(*) filter (where severity = 'blocker' and not dismissed) > 0 then 'needs_attention'
      when count(*) filter (where severity = 'warning' and not dismissed) > 0 then 'at_risk'
      else 'healthy'
    end,
    count(*) filter (where severity = 'blocker' and not dismissed)::int,
    count(*) filter (where severity = 'warning' and not dismissed)::int,
    count(*) filter (where severity = 'info' and not dismissed)::int,
    count(*) filter (where severity in ('blocker','warning') and not dismissed)::int
  from public.get_project_health(p_project);
$$;

revoke execute on function public.get_project_health_summary(uuid) from public;
grant execute on function public.get_project_health_summary(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- public.get_invitation(token)  - pre-membership read, email-gated (SECURITY_RLS §6)
-- ---------------------------------------------------------------------------
create or replace function public.get_invitation(p_token text)
returns table (project_name text, inviter_name text, role public.member_role, status public.invitation_status)
language sql stable security definer set search_path = ''
as $$
  select p.name, m.display_name, i.role, i.status
  from public.invitations i
  join public.projects p on p.id = i.project_id
  left join public.project_members m on m.id = i.invited_by
  where i.token = p_token
    and lower(i.email) = (select lower(email) from public.users where id = auth.uid());
$$;

revoke execute on function public.get_invitation(text) from public;
grant execute on function public.get_invitation(text) to authenticated;

-- ---------------------------------------------------------------------------
-- public.accept_invitation(token) -> project_id  (SECURITY_RLS §6)
-- ---------------------------------------------------------------------------
create or replace function public.accept_invitation(p_token text)
returns uuid
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_email text;
  v_inv public.invitations%rowtype;
  v_member uuid;
  v_name text;
begin
  if v_uid is null then
    raise exception 'orchestr:auth_required:you must be signed in' using errcode = '42501';
  end if;
  perform set_config('app.bypass_member_guard', 'on', true);

  select lower(email), coalesce(nullif(btrim(display_name),''), split_part(email,'@',1))
    into v_email, v_name
  from public.users where id = v_uid;

  select * into v_inv from public.invitations where token = p_token;

  if v_inv.id is null then
    raise exception 'orchestr:invalid_invitation:this invitation link is invalid or has expired' using errcode = 'P0001';
  end if;

  if v_inv.status = 'accepted' then
    if exists (select 1 from public.project_members
               where id = v_inv.accepted_member_id and user_id = v_uid) then
      return v_inv.project_id;   -- idempotent for the same user
    end if;
    raise exception 'orchestr:invalid_invitation:this invitation link is invalid or has expired' using errcode = 'P0001';
  end if;

  if v_inv.status <> 'pending' or v_inv.expires_at < now() then
    raise exception 'orchestr:invalid_invitation:this invitation link is invalid or has expired' using errcode = 'P0001';
  end if;

  if lower(v_inv.email) <> v_email then
    raise exception 'orchestr:invitation_email_mismatch:this invitation was sent to a different email address'
      using errcode = 'P0001';
  end if;

  -- already linked?
  select id into v_member from public.project_members
   where project_id = v_inv.project_id and user_id = v_uid;
  if v_member is not null then
    update public.project_members set status = 'active'
     where id = v_member and status <> 'active';
  else
    -- claim a matching name-only row
    select id into v_member from public.project_members
     where project_id = v_inv.project_id and user_id is null
       and lower(email) = v_email and status <> 'removed' and deleted_at is null
     limit 1;
    if v_member is not null then
      update public.project_members
         set user_id = v_uid, status = 'active', joined_at = now()
       where id = v_member;
    else
      insert into public.project_members
        (project_id, user_id, display_name, email, role, status, invited_at, joined_at)
      values
        (v_inv.project_id, v_uid, left(v_name,80), v_email, v_inv.role, 'active', v_inv.created_at, now())
      returning id into v_member;
    end if;
  end if;

  update public.invitations
     set status = 'accepted', accepted_at = now(), accepted_member_id = v_member
   where id = v_inv.id;

  insert into public.audit_log
    (project_id, actor_user_id, actor_member_id, source, action, entity_type, entity_id, after)
  values
    (v_inv.project_id, v_uid, v_member, 'rpc', 'update', 'invitations', v_inv.id,
     jsonb_build_object('status','accepted','accepted_member_id',v_member));

  return v_inv.project_id;
end;
$$;

revoke execute on function public.accept_invitation(text) from public;
grant execute on function public.accept_invitation(text) to authenticated;

-- ---------------------------------------------------------------------------
-- public.transfer_and_leave(project, new_organizer_member)  (SECURITY_RLS §6)
-- ---------------------------------------------------------------------------
create or replace function public.transfer_and_leave(p_project uuid, p_new_organizer_member uuid)
returns void
language plpgsql volatile security definer set search_path = ''
as $$
begin
  if not app.is_organizer(p_project) then
    raise exception 'orchestr:not_organizer:only an organizer can transfer control' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.project_members
    where id = p_new_organizer_member and project_id = p_project
      and status = 'active' and deleted_at is null
  ) then
    raise exception 'orchestr:invalid_target:target must be an active member of this project' using errcode = 'P0001';
  end if;

  update public.project_members set role = 'organizer' where id = p_new_organizer_member;
  update public.project_members set status = 'removed'
   where project_id = p_project and user_id = auth.uid() and status = 'active';
end;
$$;

revoke execute on function public.transfer_and_leave(uuid, uuid) from public;
grant execute on function public.transfer_and_leave(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- v_my_projects  (depends on get_project_health_summary)
-- ---------------------------------------------------------------------------
create view public.v_my_projects
with (security_invoker = true) as
select
  pr.id as project_id,
  pr.name, pr.status, pr.starts_on, pr.ends_on, pr.timezone, pr.currency,
  me.role as my_role,
  fin.total_cost_minor, fin.committed_spend_minor, fin.net_actual_spend_minor,
  fin.outstanding_minor, fin.remaining_budget_minor, fin.progress_pct,
  h.status as health_status, h.attention_count,
  (select min(occurs_at) from public.v_timeline_events te
    where te.project_id = pr.id and te.occurs_at >= now()) as next_event_at
from public.projects pr
join public.project_members me
  on me.project_id = pr.id and me.user_id = auth.uid()
 and me.status = 'active' and me.deleted_at is null
left join public.v_project_financials fin on fin.project_id = pr.id
left join lateral public.get_project_health_summary(pr.id) h on true
where pr.deleted_at is null;

grant select on public.v_my_projects to authenticated;
