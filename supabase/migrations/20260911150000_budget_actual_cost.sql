-- Estimates/agreed prices remain unchanged; actual is unknown for historical rows.
alter table public.commitments add column actual_cost_minor bigint check(actual_cost_minor>=0);

create function app.effective_commitment_cost(p_actual bigint,p_confirmed bigint,p_estimated bigint)
returns bigint language sql immutable set search_path='' as $$ select coalesce(p_actual,p_confirmed,p_estimated,0); $$;
revoke all on function app.effective_commitment_cost(bigint,bigint,bigint) from public;
grant execute on function app.effective_commitment_cost(bigint,bigint,bigint) to authenticated,service_role;

create function public.set_project_budget(p_project uuid,p_amount numeric)
returns void language plpgsql security definer set search_path='' as $$
begin
  if not app.is_organizer(p_project) then raise exception 'orchestr:not_authorized:Only an organizer may set the project budget.' using errcode='42501'; end if;
  perform 1 from public.projects where id=p_project and deleted_at is null and status<>'archived' for update;
  if not found then raise exception 'orchestr:project_archived:This project is read-only.' using errcode='42501'; end if;
  if p_amount is not null and (p_amount<0 or p_amount>9007199254740991 or p_amount<>trunc(p_amount)) then
    raise exception 'orchestr:invalid_amount:Budget must be a non-negative whole minor-unit amount.' using errcode='22023'; end if;
  insert into public.budgets(project_id,total_target_minor) values(p_project,p_amount::bigint)
  on conflict(project_id) do update set total_target_minor=excluded.total_target_minor;
end $$;
revoke all on function public.set_project_budget(uuid,numeric) from public;
grant execute on function public.set_project_budget(uuid,numeric) to authenticated;

-- Guard direct table writes as well as the RPC. Authorize using the OLD owner,
-- never a replacement owner supplied in the same UPDATE.
create function app.guard_actual_cost() returns trigger language plpgsql security definer set search_path='' as $$
declare v_changed boolean; v_owner uuid; v_status public.commitment_status;
begin
  if tg_op='INSERT' then v_changed := new.actual_cost_minor is not null;
  else v_changed := new.actual_cost_minor is distinct from old.actual_cost_minor; v_owner:=old.owner_member_id; v_status:=old.status; end if;
  if not v_changed then return new; end if;
  if auth.uid() is not null then
    if not app.is_writable_project(new.project_id) or not (app.is_organizer(new.project_id)
      or (app.has_role(new.project_id,array['member']::public.member_role[]) and coalesce(v_owner=app.current_member_id(new.project_id),false)
          and v_status not in ('completed','cancelled'))) then
      raise exception 'orchestr:not_authorized:Only an organizer or the assigned member of an actionable activity may change final cost.' using errcode='42501'; end if;
  end if;
  return new;
end $$;
revoke all on function app.guard_actual_cost() from public;
create trigger guard_actual_cost before insert or update on public.commitments for each row execute function app.guard_actual_cost();

create function public.set_commitment_actual_cost(p_commitment uuid,p_amount numeric,p_complete boolean default false)
returns void language plpgsql security definer set search_path='' as $$
declare c public.commitments%rowtype;
begin
  select * into c from public.commitments where id=p_commitment and deleted_at is null for update;
  if not found or not coalesce((app.is_organizer(c.project_id) or
    (app.has_role(c.project_id,array['member']::public.member_role[]) and c.owner_member_id=app.current_member_id(c.project_id)
      and c.status not in ('completed','cancelled'))),false) then
    raise exception 'orchestr:not_authorized:You cannot change final cost for this activity.' using errcode='42501'; end if;
  if not app.is_writable_project(c.project_id) then raise exception 'orchestr:project_archived:This project is read-only.' using errcode='42501'; end if;
  if p_amount is not null and (p_amount<0 or p_amount>9007199254740991 or p_amount<>trunc(p_amount)) then
    raise exception 'orchestr:invalid_amount:Final cost must be a non-negative whole minor-unit amount.' using errcode='22023'; end if;
  if p_complete and c.recurrence_frequency is not null then raise exception 'orchestr:recurring_activity:Complete recurring occurrences separately.' using errcode='22023'; end if;
  update public.commitments set actual_cost_minor=p_amount::bigint,
    status=case when p_complete then 'completed'::public.commitment_status else status end where id=p_commitment;
