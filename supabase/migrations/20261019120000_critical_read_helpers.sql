-- Reduce measured repeated authorization and confirmed-state planning work.
-- Preserve FORCE RLS, invoker views, helper privileges, and all financial predicates.
-- See ignored BACKEND_SECURITY_AND_DATA.md for measurements and rollback notes.
create or replace function app.can_read_reimbursement(p_id uuid) returns boolean language sql stable security definer set search_path='' as $fn$
select exists(select 1 from public.reimbursement_requests r
join public.projects p on p.id=r.project_id join public.commitments c on c.id=r.commitment_id join public.payments pay on pay.id=r.payment_id
join public.project_members m on m.project_id=r.project_id and m.user_id=auth.uid() and m.status='active' and m.deleted_at is null
where r.id=p_id and p.deleted_at is null and c.deleted_at is null and pay.deleted_at is null
and (m.role='organizer' or m.id in(r.debtor_member_id,r.creditor_member_id)));
$fn$;
create or replace function app.can_confirm_reimbursement(p_ack uuid) returns boolean language plpgsql stable security definer set search_path='' as $fn$
begin
-- This condition is already required by the original predicate. Avoid planning financial views when it is false.
if exists(select 1 from public.reimbursement_payment_acknowledgements a join public.reimbursement_receipt_confirmations f on f.reimbursement_request_id=a.reimbursement_request_id where a.id=p_ack) then return false;end if;
return (select exists(select 1 from public.reimbursement_payment_acknowledgements a
 join public.reimbursement_requests r on r.id=a.reimbursement_request_id
 join public.project_members d on d.id=r.debtor_member_id join public.project_members c on c.id=r.creditor_member_id
 join public.commitments activity on activity.id=r.commitment_id
 where a.id=p_ack and a.withdrawn_at is null and a.debtor_member_id=r.debtor_member_id
 and app.can_read_reimbursement(r.id) and app.is_writable_project(r.project_id) and activity.status<>'cancelled'
 and r.status='open' and not app.reimbursement_needs_review(r.id)
 and c.user_id=auth.uid() and c.status='active' and c.deleted_at is null and d.status='active' and d.deleted_at is null
 and not exists(select 1 from public.reimbursement_receipt_confirmations f where f.reimbursement_request_id=r.id)
 and r.amount_minor<=(select remaining_minor from public.v_activity_member_settlements where commitment_id=r.commitment_id and member_id=r.debtor_member_id)
 and r.amount_minor<=(select -remaining_minor from public.v_activity_member_settlements where commitment_id=r.commitment_id and member_id=r.creditor_member_id)));
end;
$fn$;