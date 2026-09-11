-- Additive taxonomy: classification never selects Activity workflow.
alter type public.commitment_kind add value if not exists 'equipment_assets';
alter type public.commitment_kind add value if not exists 'technology';
alter type public.commitment_kind add value if not exists 'marketing';
alter type public.commitment_kind add value if not exists 'supplies_materials';
alter type public.commitment_kind add value if not exists 'fees_admin';

-- Append payment-derived category totals without changing existing column meanings.
create or replace view public.v_budget_category_actuals
with (security_invoker = true) as
select pr.id as project_id, k.kind, t.amount_minor as target_minor,
  coalesce(a.actual_minor,0)::bigint as actual_minor,
  case when t.amount_minor is null then null else t.amount_minor-coalesce(a.actual_minor,0) end::bigint as variance_minor,
  coalesce(p.net_paid_minor,0)::bigint as net_paid_minor
from public.projects pr
cross join (select unnest(enum_range(null::public.commitment_kind)) as kind) k
left join public.budget_category_targets t on t.project_id=pr.id and t.kind=k.kind
left join lateral (
  select sum(app.effective_commitment_cost(c.actual_cost_minor,c.confirmed_cost_minor,c.estimated_cost_minor)) as actual_minor
  from public.commitments c
  where c.project_id=pr.id and c.kind=k.kind and c.deleted_at is null and c.status<>'cancelled'
) a on true
left join lateral (
  select sum(case when pay.direction='outgoing' then pay.amount_minor else -pay.amount_minor end) as net_paid_minor
  from public.payments pay join public.commitments c on c.id=pay.commitment_id and c.deleted_at is null
  where pay.project_id=pr.id and c.kind=k.kind and pay.deleted_at is null and pay.status='paid'
) p on true
where pr.deleted_at is null;