end $$;
revoke all on function public.set_commitment_actual_cost(uuid,numeric,boolean) from public;
grant execute on function public.set_commitment_actual_cost(uuid,numeric,boolean) to authenticated;

create or replace view public.v_commitment_financials
with (security_invoker = true) as
select
  c.id            as commitment_id,
  c.project_id,
  c.status,
  app.effective_commitment_cost(c.actual_cost_minor,c.confirmed_cost_minor,c.estimated_cost_minor)::bigint as effective_cost_minor,
  coalesce(p.gross_paid, 0)::bigint     as gross_paid_minor,
  coalesce(p.refunded, 0)::bigint       as refunded_minor,
  (coalesce(p.gross_paid,0) - coalesce(p.refunded,0))::bigint as net_paid_minor,
  greatest(
    app.effective_commitment_cost(c.actual_cost_minor,c.confirmed_cost_minor,c.estimated_cost_minor)
      - (coalesce(p.gross_paid,0) - coalesce(p.refunded,0)),
    0
  )::bigint as outstanding_minor,
  case
    when app.effective_commitment_cost(c.actual_cost_minor,c.confirmed_cost_minor,c.estimated_cost_minor) = 0
         and coalesce(p.gross_paid,0) - coalesce(p.refunded,0) > 0 then 'paid_in_full'
    when coalesce(p.gross_paid,0) - coalesce(p.refunded,0) <= 0 then 'unpaid'
    when coalesce(p.gross_paid,0) - coalesce(p.refunded,0)
         >= app.effective_commitment_cost(c.actual_cost_minor,c.confirmed_cost_minor,c.estimated_cost_minor) then 'paid_in_full'
    when coalesce(p.paid_out_count,0) > 0 and coalesce(p.only_deposits, false) then 'deposit_paid'
    else 'part_paid'
  end as payment_progress
from public.commitments c
left join lateral (
  select
    sum(pay.amount_minor) filter (where pay.status='paid' and pay.direction='outgoing') as gross_paid,
    sum(pay.amount_minor) filter (where pay.status='paid' and pay.direction='incoming') as refunded,
    count(*)              filter (where pay.status='paid' and pay.direction='outgoing') as paid_out_count,
    bool_and(pay.type='deposit') filter (where pay.status='paid' and pay.direction='outgoing') as only_deposits
  from public.payments pay
  where pay.commitment_id = c.id and pay.deleted_at is null
) p on true
where c.deleted_at is null;

create or replace view public.v_project_financials
with (security_invoker = true) as
select
  pr.id as project_id,
  -- BUD-4 total cost: all non-cancelled commitments
  coalesce(sum(cf.effective_cost_minor) filter (where cf.status <> 'cancelled'), 0)::bigint as total_cost_minor,
  -- BUD-5 committed spend
  coalesce(sum(cf.effective_cost_minor) filter (where cf.status in ('confirmed','booked','completed')), 0)::bigint as committed_spend_minor,
  -- BUD-6 financial history (NOT filtered by commitment status - see §8 amendment)
  coalesce(pf.gross_paid, 0)::bigint as gross_paid_minor,
  coalesce(pf.refunded, 0)::bigint   as refunded_minor,
  (coalesce(pf.gross_paid,0) - coalesce(pf.refunded,0))::bigint as net_actual_spend_minor,
  -- BUD-7 outstanding: per-committed-commitment floor, then sum
  coalesce(sum(cf.outstanding_minor) filter (where cf.status in ('confirmed','booked','completed')), 0)::bigint as outstanding_minor,
  -- PAY-14 scheduled outstanding
  coalesce(pf.scheduled_out, 0)::bigint as scheduled_outstanding_minor,
  -- BUD-8 / BUD-9 (null when no budget row / null target)
  b.total_target_minor,
  case when b.total_target_minor is null then null
       else b.total_target_minor
            - coalesce(sum(cf.effective_cost_minor) filter (where cf.status <> 'cancelled'), 0)
  end::bigint as remaining_budget_minor,
  case when b.total_target_minor is null then null
       else b.total_target_minor
            - coalesce(sum(cf.effective_cost_minor) filter (where cf.status <> 'cancelled'), 0)
  end::bigint as projected_variance_minor,
  case when b.total_target_minor is null then null
       else b.total_target_minor - (coalesce(pf.gross_paid,0) - coalesce(pf.refunded,0))
  end::bigint as settled_variance_minor,
  -- VAL-49 progress %
  coalesce(round(
    100.0 * count(*) filter (where cf.status in ('confirmed','booked','completed'))
    / nullif(count(*) filter (where cf.status <> 'cancelled'), 0)
  ), 0)::int as progress_pct,
  count(*) filter (where cf.status <> 'cancelled')                        as commitment_count,
  count(*) filter (where cf.status not in ('cancelled','completed'))      as open_commitment_count,
  case when b.total_target_minor > 0 then round(100.0 * coalesce(sum(cf.effective_cost_minor) filter(where cf.status<>'cancelled'),0) / b.total_target_minor,1) else null end as budget_used_pct
