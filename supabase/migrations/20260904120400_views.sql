-- ============================================================================
-- 20260904120400_views
-- Derived read models. NO derived data is stored (docs/DATABASE_SCHEMA.md §5).
-- All views are security_invoker so base-table RLS applies to the caller,
-- except v_member_directory (deliberate definer view - docs/SECURITY_RLS.md §7).
--
-- Formulas: docs/BUSINESS_RULES.md §8 (with the §8 financial-history amendment).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- v_commitment_financials  - per commitment
-- ---------------------------------------------------------------------------
create view public.v_commitment_financials
with (security_invoker = true) as
select
  c.id            as commitment_id,
  c.project_id,
  c.status,
  coalesce(c.confirmed_cost_minor, c.estimated_cost_minor, 0)::bigint as effective_cost_minor,
  coalesce(p.gross_paid, 0)::bigint     as gross_paid_minor,
  coalesce(p.refunded, 0)::bigint       as refunded_minor,
  (coalesce(p.gross_paid,0) - coalesce(p.refunded,0))::bigint as net_paid_minor,
  greatest(
    coalesce(c.confirmed_cost_minor, c.estimated_cost_minor, 0)
      - (coalesce(p.gross_paid,0) - coalesce(p.refunded,0)),
    0
  )::bigint as outstanding_minor,
  case
    when coalesce(c.confirmed_cost_minor, c.estimated_cost_minor, 0) = 0
         and coalesce(p.gross_paid,0) - coalesce(p.refunded,0) > 0 then 'paid_in_full'
    when coalesce(p.gross_paid,0) - coalesce(p.refunded,0) <= 0 then 'unpaid'
    when coalesce(p.gross_paid,0) - coalesce(p.refunded,0)
         >= coalesce(c.confirmed_cost_minor, c.estimated_cost_minor, 0) then 'paid_in_full'
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

comment on view public.v_commitment_financials is
  'Per-commitment derived finance. payment_progress is the derived per-commitment status (NOT stored); payments.status is the stored per-row lifecycle.';

-- ---------------------------------------------------------------------------
-- v_project_financials  - per project roll-up (docs/BUSINESS_RULES.md §8.2)
-- ---------------------------------------------------------------------------
create view public.v_project_financials
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
  count(*) filter (where cf.status not in ('cancelled','completed'))      as open_commitment_count
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

-- ---------------------------------------------------------------------------
-- v_budget_category_actuals  - per (project, kind)  (BUD-10 / BUD-9 per-category)
-- ---------------------------------------------------------------------------
create view public.v_budget_category_actuals
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
  select sum(coalesce(c.confirmed_cost_minor, c.estimated_cost_minor, 0)) as actual_minor
  from public.commitments c
  where c.project_id = pr.id and c.deleted_at is null and c.status <> 'cancelled' and c.kind = k.kind
) a on true
where pr.deleted_at is null;

-- ---------------------------------------------------------------------------
-- v_member_balances  - per (project, member)  (docs/BUSINESS_RULES.md §8.3)
-- Explicit cost_shares override the default equal-split over participants.
-- Deterministic minor-unit rounding: lowest member_id first (BUD-16).
-- ---------------------------------------------------------------------------
create view public.v_member_balances
with (security_invoker = true) as
with
tc as (
  select c.id, c.project_id,
         coalesce(c.confirmed_cost_minor, c.estimated_cost_minor, 0)::bigint as cost
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

-- ---------------------------------------------------------------------------
-- v_timeline_events  - fully derived (docs/BUSINESS_RULES.md §7 / TML-1)
-- ---------------------------------------------------------------------------
create view public.v_timeline_events
with (security_invoker = true) as
  -- scheduled commitments (start)
  select c.project_id, c.starts_at as occurs_at, false as all_day,
         'commitment_start'::text as event_type, c.title,
         'commitment'::text as subject_type, c.id as subject_id, c.status::text as status
  from public.commitments c
  where c.deleted_at is null and c.status <> 'cancelled' and c.starts_at is not null
union all
  select c.project_id, c.ends_at, false, 'commitment_end', c.title,
         'commitment', c.id, c.status::text
  from public.commitments c
  where c.deleted_at is null and c.status <> 'cancelled' and c.ends_at is not null
union all
  -- scheduled payments due
  select pay.project_id,
         (pay.due_on::timestamp at time zone pr.timezone),
         true, 'payment_due',
         'Payment due - ' || c.title, 'payment', pay.id, pay.status::text
  from public.payments pay
  join public.commitments c on c.id = pay.commitment_id and c.deleted_at is null
  join public.projects pr on pr.id = pay.project_id
  where pay.deleted_at is null and pay.status = 'scheduled' and pay.due_on is not null
union all
  -- payments made
  select pay.project_id,
         (pay.paid_on::timestamp at time zone pr.timezone),
         true, 'payment_made',
         'Payment made - ' || c.title, 'payment', pay.id, pay.status::text
  from public.payments pay
  join public.commitments c on c.id = pay.commitment_id and c.deleted_at is null
  join public.projects pr on pr.id = pay.project_id
  where pay.deleted_at is null and pay.status = 'paid' and pay.paid_on is not null
union all
  -- tasks due
  select t.project_id,
         (t.due_on::timestamp at time zone pr.timezone),
         true, 'task_due', 'Task: ' || t.title, 'task', t.id, t.status::text
  from public.tasks t
  join public.projects pr on pr.id = t.project_id
  where t.deleted_at is null and t.status in ('open','in_progress') and t.due_on is not null
union all
  -- milestones
  select m.project_id,
         (m.on_date::timestamp at time zone pr.timezone),
         true, 'milestone', m.title, 'milestone', m.id, null
  from public.milestones m
  join public.projects pr on pr.id = m.project_id
union all
  -- project boundaries
  select pr.id, (pr.starts_on::timestamp at time zone pr.timezone), true,
         'project_start', pr.name || ' starts', 'project', pr.id, pr.status::text
  from public.projects pr where pr.deleted_at is null and pr.starts_on is not null
union all
  select pr.id, (pr.ends_on::timestamp at time zone pr.timezone), true,
         'project_end', pr.name || ' ends', 'project', pr.id, pr.status::text
  from public.projects pr where pr.deleted_at is null and pr.ends_on is not null;

-- ---------------------------------------------------------------------------
-- v_member_directory  - DEFINER view (docs/SECURITY_RLS.md §7): members may see
-- co-members' name + avatar without a broad `users` policy. Column whitelist +
-- internal is_member() filter are the safety mechanism.
-- ---------------------------------------------------------------------------
create view public.v_member_directory
with (security_invoker = false) as
select
  pm.project_id,
  pm.id            as member_id,
  pm.display_name,
  u.avatar_url,
  pm.role,
  pm.status
from public.project_members pm
left join public.users u on u.id = pm.user_id
where pm.deleted_at is null
  and app.is_member(pm.project_id);

-- v_my_projects is created in 20260904120500_functions_rpcs.sql (it depends on the health RPC).

grant select on
  public.v_commitment_financials, public.v_project_financials, public.v_budget_category_actuals,
  public.v_member_balances, public.v_timeline_events, public.v_member_directory
to authenticated;
