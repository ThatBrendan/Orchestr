-- Existing payment attribution is the settlement ledger; no paid flag or competing table.
create view public.v_activity_member_settlements with (security_invoker=true) as
select s.project_id,s.commitment_id,s.member_id,m.display_name,m.status as member_status,
 s.amount_minor as allocated_minor,coalesce(p.paid,0)::bigint as paid_minor,
 (s.amount_minor-coalesce(p.paid,0))::bigint as remaining_minor
from public.v_activity_cost_shares s
join public.project_members m on m.id=s.member_id and m.project_id=s.project_id
left join lateral (
 select sum(case when direction='outgoing' then amount_minor else -amount_minor end) as paid
 from public.payments where commitment_id=s.commitment_id and paid_by_member_id=s.member_id
 and status='paid' and deleted_at is null
) p on true;
grant select on public.v_activity_member_settlements to authenticated;

create function app.guard_payment_settlement_member() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 -- Serialize financial edits with future completion checks.
 if tg_op='UPDATE' and new.commitment_id is distinct from old.commitment_id then
  raise exception 'orchestr:immutable_column:A Payment cannot move to another Activity.';
 end if;
 perform 1 from public.commitments where id=coalesce(new.commitment_id,old.commitment_id) for update;
 if tg_op='DELETE' then return old; end if;
 if auth.uid() is not null and not app.is_organizer(new.project_id) then
  if (new.paid_by_member_id is not null and new.paid_by_member_id is distinct from app.current_member_id(new.project_id))
    or (tg_op='UPDATE' and old.paid_by_member_id is not null and old.paid_by_member_id is distinct from app.current_member_id(new.project_id)) then
   raise exception 'orchestr:not_authorized:Only an organizer can record or change another member''s payment.' using errcode='42501';
  end if;
 end if;
 if new.paid_by_member_id is not null and (tg_op='INSERT' or new.paid_by_member_id is distinct from old.paid_by_member_id or (new.status='paid' and old.status is distinct from 'paid')) then
  perform 1 from public.project_members where id=new.paid_by_member_id and project_id=new.project_id and status='active' and deleted_at is null for share;
  if not found then raise exception 'orchestr:invalid_member:Select an active member of this project.' using errcode='42501'; end if;
 end if;
 return new;
end $$;
revoke all on function app.guard_payment_settlement_member() from public;
create trigger settlement_member_guard before insert or update or delete on public.payments for each row execute function app.guard_payment_settlement_member();

create function public.record_member_payment(p_commitment uuid,p_member uuid,p_amount bigint,p_type public.payment_type,p_paid_now boolean,p_date date)
returns uuid language plpgsql security invoker set search_path='' as $$
declare c public.commitments%rowtype; result uuid;
begin
 select * into c from public.commitments where id=p_commitment and deleted_at is null for update;
 if not found or not app.has_role(c.project_id,array['organizer','member']::public.member_role[]) or not app.is_writable_project(c.project_id) then raise exception 'orchestr:not_authorized:You cannot record this payment.' using errcode='42501'; end if;
 if p_member is null or not exists(select 1 from public.v_activity_cost_shares where commitment_id=c.id and member_id=p_member) then raise exception 'orchestr:invalid_member:This member has no share in the Activity.' using errcode='42501'; end if;
 if p_date is null or p_paid_now is null then raise exception 'orchestr:invalid_payment:Choose a payment date and timing.'; end if;
 insert into public.payments(project_id,commitment_id,paid_by_member_id,amount_minor,type,direction,status,paid_on,due_on)
 values(c.project_id,c.id,p_member,p_amount,p_type,case when p_type='refund' then 'incoming'::public.payment_direction else 'outgoing' end,
 case when p_paid_now then 'paid'::public.payment_status else 'scheduled' end,case when p_paid_now then p_date end,case when not p_paid_now then p_date end) returning id into result;
 return result;
end $$;
revoke all on function public.record_member_payment(uuid,uuid,bigint,public.payment_type,boolean,date) from public;
grant execute on function public.record_member_payment(uuid,uuid,bigint,public.payment_type,boolean,date) to authenticated;