from public.projects pr
left join public.v_commitment_financials cf on cf.project_id = pr.id
left join public.budgets b on b.project_id = pr.id
left join lateral (
  select
    coalesce(sum(pay.amount_minor) filter (where pay.status='paid' and pay.direction='outgoing'),0) as gross_paid,
    coalesce(sum(pay.amount_minor) filter (where pay.status='paid' and pay.direction='incoming'),0) as refunded,
    coalesce(sum(pay.amount_minor) filter (where pay.status='scheduled'),0) as scheduled_out
  from public.payments pay
  join public.commitments cc on cc.id = pay.commitment_id and cc.deleted_at is null
  where pay.project_id = pr.id and pay.deleted_at is null
) pf on true
where pr.deleted_at is null
group by pr.id, pf.gross_paid, pf.refunded, pf.scheduled_out, b.total_target_minor;

create or replace view public.v_budget_category_actuals
with (security_invoker = true) as
select
  pr.id as project_id,
  k.kind,
  t.amount_minor as target_minor,
  coalesce(a.actual_minor, 0)::bigint as actual_minor,
  case when t.amount_minor is null then null
       else t.amount_minor - coalesce(a.actual_minor, 0) end::bigint as variance_minor
from public.projects pr
cross join (select unnest(enum_range(null::public.commitment_kind)) as kind) k
left join public.budget_category_targets t on t.project_id = pr.id and t.kind = k.kind
left join lateral (
  select sum(app.effective_commitment_cost(c.actual_cost_minor,c.confirmed_cost_minor,c.estimated_cost_minor)) as actual_minor
  from public.commitments c
  where c.project_id = pr.id and c.deleted_at is null and c.status <> 'cancelled' and c.kind = k.kind
) a on true
where pr.deleted_at is null;

