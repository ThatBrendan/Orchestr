-- Creditor confirmation links workflow provenance to the existing paired ledger.
create table public.reimbursement_receipt_confirmations (
 id uuid primary key default gen_random_uuid(), project_id uuid not null,
 reimbursement_request_id uuid not null unique, acknowledgement_id uuid not null unique,
 creditor_member_id uuid not null, settlement_group_id uuid not null unique,
 confirmed_at timestamptz not null default clock_timestamp(), created_by_user_id uuid not null references public.users(id),
 unique(project_id,reimbursement_request_id,id),
 foreign key(project_id,reimbursement_request_id) references public.reimbursement_requests(project_id,id),
 foreign key(project_id,reimbursement_request_id,acknowledgement_id) references public.reimbursement_payment_acknowledgements(project_id,reimbursement_request_id,id),
 foreign key(project_id,creditor_member_id) references public.project_members(project_id,id)
);
alter table public.reimbursement_receipt_confirmations enable row level security;
alter table public.reimbursement_receipt_confirmations force row level security;
revoke all on public.reimbursement_receipt_confirmations from public,anon,authenticated,service_role;
grant select on public.reimbursement_receipt_confirmations to authenticated;
create policy confirmation_read on public.reimbursement_receipt_confirmations for select to authenticated using(app.can_read_reimbursement(reimbursement_request_id));
create function app.guard_receipt_confirmation() returns trigger language plpgsql set search_path='' as $$
begin raise exception 'orchestr:immutable_column:Receipt confirmation is historical. Correct the settlement instead.'; end $$;
revoke all on function app.guard_receipt_confirmation() from public,anon,authenticated,service_role;
create trigger confirmation_immutable before update or delete on public.reimbursement_receipt_confirmations for each row execute function app.guard_receipt_confirmation();
create trigger audit_row after insert on public.reimbursement_receipt_confirmations for each row execute function app.tg_audit_row();
-- Only exact pair inserts supported by a trusted confirmation gain creditor authority.
create function app.is_confirmation_payment(p public.payments) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.reimbursement_receipt_confirmations f join public.reimbursement_requests r on r.id=f.reimbursement_request_id
 join public.reimbursement_payment_acknowledgements a on a.id=f.acknowledgement_id
 where f.settlement_group_id=p.settlement_group_id and f.project_id=p.project_id and r.commitment_id=p.commitment_id
 and r.amount_minor=p.amount_minor and r.status='open' and a.withdrawn_at is null
 and f.created_by_user_id=auth.uid() and f.creditor_member_id=app.current_member_id(r.project_id)
 and p.status='paid' and p.deleted_at is null and p.payment_schedule_id is null and p.paid_on=current_date
 and ((p.direction='outgoing' and p.type='full' and p.paid_by_member_id=r.debtor_member_id)
 or(p.direction='incoming' and p.type='refund' and p.paid_by_member_id=r.creditor_member_id)));
$$;
revoke all on function app.is_confirmation_payment(public.payments) from public,anon,authenticated,service_role;
-- Preserve paired settlement history during normal project soft deletion. No balance calculation changes.
create or replace function app.guard_settlement_identity() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='UPDATE' and old.settlement_group_id is distinct from new.settlement_group_id then raise exception 'orchestr:immutable_column:Settlement identity cannot change.'; end if;
 -- Only the existing project cascade may change deletion lifecycle after hiding memberships.
 if tg_op='UPDATE' and pg_trigger_depth()>1
 and (to_jsonb(new)-array['deleted_at','updated_at'])=(to_jsonb(old)-array['deleted_at','updated_at'])
 and exists(select 1 from public.projects p where p.id=new.project_id
   and (p.deleted_at is not null or (old.deleted_at is not null and new.deleted_at is null))) then return new; end if;
 if new.settlement_group_id is not null then
  if not app.is_organizer(new.project_id) and not (tg_op='INSERT' and app.is_confirmation_payment(new)) then raise exception 'orchestr:not_authorized:Only an organizer can record settlements.' using errcode='42501'; end if;
  if tg_op='UPDATE' and (new.amount_minor,new.direction,new.paid_by_member_id,new.commitment_id,new.type,new.paid_on) is distinct from (old.amount_minor,old.direction,old.paid_by_member_id,old.commitment_id,old.type,old.paid_on) and not (new.status='cancelled' and new.paid_on is null and (new.amount_minor,new.direction,new.paid_by_member_id,new.commitment_id,new.type) is not distinct from (old.amount_minor,old.direction,old.paid_by_member_id,old.commitment_id,old.type)) then raise exception 'orchestr:immutable_column:Cancel the settlement before recording a correction.'; end if;
 end if;
 return new;
