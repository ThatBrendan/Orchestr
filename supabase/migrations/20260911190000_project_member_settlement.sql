-- Preserve attributed payment history even after an allocation is explicitly removed.
create or replace view public.v_activity_member_settlements with (security_invoker=true) as
with pairs as (
 select project_id,commitment_id,member_id from public.v_activity_cost_shares
 union
 select project_id,commitment_id,paid_by_member_id from public.payments where deleted_at is null and paid_by_member_id is not null
)
select k.project_id,k.commitment_id,k.member_id,m.display_name,m.status as member_status,
 coalesce(s.amount_minor,0)::bigint as allocated_minor,coalesce(p.paid,0)::bigint as paid_minor,
 (coalesce(s.amount_minor,0)-coalesce(p.paid,0))::bigint as remaining_minor
from pairs k join public.commitments c on c.id=k.commitment_id and c.deleted_at is null
join public.project_members m on m.id=k.member_id and m.project_id=k.project_id
left join public.v_activity_cost_shares s on s.commitment_id=k.commitment_id and s.member_id=k.member_id
left join lateral (
 select sum(case when direction='outgoing' then amount_minor else -amount_minor end) as paid
 from public.payments where commitment_id=k.commitment_id and paid_by_member_id=k.member_id and status='paid' and deleted_at is null
) p on true;

create view public.v_project_member_settlements with (security_invoker=true) as
select s.project_id,s.member_id,s.display_name,s.member_status,p.currency,
 sum(case when c.status='cancelled' then 0 else s.allocated_minor end)::bigint as allocated_minor,
 sum(s.paid_minor)::bigint as paid_minor,
 sum(case when c.status='cancelled' then 0 else s.allocated_minor end-s.paid_minor)::bigint as remaining_minor
from public.v_activity_member_settlements s join public.commitments c on c.id=s.commitment_id
join public.projects p on p.id=s.project_id
where c.deleted_at is null and p.deleted_at is null
group by s.project_id,s.member_id,s.display_name,s.member_status,p.currency;
create view public.v_project_settlement_totals with (security_invoker=true) as
select project_id,sum(greatest(remaining_minor,0))::bigint as remaining_minor,
 sum(greatest(-remaining_minor,0))::bigint as credit_minor
from public.v_project_member_settlements group by project_id;
grant select on public.v_project_member_settlements,public.v_project_settlement_totals to authenticated;