create or replace view public.v_member_balances
with (security_invoker = true) as
with
tc as (
  select c.id, c.project_id,
         app.effective_commitment_cost(c.actual_cost_minor,c.confirmed_cost_minor,c.estimated_cost_minor)::bigint as cost
  from public.commitments c
  where c.deleted_at is null and c.status in ('confirmed','booked','completed')
),
cs as (
  select s.commitment_id, s.member_id, s.basis, s.weight, s.fixed_amount_minor
  from public.cost_shares s
  join tc on tc.id = s.commitment_id
),
cs_commitments as (select distinct commitment_id from cs),
fixed_tot as (
  select commitment_id, coalesce(sum(fixed_amount_minor),0) as ft
  from cs where basis = 'fixed' group by commitment_id
),
w_tot as (
  select commitment_id, sum(weight) as wsum
  from cs where basis = 'weight' group by commitment_id
),
-- weight basis (exclusive): floor then hand remainder to lowest member_ids
share_weight_base as (
  select cs.commitment_id, cs.member_id, tc.cost,
         floor(tc.cost * cs.weight / w_tot.wsum)::bigint as base_share,
         row_number() over (partition by cs.commitment_id order by cs.member_id) as rn
  from cs
  join tc on tc.id = cs.commitment_id
  join w_tot on w_tot.commitment_id = cs.commitment_id
  where cs.basis = 'weight'
),
share_weight as (
  select commitment_id, member_id,
         base_share + case when rn <= (cost - sum(base_share) over (partition by commitment_id))
                           then 1 else 0 end as share
  from share_weight_base
),
share_fixed as (
  select commitment_id, member_id, fixed_amount_minor::bigint as share
  from cs where basis = 'fixed'
),
equal_expl_base as (
  select cs.commitment_id, cs.member_id,
         (tc.cost - coalesce(ft.ft,0))::bigint as pot,
         count(*) over (partition by cs.commitment_id) as n,
         row_number() over (partition by cs.commitment_id order by cs.member_id) as rn
  from cs
  join tc on tc.id = cs.commitment_id
  left join fixed_tot ft on ft.commitment_id = cs.commitment_id
  where cs.basis = 'equal'
),
share_equal_expl as (
  select commitment_id, member_id,
         (pot / n) + case when rn <= (pot - (pot/n)*n) then 1 else 0 end as share
  from equal_expl_base
),
part_base as (
  select cp.commitment_id, cp.member_id, tc.cost::bigint as pot,
         count(*) over (partition by cp.commitment_id) as n,
         row_number() over (partition by cp.commitment_id order by cp.member_id) as rn
  from public.commitment_participants cp
  join tc on tc.id = cp.commitment_id
  where cp.commitment_id not in (select commitment_id from cs_commitments)
),
share_default as (
  select commitment_id, member_id,
         (pot / n) + case when rn <= (pot - (pot/n)*n) then 1 else 0 end as share
  from part_base
),
all_shares as (
  select commitment_id, member_id, share from share_weight
  union all select commitment_id, member_id, share from share_fixed
  union all select commitment_id, member_id, share from share_equal_expl
  union all select commitment_id, member_id, share from share_default
),
owed as (
  select tc.project_id, s.member_id, sum(s.share)::bigint as owed_minor
  from all_shares s join tc on tc.id = s.commitment_id
  group by tc.project_id, s.member_id
),
contributed as (
  select pay.project_id, pay.paid_by_member_id as member_id,
         sum(case when pay.direction = 'outgoing' then pay.amount_minor else -pay.amount_minor end)::bigint as contributed_minor
  from public.payments pay
  join public.commitments c on c.id = pay.commitment_id and c.deleted_at is null
  where pay.deleted_at is null and pay.status = 'paid' and pay.paid_by_member_id is not null
  group by pay.project_id, pay.paid_by_member_id
),
mem as (
  select id as member_id, project_id, display_name, status
  from public.project_members where deleted_at is null
)
select
  mem.project_id,
  mem.member_id,
  mem.display_name,
  mem.status as member_status,
  coalesce(o.owed_minor, 0)::bigint as owed_minor,
  coalesce(c.contributed_minor, 0)::bigint as contributed_minor,
  (coalesce(c.contributed_minor, 0) - coalesce(o.owed_minor, 0))::bigint as balance_minor
from mem
left join owed o on o.project_id = mem.project_id and o.member_id = mem.member_id
left join contributed c on c.project_id = mem.project_id and c.member_id = mem.member_id;

create or replace view public.v_admin_projects
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
    sum(app.effective_commitment_cost(c.actual_cost_minor,c.confirmed_cost_minor,c.estimated_cost_minor)) filter (where c.deleted_at is null and c.status <> 'cancelled')::bigint as total_cost_minor
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
    and coalesce(c.actual_cost_minor,c.confirmed_cost_minor,c.estimated_cost_minor) is null

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
    and app.effective_commitment_cost(c.actual_cost_minor,c.confirmed_cost_minor,c.estimated_cost_minor) > 0
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

create or replace function app.tg_cost_share_basis_consistency()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_commitment uuid := coalesce(new.commitment_id, old.commitment_id);
  v_bases text[];
  v_fixed_total bigint;
  v_cost bigint;
begin
  select array_agg(distinct basis::text) into v_bases
  from public.cost_shares where commitment_id = v_commitment;

  if v_bases is null then
    return coalesce(new, old);   -- all removed
  end if;

  if not (
       v_bases <@ array['equal']
    or v_bases <@ array['weight']
    or v_bases <@ array['fixed','equal']
  ) then
    raise exception 'orchestr:cost_share_mix:a commitment''s cost shares must be all equal, all weight, or a mix of fixed and equal'
      using errcode = 'P0001';
  end if;

  if 'fixed' = any (v_bases) then
    select coalesce(sum(fixed_amount_minor),0) into v_fixed_total
    from public.cost_shares where commitment_id = v_commitment and basis = 'fixed';
    select app.effective_commitment_cost(actual_cost_minor,confirmed_cost_minor,estimated_cost_minor) into v_cost
    from public.commitments where id = v_commitment;
    if v_fixed_total > v_cost then
      raise exception 'orchestr:cost_share_overflow:fixed shares (%) exceed the commitment cost (%)',
        v_fixed_total, v_cost
        using errcode = 'P0001';
    end if;
  end if;
  return coalesce(new, old);
end;
$$;