end $$;

-- Normal project deletion must preserve and hide attributed payment history.
create or replace function app.guard_payment_settlement_member() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 -- Serialize financial edits with future completion checks.
 if tg_op='UPDATE' and new.commitment_id is distinct from old.commitment_id then
  raise exception 'orchestr:immutable_column:A Payment cannot move to another Activity.';
 end if;
 perform 1 from public.commitments where id=coalesce(new.commitment_id,old.commitment_id) for update;
 if tg_op='DELETE' then return old; end if;
 -- The existing project cascade hides memberships before updating payments.
 -- Permit only its lifecycle-only changes; attribution and monetary fields
 -- remain immutable here and all direct member checks below remain intact.
 if tg_op='UPDATE' and pg_trigger_depth()>1
  and (to_jsonb(new)-array['status','deleted_at','updated_at'])=(to_jsonb(old)-array['status','deleted_at','updated_at'])
  and (new.status=old.status or (old.status='scheduled' and new.status='cancelled'))
  and exists(select 1 from public.projects p where p.id=new.project_id
    and (p.deleted_at is not null or (old.deleted_at is not null and new.deleted_at is null))) then
  return new;
 end if;
 if auth.uid() is not null and not app.is_organizer(new.project_id) and not (tg_op='INSERT' and app.is_confirmation_payment(new)) then
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
create function app.record_item_settlement(p_item uuid,p_from uuid,p_to uuid,p_amount bigint,p_date date,p_group uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare c public.commitments%rowtype; g uuid:=p_group; owed bigint; credit bigint;
begin
 select * into c from public.commitments where id=p_item and deleted_at is null for update;
 if not found or not app.is_writable_project(c.project_id) then raise exception 'orchestr:not_authorized:Activity is unavailable for settlement.' using errcode='42501'; end if;
 select remaining_minor into owed from public.v_activity_member_settlements where commitment_id=p_item and member_id=p_from;
 select -remaining_minor into credit from public.v_activity_member_settlements where commitment_id=p_item and member_id=p_to;
 if p_from=p_to or p_date is null or p_amount is null or p_amount<=0 or p_amount>coalesce(owed,0) or p_amount>coalesce(credit,0) then raise exception 'orchestr:invalid_settlement:Choose an outstanding share and a person owed this amount.'; end if;
 insert into public.payments(project_id,commitment_id,type,direction,status,amount_minor,paid_on,paid_by_member_id,settlement_group_id)
 values(c.project_id,c.id,'full','outgoing','paid',p_amount,p_date,p_from,g),(c.project_id,c.id,'refund','incoming','paid',p_amount,p_date,p_to,g);
 return g;
end $$;
revoke all on function app.record_item_settlement(uuid,uuid,uuid,bigint,date,uuid) from public,anon,authenticated,service_role;
create or replace function public.record_item_settlement(p_item uuid,p_from uuid,p_to uuid,p_amount bigint,p_date date)
returns uuid language plpgsql security invoker set search_path='' as $$
declare c public.commitments%rowtype;
begin
 select * into c from public.commitments where id=p_item and deleted_at is null for update;
 if not found or not app.is_organizer(c.project_id) or not app.is_writable_project(c.project_id) then raise exception 'orchestr:not_authorized:Only an organizer can record settlements.' using errcode='42501'; end if;
 return app.record_item_settlement(p_item,p_from,p_to,p_amount,p_date,gen_random_uuid());
end $$;
-- The wrapper must compose a private helper while retaining its explicit role check.
alter function public.record_item_settlement(uuid,uuid,uuid,bigint,date) security definer;
alter table public.reimbursement_requests drop constraint reimbursement_requests_status_check;
alter table public.reimbursement_requests add constraint reimbursement_requests_status_check check(status in('open','cancelled','settled'));
alter table public.reimbursement_requests drop constraint reimbursement_requests_check1;
alter table public.reimbursement_requests add constraint reimbursement_cancellation_state check((status in('open','settled') and cancelled_at is null and cancelled_by is null) or(status='cancelled' and cancelled_at is not null and cancelled_by is not null));
create or replace function app.guard_reimbursement_identity() returns trigger
language plpgsql set search_path='' as $$
begin
 if tg_op='DELETE' then raise exception 'orchestr:immutable_column:Reimbursement history cannot be deleted.'; end if;
 if (to_jsonb(new)-array['status','cancelled_by','cancelled_at','updated_at']) is distinct from (to_jsonb(old)-array['status','cancelled_by','cancelled_at','updated_at'])
 or old.status<>'open' or new.status not in('cancelled','settled')
 or (new.status='settled' and not exists(select 1 from public.reimbursement_receipt_confirmations f where f.reimbursement_request_id=old.id))
 or (new.status='cancelled' and exists(select 1 from public.reimbursement_receipt_confirmations f where f.reimbursement_request_id=old.id)) then
 raise exception 'orchestr:immutable_column:Cancel and recreate a reimbursement to correct it.'; end if;
 new.updated_at:=now(); return new;
end $$;
create or replace function app.tg_reimbursement_events() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='UPDATE' and new.status='settled' then return new; end if;
 perform app.emit_domain_event(case when tg_op='INSERT' then 'reimbursement.created' else 'reimbursement.cancelled' end,new.project_id,new.id,jsonb_build_object('activity_id',new.commitment_id,'payment_id',new.payment_id),case when tg_op='INSERT' then 'created' else 'cancelled' end);
 return new;
end $$;
create or replace function public.cancel_reimbursement(p_request uuid) returns void
language plpgsql security definer set search_path='' as $$
declare r public.reimbursement_requests%rowtype;
begin
 select * into r from public.reimbursement_requests where id=p_request;
 if not found then raise exception 'orchestr:not_authorized:Reimbursement unavailable.' using errcode='42501'; end if;
 perform 1 from public.commitments where id=r.commitment_id and deleted_at is null for update;
 if not found or not app.can_read_reimbursement(r.id) or not app.has_role(r.project_id,array['organizer','member']::public.member_role[])
 or not (app.is_organizer(r.project_id) or app.current_member_id(r.project_id)=r.creditor_member_id) then
 raise exception 'orchestr:not_authorized:You cannot cancel this reimbursement.' using errcode='42501'; end if;
 perform 1 from public.projects where id=r.project_id and deleted_at is null and status<>'archived' for share;
 if not found then raise exception 'orchestr:project_archived:This project is read-only.' using errcode='42501'; end if;
 if exists(select 1 from public.reimbursement_receipt_confirmations where reimbursement_request_id=r.id) then raise exception 'orchestr:reimbursement_confirmed:Correct the settlement instead of cancelling a confirmed reimbursement.' using errcode='42501'; end if;
 update public.reimbursement_requests set status='cancelled',cancelled_at=now(),cancelled_by=app.current_member_id(r.project_id) where id=r.id and status='open';
end $$;
create function app.can_confirm_reimbursement(p_ack uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.reimbursement_payment_acknowledgements a
 join public.reimbursement_requests r on r.id=a.reimbursement_request_id
 join public.project_members d on d.id=r.debtor_member_id join public.project_members c on c.id=r.creditor_member_id
 join public.commitments activity on activity.id=r.commitment_id
 where a.id=p_ack and a.withdrawn_at is null and a.debtor_member_id=r.debtor_member_id
 and app.can_read_reimbursement(r.id) and app.is_writable_project(r.project_id) and activity.status<>'cancelled'
 and r.status='open' and not app.reimbursement_needs_review(r.id)
 and c.user_id=auth.uid() and c.status='active' and c.deleted_at is null and d.status='active' and d.deleted_at is null
 and not exists(select 1 from public.reimbursement_receipt_confirmations f where f.reimbursement_request_id=r.id)
 and r.amount_minor<=(select remaining_minor from public.v_activity_member_settlements where commitment_id=r.commitment_id and member_id=r.debtor_member_id)
 and r.amount_minor<=(select -remaining_minor from public.v_activity_member_settlements where commitment_id=r.commitment_id and member_id=r.creditor_member_id));
$$;
revoke all on function app.can_confirm_reimbursement(uuid) from public,anon,service_role;
grant execute on function app.can_confirm_reimbursement(uuid) to authenticated;
create function app.validate_confirmation_pair() returns trigger language plpgsql security definer set search_path='' as $$
declare r public.reimbursement_requests%rowtype; a public.reimbursement_payment_acknowledgements%rowtype; valid boolean; n integer;
begin
 select * into strict r from public.reimbursement_requests where id=new.reimbursement_request_id;
 select * into strict a from public.reimbursement_payment_acknowledgements where id=new.acknowledgement_id;
 select count(*),bool_and(p.project_id=r.project_id and p.commitment_id=r.commitment_id and p.amount_minor=r.amount_minor and
 ((p.type='full' and p.direction='outgoing' and p.paid_by_member_id=r.debtor_member_id) or
 (p.type='refund' and p.direction='incoming' and p.paid_by_member_id=r.creditor_member_id)))
 into n,valid from public.payments p where settlement_group_id=new.settlement_group_id;
 if n<>2 or not coalesce(valid,false) or r.status<>'settled' or new.creditor_member_id<>r.creditor_member_id or a.withdrawn_at is not null then
 raise exception 'orchestr:invalid_confirmation:Confirmation must link one matching settlement pair and active claim.'; end if;
 return null;
end $$;
revoke all on function app.validate_confirmation_pair() from public,anon,authenticated,service_role;
create constraint trigger confirmation_pair after insert on public.reimbursement_receipt_confirmations deferrable initially deferred for each row execute function app.validate_confirmation_pair();
create function public.confirm_reimbursement_receipt(p_acknowledgement uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare a public.reimbursement_payment_acknowledgements%rowtype; r public.reimbursement_requests%rowtype; result uuid; g uuid:=gen_random_uuid();
begin
 select * into a from public.reimbursement_payment_acknowledgements where id=p_acknowledgement;
 if not found then raise exception 'orchestr:not_authorized:Receipt confirmation unavailable.' using errcode='42501'; end if;
 select * into strict r from public.reimbursement_requests where id=a.reimbursement_request_id;
 if not app.can_read_reimbursement(r.id) or app.current_member_id(r.project_id) is distinct from r.creditor_member_id then raise exception 'orchestr:not_authorized:Only the creditor can confirm receipt.' using errcode='42501'; end if;
 perform 1 from public.commitments where id=r.commitment_id and deleted_at is null for update;
 if not found then raise exception 'orchestr:not_authorized:Activity unavailable.' using errcode='42501'; end if;
 perform 1 from public.projects where id=r.project_id and deleted_at is null and status<>'archived' for share;
 if not found then raise exception 'orchestr:project_archived:This project is read-only.' using errcode='42501'; end if;
 select * into r from public.reimbursement_requests where id=r.id for update;
 select * into a from public.reimbursement_payment_acknowledgements where id=p_acknowledgement for update;
 perform 1 from public.project_members where id in(r.debtor_member_id,r.creditor_member_id) order by id for share;
 if not app.can_read_reimbursement(r.id) or app.current_member_id(r.project_id) is distinct from r.creditor_member_id
 or (select count(*) from public.project_members where id in(r.debtor_member_id,r.creditor_member_id) and status='active' and deleted_at is null)<>2 then raise exception 'orchestr:not_authorized:Both participants must be active.' using errcode='42501'; end if;
 select id into result from public.reimbursement_receipt_confirmations where acknowledgement_id=a.id;
 if found then return result; end if;
 if not app.can_confirm_reimbursement(a.id) then raise exception 'orchestr:reimbursement_review:This reimbursement needs review before it can be confirmed. Check the current request and payment-sent status.' using errcode='42501'; end if;
 -- A private immutable authorization row precedes the pair so existing guards can
 -- validate this creditor's precise transfer. Deferred integrity requires the pair.
 insert into public.reimbursement_receipt_confirmations(project_id,reimbursement_request_id,acknowledgement_id,creditor_member_id,settlement_group_id,created_by_user_id)
 values(r.project_id,r.id,a.id,r.creditor_member_id,g,auth.uid()) returning id into result;
 perform app.record_item_settlement(r.commitment_id,r.debtor_member_id,r.creditor_member_id,r.amount_minor,current_date,g);
 update public.reimbursement_requests set status='settled' where id=r.id;
 perform app.emit_domain_event('reimbursement.receipt_confirmed',r.project_id,result,jsonb_build_object('activity_id',r.commitment_id,'reimbursement_request_id',r.id,'acknowledgement_id',a.id),'confirmed');
 return result;
end $$;
revoke all on function public.confirm_reimbursement_receipt(uuid) from public,anon,service_role;
grant execute on function public.confirm_reimbursement_receipt(uuid) to authenticated;
create or replace function app.guard_payment_acknowledgement() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='DELETE' then raise exception 'orchestr:immutable_column:Payment-sent history cannot be deleted.'; end if;
 if exists(select 1 from public.reimbursement_receipt_confirmations where acknowledgement_id=old.id)
 or (to_jsonb(new)-'withdrawn_at') is distinct from (to_jsonb(old)-'withdrawn_at') or old.withdrawn_at is not null or new.withdrawn_at is null then
 raise exception 'orchestr:immutable_column:Confirmed payment-sent history cannot be edited.'; end if;
 return new;
end $$;
create or replace view public.v_reimbursement_payment_status with(security_invoker=true) as
 select r.id as reimbursement_request_id,
 (select a.id from public.reimbursement_payment_acknowledgements a where a.reimbursement_request_id=r.id and a.withdrawn_at is null) as active_acknowledgement_id,
 app.can_acknowledge_reimbursement(r.id) and not app.has_active_payment_acknowledgement(r.id) as can_acknowledge,
 app.can_acknowledge_reimbursement(r.id) and app.has_active_payment_acknowledgement(r.id) as can_withdraw,
 coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'acknowledged_at',a.acknowledged_at,'withdrawn_at',a.withdrawn_at) order by a.acknowledged_at desc,a.id desc) from public.reimbursement_payment_acknowledgements a where a.reimbursement_request_id=r.id),'[]'::jsonb) as history,
 f.id as confirmation_id,f.confirmed_at,
 case when f.id is null then null when exists(select 1 from public.payments p where p.settlement_group_id=f.settlement_group_id and p.status='cancelled') then 'reversed' else 'settled' end as confirmation_state,
 coalesce((select app.can_confirm_reimbursement(a.id) from public.reimbursement_payment_acknowledgements a where a.reimbursement_request_id=r.id and a.withdrawn_at is null),false) as can_confirm
 from public.v_reimbursements r left join public.reimbursement_receipt_confirmations f on f.reimbursement_request_id=r.id;
