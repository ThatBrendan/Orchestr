-- Phase 4: future completion of cost-bearing Activities requires settlement.
-- Historical completed rows are untouched; this guard only evaluates transitions.

create or replace function public.set_actual_cost_with_split(p_commitment uuid,p_amount numeric,p_complete boolean,p_split jsonb)
returns void language plpgsql security invoker set search_path='' as $$
begin
  -- Reconcile final cost and split before the completion guard evaluates settlement.
  perform public.set_commitment_actual_cost(p_commitment,p_amount,false);
  if p_split is not null then perform public.set_activity_cost_split(p_commitment,p_split); end if;
  if p_complete then update public.commitments set status='completed' where id=p_commitment; end if;
end;
$$;

create or replace function app.commitment_financially_settled(p_commitment uuid)
returns boolean
language sql
stable
security definer
set search_path=''
as $$
with c as (
  select id, app.effective_commitment_cost(actual_cost_minor, confirmed_cost_minor, estimated_cost_minor)::bigint as cost
  from public.commitments
  where id=p_commitment and deleted_at is null
), paid as (
  select
    coalesce(sum(amount_minor) filter (where direction='outgoing' and status='paid'),0)::bigint
      - coalesce(sum(amount_minor) filter (where direction='incoming' and status='paid'),0)::bigint as net_paid,
    exists (
      select 1 from public.payments
      where commitment_id=p_commitment and status='scheduled' and deleted_at is null
    ) as has_scheduled
  from public.payments
  where commitment_id=p_commitment and deleted_at is null
)
select case
  when c.cost <= 0 then true
  when paid.has_scheduled then false
  when exists (select 1 from public.v_activity_cost_shares where commitment_id=p_commitment) then not exists (
    select 1 from public.v_activity_member_settlements
    where commitment_id=p_commitment and remaining_minor > 0
  )
  else paid.net_paid >= c.cost
end
from c cross join paid;
$$;
revoke all on function app.commitment_financially_settled(uuid) from public;
grant execute on function app.commitment_financially_settled(uuid) to authenticated, service_role;

create or replace function app.tg_commitment_financial_completion_guard()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if new.status='completed' and old.status is distinct from 'completed'
     and app.effective_commitment_cost(new.actual_cost_minor,new.confirmed_cost_minor,new.estimated_cost_minor) > 0
     and not app.commitment_financially_settled(new.id) then
    raise exception 'orchestr:financial_unsettled:This Activity still has payments to settle before it can be completed.' using errcode='P0001';
  end if;
  return new;
end;
$$;
revoke all on function app.tg_commitment_financial_completion_guard() from public;

drop trigger if exists financial_completion_guard on public.commitments;
create trigger financial_completion_guard
before update of status,actual_cost_minor,confirmed_cost_minor,estimated_cost_minor on public.commitments
for each row execute function app.tg_commitment_financial_completion_guard();