alter function app._health_findings(uuid) rename to _health_findings_before_confirmations;
create function app._health_findings(p_project uuid)
returns table(code text,severity text,subject_type text,subject_id uuid,subject_label text,params jsonb,message text,resolution text,affects_health boolean,dismissible boolean)
language sql stable security invoker set search_path='' as $$
 select * from app._health_findings_before_confirmations(p_project)
 union all
 select 'reimbursement_confirmation','warning','reimbursement',r.id,r.activity_title,jsonb_build_object('activity_id',r.commitment_id),
 r.debtor_name||' says they have paid '||app.format_money(r.amount_minor,r.currency)||'.','Confirm whether you have received it.',false,false
 from public.v_reimbursements r join public.reimbursement_payment_acknowledgements a on a.reimbursement_request_id=r.id
 where r.project_id=p_project and app.can_confirm_reimbursement(a.id);
$$;
revoke all on function app._health_findings(uuid) from public;
grant execute on function app._health_findings(uuid) to authenticated,service_role;

insert into app.domain_event_types values('reimbursement.receipt_confirmed','reimbursement_receipt_confirmation');
alter table app.automation_rules drop constraint automation_rules_action_type_check;
alter table app.automation_rules add constraint automation_rules_action_type_check check(action_type in('notify_activity_collaborators','notify_join_organizers','notify_approved_requester','notify_decision_managers','notify_decision_members','notify_payment_responsible','notify_reimbursement_debtor','notify_reimbursement_creditor','notify_receipt_debtor'));
alter table app.automation_rules add constraint receipt_action_event check(action_type<>'notify_receipt_debtor' or event_type='reimbursement.receipt_confirmed');
insert into app.automation_rules(id,event_type,condition_handler,action_type) values('receipt_debtor','reimbursement.receipt_confirmed','always','notify_receipt_debtor');
alter table public.notifications add column receipt_confirmation_id uuid;
alter table public.notifications add constraint notification_receipt_fk foreign key(project_id,reimbursement_id,receipt_confirmation_id) references public.reimbursement_receipt_confirmations(project_id,reimbursement_request_id,id);
alter table public.notifications drop constraint notifications_kind_resource;
alter table public.notifications add constraint notifications_kind_resource check((receipt_confirmation_id is null and ((payment_acknowledgement_id is null and (
 (kind='activity_created' and commitment_id is not null and join_request_id is null and decision_id is null and domain_event_id is null and payment_schedule_id is null and reimbursement_id is null)
 or(kind in('project_join_requested','project_member_approved') and commitment_id is null and join_request_id is not null and decision_id is null and domain_event_id is null and payment_schedule_id is null and reimbursement_id is null)
 or(kind in('decision_deadline_reached','decision_resolved') and commitment_id is null and join_request_id is null and decision_id is not null and domain_event_id is not null and payment_schedule_id is null and reimbursement_id is null)
 or(kind='payment_due_soon' and commitment_id is null and join_request_id is null and decision_id is null and domain_event_id is not null and payment_schedule_id is not null and reimbursement_id is null)
 or(kind='reimbursement_created' and commitment_id is null and join_request_id is null and decision_id is null and domain_event_id is not null and payment_schedule_id is null and reimbursement_id is not null)))
 or(kind in('reimbursement_payment_acknowledged','reimbursement_payment_acknowledgement_withdrawn') and commitment_id is null and join_request_id is null and decision_id is null and payment_schedule_id is null and domain_event_id is not null and reimbursement_id is not null and payment_acknowledgement_id is not null))) or
(kind='reimbursement_receipt_confirmed' and receipt_confirmation_id is not null and reimbursement_id is not null and domain_event_id is not null and payment_acknowledgement_id is null and commitment_id is null and join_request_id is null and decision_id is null and payment_schedule_id is null));
create unique index notification_receipt_recipient on public.notifications(recipient_user_id,receipt_confirmation_id) where receipt_confirmation_id is not null;
create policy notification_receipt_read on public.notifications for select to authenticated using(kind='reimbursement_receipt_confirmed' and recipient_user_id=auth.uid() and app.can_read_reimbursement(reimbursement_id));
create view public.v_my_receipt_confirmation_notifications with(security_invoker=true) as
 select n.id,n.created_at,n.read_at,r.id as reimbursement_id,r.project_id,r.commitment_id,r.amount_minor,r.currency,r.creditor_name,r.activity_title,s.confirmation_state
 from public.notifications n join public.v_reimbursements r on r.id=n.reimbursement_id join public.v_reimbursement_payment_status s on s.reimbursement_request_id=r.id
 where n.kind='reimbursement_receipt_confirmed';
revoke all on public.v_my_receipt_confirmation_notifications from public,anon,service_role;
grant select on public.v_my_receipt_confirmation_notifications to authenticated;
alter function app.process_domain_event(uuid) rename to process_domain_event_before_confirmations;
create function app.process_domain_event(p_event uuid) returns void language plpgsql security definer set search_path='' as $$
declare e app.domain_events%rowtype; rule app.automation_rules%rowtype;
begin
 select * into strict e from app.domain_events where id=p_event for update;
 if e.event_type<>'reimbursement.receipt_confirmed' then perform app.process_domain_event_before_confirmations(p_event); return; end if;
 if exists(select 1 from app.domain_event_processing where event_id=p_event) then return; end if;
 for rule in select * from app.automation_rules where enabled and event_type=e.event_type order by priority,id loop
  if rule.action_type<>'notify_receipt_debtor' or rule.condition_handler<>'always' then raise exception 'Unsupported receipt action'; end if;
  insert into public.notifications(project_id,reimbursement_id,receipt_confirmation_id,domain_event_id,recipient_user_id,kind)
  select r.project_id,r.id,f.id,e.id,m.user_id,'reimbursement_receipt_confirmed' from public.reimbursement_receipt_confirmations f
  join public.reimbursement_requests r on r.id=f.reimbursement_request_id join public.project_members m on m.id=r.debtor_member_id
  where f.id=e.resource_id and r.status='settled' and m.status='active' and m.deleted_at is null and m.user_id<>e.actor_user_id
  on conflict do nothing;
  insert into app.automation_action_runs(event_id,rule_id) values(e.id,rule.id);
 end loop;
 insert into app.domain_event_processing(event_id) values(e.id);
end $$;
alter function app.emit_domain_event(text,uuid,uuid,jsonb,text) rename to emit_domain_event_before_confirmations;
create function app.emit_domain_event(p_type text,p_project uuid,p_resource uuid,p_payload jsonb,p_key text) returns uuid language plpgsql security definer set search_path='' as $$
declare f public.reimbursement_receipt_confirmations%rowtype; r public.reimbursement_requests%rowtype; e uuid; prior app.domain_events%rowtype;
begin
 if p_type is distinct from 'reimbursement.receipt_confirmed' then return app.emit_domain_event_before_confirmations(p_type,p_project,p_resource,p_payload,p_key); end if;
 select * into f from public.reimbursement_receipt_confirmations where id=p_resource and project_id=p_project;
 if not found then raise exception 'Invalid receipt fact' using errcode='22023'; end if;
 select * into strict r from public.reimbursement_requests where id=f.reimbursement_request_id;
 if f.created_by_user_id is distinct from auth.uid() or not app.can_read_reimbursement(r.id) or r.status<>'settled'
 or p_key is distinct from 'confirmed' or p_payload is distinct from jsonb_build_object('activity_id',r.commitment_id,'reimbursement_request_id',r.id,'acknowledgement_id',f.acknowledgement_id)
 or (select count(*) from public.payments where settlement_group_id=f.settlement_group_id and status='paid')<>2 then raise exception 'Invalid receipt fact' using errcode='22023'; end if;
 insert into app.domain_events(event_type,project_id,actor_user_id,resource_type,resource_id,payload,deduplication_key)
 values(p_type,p_project,auth.uid(),'reimbursement_receipt_confirmation',f.id,p_payload,p_key)
 on conflict(event_type,resource_id,deduplication_key) do nothing returning id into e;
 if e is null then
 select * into strict prior from app.domain_events where event_type=p_type and resource_id=p_resource and deduplication_key=p_key;
 if prior.project_id is distinct from p_project or prior.payload is distinct from p_payload or prior.actor_user_id is distinct from auth.uid() then raise exception 'Conflicting receipt retry'; end if;
 e:=prior.id;
 end if;
 perform app.process_domain_event(e); return e;
end $$;
revoke all on function app.process_domain_event(uuid),app.emit_domain_event(text,uuid,uuid,jsonb,text) from public,anon,authenticated,service_role;
