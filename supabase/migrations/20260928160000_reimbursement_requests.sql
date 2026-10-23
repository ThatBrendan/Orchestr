-- Explicit workflow snapshots over the existing Activity settlement mathematics.
-- No existing financial view, cost-share rule, payment ledger or settlement RPC changes.
alter table public.payments add constraint payments_project_identity unique(project_id,id);
create table public.reimbursement_requests (
 id uuid primary key default gen_random_uuid(),
 project_id uuid not null references public.projects(id),
 commitment_id uuid not null,
 payment_id uuid not null,
 debtor_member_id uuid not null,
 creditor_member_id uuid not null,
 amount_minor bigint not null check(amount_minor>0),
 status text not null default 'open' check(status in ('open','cancelled')),
 basis_hash text not null,
 created_by uuid not null references public.project_members(id),
 cancelled_by uuid references public.project_members(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 cancelled_at timestamptz,
 unique(project_id,id),
 foreign key(project_id,commitment_id) references public.commitments(project_id,id),
 foreign key(project_id,payment_id) references public.payments(project_id,id),
 foreign key(project_id,debtor_member_id) references public.project_members(project_id,id),
 foreign key(project_id,creditor_member_id) references public.project_members(project_id,id),
 check(debtor_member_id<>creditor_member_id),
 check((status='open' and cancelled_at is null and cancelled_by is null) or (status='cancelled' and cancelled_at is not null and cancelled_by is not null))
);
create unique index reimbursement_open_source_member on public.reimbursement_requests(payment_id,debtor_member_id,creditor_member_id) where status='open';
create index reimbursement_activity on public.reimbursement_requests(commitment_id,status);
create index reimbursement_parties on public.reimbursement_requests(project_id,debtor_member_id,creditor_member_id);
alter table public.reimbursement_requests enable row level security;
alter table public.reimbursement_requests force row level security;
revoke all on public.reimbursement_requests from public,anon,authenticated,service_role;
grant select on public.reimbursement_requests to authenticated;

-- Fingerprint the existing engine's results; do not recompute responsibility or net payments.
create function app.reimbursement_basis(p_activity uuid) returns text
language sql stable security definer set search_path='' as $$
 select md5(coalesce(jsonb_agg(jsonb_build_array(s.member_id,s.allocated_minor,s.paid_minor,s.remaining_minor) order by s.member_id)::text,'[]'))
 from public.v_activity_member_settlements s where s.commitment_id=p_activity;
$$;
revoke all on function app.reimbursement_basis(uuid) from public,anon,authenticated,service_role;
create function app.can_read_reimbursement(p_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.reimbursement_requests r
 join public.projects p on p.id=r.project_id join public.commitments c on c.id=r.commitment_id
 join public.payments pay on pay.id=r.payment_id
 where r.id=p_id and app.is_member(r.project_id) and p.deleted_at is null and c.deleted_at is null and pay.deleted_at is null
 and (app.is_organizer(r.project_id) or app.current_member_id(r.project_id) in (r.debtor_member_id,r.creditor_member_id)));
$$;
revoke all on function app.can_read_reimbursement(uuid) from public,anon,service_role;
grant execute on function app.can_read_reimbursement(uuid) to authenticated;
create policy reimbursement_read on public.reimbursement_requests for select to authenticated using(app.can_read_reimbursement(id));
create function app.guard_reimbursement_identity() returns trigger
language plpgsql set search_path='' as $$
begin
 if tg_op='DELETE' then raise exception 'orchestr:immutable_column:Reimbursement history cannot be deleted.'; end if;
 if (to_jsonb(new)-array['status','cancelled_by','cancelled_at','updated_at']) is distinct from (to_jsonb(old)-array['status','cancelled_by','cancelled_at','updated_at'])
 or old.status='cancelled' or new.status<>'cancelled' then
 raise exception 'orchestr:immutable_column:Cancel and recreate a reimbursement to correct it.'; end if;
 new.updated_at:=now(); return new;
end $$;
revoke all on function app.guard_reimbursement_identity() from public,anon,authenticated,service_role;
create trigger reimbursement_identity before update or delete on public.reimbursement_requests for each row execute function app.guard_reimbursement_identity();
create trigger audit_row after insert or update on public.reimbursement_requests for each row execute function app.tg_audit_row();

-- Explicit access predicate, as with the existing member-directory definer view.
-- The fingerprint is internal and is not returned by the application read model.
create function app.reimbursement_needs_review(p_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select case when app.can_read_reimbursement(p_id) then exists(select 1 from public.reimbursement_requests r where r.id=p_id and r.status='open' and r.basis_hash is distinct from app.reimbursement_basis(r.commitment_id)) else false end;
$$;
revoke all on function app.reimbursement_needs_review(uuid) from public,anon,service_role;
grant execute on function app.reimbursement_needs_review(uuid) to authenticated;
create view public.v_reimbursements with(security_invoker=false) as
 select r.id,r.project_id,r.commitment_id,r.payment_id,r.debtor_member_id,r.creditor_member_id,
 r.amount_minor,r.status,r.created_at,r.cancelled_at,pay.amount_minor as source_amount_minor,pay.paid_on as source_paid_on,c.title as activity_title,p.currency,
 coalesce(du.display_name,dm.display_name) as debtor_name,coalesce(cu.display_name,cm.display_name) as creditor_name,
 app.reimbursement_needs_review(r.id) as needs_review,
 (app.has_role(r.project_id,array['organizer','member']::public.member_role[]) and (app.is_organizer(r.project_id) or app.current_member_id(r.project_id)=r.creditor_member_id) and app.is_writable_project(r.project_id) and r.status='open') as can_cancel,
 app.current_member_id(r.project_id)=r.debtor_member_id as is_debtor,
 app.current_member_id(r.project_id)=r.creditor_member_id as is_creditor
 from public.reimbursement_requests r join public.payments pay on pay.id=r.payment_id join public.commitments c on c.id=r.commitment_id join public.projects p on p.id=r.project_id
 join public.project_members dm on dm.id=r.debtor_member_id join public.project_members cm on cm.id=r.creditor_member_id
 left join public.users du on du.id=dm.user_id left join public.users cu on cu.id=cm.user_id
 where app.can_read_reimbursement(r.id);
revoke all on public.v_reimbursements from public,anon,service_role;
grant select on public.v_reimbursements to authenticated;

-- Same owed/credit bounds used by record_item_settlement; only workflow reservations are new.
-- Deterministic suggestion ordering is a selection policy, not new balance mathematics.
create function public.get_reimbursement_suggestions(p_payment uuid)
returns table(payment_id uuid,commitment_id uuid,debtor_member_id uuid,debtor_name text,creditor_member_id uuid,creditor_name text,amount_minor bigint)
language plpgsql stable security definer set search_path='' as $$
declare pay public.payments%rowtype; budget bigint; credit bigint; reserved bigint; candidate record; proposed bigint;
begin
 select * into pay from public.payments where id=p_payment and deleted_at is null and status='paid' and direction='outgoing' and settlement_group_id is null and paid_by_member_id is not null;
 if not found or not app.has_role(pay.project_id,array['organizer','member']::public.member_role[]) or not app.is_writable_project(pay.project_id)
 or not (app.is_organizer(pay.project_id) or pay.paid_by_member_id=app.current_member_id(pay.project_id))
 or not exists(select 1 from public.commitments where id=pay.commitment_id and deleted_at is null)
 or not exists(select 1 from public.project_members where id=pay.paid_by_member_id and project_id=pay.project_id and status='active' and deleted_at is null) then
 raise exception 'orchestr:not_authorized:Select an actual payment you are allowed to request reimbursement for.' using errcode='42501'; end if;
 if exists(select 1 from public.reimbursement_requests r where r.commitment_id=pay.commitment_id and r.status='open' and r.basis_hash is distinct from app.reimbursement_basis(pay.commitment_id)) then
 raise exception 'orchestr:reimbursement_review:Balances changed. Cancel and recreate the existing reimbursement requests first.'; end if;
 select -s.remaining_minor,s.display_name into credit,creditor_name from public.v_activity_member_settlements s where s.commitment_id=pay.commitment_id and s.member_id=pay.paid_by_member_id;
 select coalesce(sum(r.amount_minor),0) into reserved from public.reimbursement_requests r where r.commitment_id=pay.commitment_id and r.creditor_member_id=pay.paid_by_member_id and r.status='open';
 budget:=least(greatest(coalesce(credit,0)-reserved,0),pay.amount_minor-(select coalesce(sum(r.amount_minor),0) from public.reimbursement_requests r where r.payment_id=pay.id and r.status='open'));
 for candidate in
 select s.member_id,s.display_name,greatest(s.remaining_minor-(select coalesce(sum(r.amount_minor),0) from public.reimbursement_requests r where r.commitment_id=pay.commitment_id and r.debtor_member_id=s.member_id and r.status='open'),0)::bigint as available
 from public.v_activity_member_settlements s join public.project_members m on m.id=s.member_id
 where s.commitment_id=pay.commitment_id and s.member_id<>pay.paid_by_member_id and s.remaining_minor>0 and m.status='active' and m.deleted_at is null
 and not exists(select 1 from public.reimbursement_requests r where r.payment_id=pay.id and r.debtor_member_id=s.member_id and r.status='open') order by s.member_id
 loop
  proposed:=least(candidate.available,budget);
  if proposed>0 then
   payment_id:=pay.id; commitment_id:=pay.commitment_id; debtor_member_id:=candidate.member_id; debtor_name:=candidate.display_name; creditor_member_id:=pay.paid_by_member_id; amount_minor:=proposed;
   return next; budget:=budget-proposed;
  end if;
 end loop;
end $$;
revoke all on function public.get_reimbursement_suggestions(uuid) from public,anon,service_role;
grant execute on function public.get_reimbursement_suggestions(uuid) to authenticated;

create function public.create_reimbursement(p_payment uuid,p_debtor uuid,p_amount bigint) returns uuid
language plpgsql security definer set search_path='' as $$
declare pay public.payments%rowtype; prior public.reimbursement_requests%rowtype; allowed bigint; result uuid;
begin
 -- Match existing financial lock order (Activity, then payment/member rows).
 select * into pay from public.payments where id=p_payment;
 if not found then raise exception 'orchestr:not_authorized:Payment unavailable.' using errcode='42501'; end if;
 perform 1 from public.commitments where id=pay.commitment_id and deleted_at is null for update;
 if not found then raise exception 'orchestr:not_authorized:Activity unavailable.' using errcode='42501'; end if;
 perform 1 from public.projects where id=pay.project_id and deleted_at is null and status<>'archived' for share;
 if not found then raise exception 'orchestr:project_archived:This project is read-only.' using errcode='42501'; end if;
 select * into pay from public.payments where id=p_payment for share;
 if not app.has_role(pay.project_id,array['organizer','member']::public.member_role[]) or not (app.is_organizer(pay.project_id) or pay.paid_by_member_id=app.current_member_id(pay.project_id))
 or pay.deleted_at is not null or pay.status<>'paid' or pay.direction<>'outgoing' or pay.settlement_group_id is not null or pay.paid_by_member_id is null then
 raise exception 'orchestr:not_authorized:Select an actual payment you are allowed to request reimbursement for.' using errcode='42501'; end if;
 perform 1 from public.project_members where project_id=pay.project_id and id in (p_debtor,pay.paid_by_member_id) and status='active' and deleted_at is null order by id for share;
 if p_debtor=pay.paid_by_member_id or (select count(*) from public.project_members where project_id=pay.project_id and id in(p_debtor,pay.paid_by_member_id) and status='active' and deleted_at is null)<>2 then
 raise exception 'orchestr:invalid_member:Choose another active participant in this Activity.' using errcode='42501'; end if;
 select * into prior from public.reimbursement_requests r where r.payment_id=pay.id and r.debtor_member_id=p_debtor and r.status='open';
 if found then
  if prior.amount_minor is distinct from p_amount then raise exception 'orchestr:reimbursement_duplicate:An open reimbursement already exists. Cancel it before changing the amount.'; end if;
  return prior.id;
 end if;
 select s.amount_minor into allowed from public.get_reimbursement_suggestions(pay.id) s where s.debtor_member_id=p_debtor;
 if p_amount is null or p_amount<=0 or p_amount>coalesce(allowed,0) then raise exception 'orchestr:reimbursement_amount:Choose an amount within the current reimbursement suggestion.'; end if;
 insert into public.reimbursement_requests(project_id,commitment_id,payment_id,debtor_member_id,creditor_member_id,amount_minor,basis_hash,created_by)
 values(pay.project_id,pay.commitment_id,pay.id,p_debtor,pay.paid_by_member_id,p_amount,app.reimbursement_basis(pay.commitment_id),app.current_member_id(pay.project_id)) returning id into result;
 return result;
end $$;
create function public.cancel_reimbursement(p_request uuid) returns void
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
 update public.reimbursement_requests set status='cancelled',cancelled_at=now(),cancelled_by=app.current_member_id(r.project_id) where id=r.id and status='open';
end $$;
revoke all on function public.create_reimbursement(uuid,uuid,bigint),public.cancel_reimbursement(uuid) from public,anon,service_role;
grant execute on function public.create_reimbursement(uuid,uuid,bigint),public.cancel_reimbursement(uuid) to authenticated;

-- Extend the event pipeline by delegating all existing handlers unchanged.
insert into app.domain_event_types values('reimbursement.created','reimbursement'),('reimbursement.cancelled','reimbursement');
alter table app.automation_rules drop constraint automation_rules_action_type_check;
alter table app.automation_rules add constraint automation_rules_action_type_check check(action_type in('notify_activity_collaborators','notify_join_organizers','notify_approved_requester','notify_decision_managers','notify_decision_members','notify_payment_responsible','notify_reimbursement_debtor'));
alter table app.automation_rules add constraint reimbursement_action_event check(action_type<>'notify_reimbursement_debtor' or event_type='reimbursement.created');
insert into app.automation_rules(id,event_type,condition_handler,action_type) values('reimbursement_debtor','reimbursement.created','always','notify_reimbursement_debtor');
alter table public.notifications add column reimbursement_id uuid;
alter table public.notifications add constraint notification_reimbursement_fk foreign key(project_id,reimbursement_id) references public.reimbursement_requests(project_id,id);
alter table public.notifications drop constraint notifications_kind_resource;
alter table public.notifications add constraint notifications_kind_resource check(
 (kind='activity_created' and commitment_id is not null and join_request_id is null and decision_id is null and domain_event_id is null and payment_schedule_id is null and reimbursement_id is null)
 or(kind in('project_join_requested','project_member_approved') and commitment_id is null and join_request_id is not null and decision_id is null and domain_event_id is null and payment_schedule_id is null and reimbursement_id is null)
 or(kind in('decision_deadline_reached','decision_resolved') and commitment_id is null and join_request_id is null and decision_id is not null and domain_event_id is not null and payment_schedule_id is null and reimbursement_id is null)
 or(kind='payment_due_soon' and commitment_id is null and join_request_id is null and decision_id is null and domain_event_id is not null and payment_schedule_id is not null and reimbursement_id is null)
 or(kind='reimbursement_created' and commitment_id is null and join_request_id is null and decision_id is null and domain_event_id is not null and payment_schedule_id is null and reimbursement_id is not null));
create unique index notification_reimbursement_recipient on public.notifications(recipient_user_id,reimbursement_id,kind) where reimbursement_id is not null;
create policy notification_reimbursement_read on public.notifications for select to authenticated using(kind='reimbursement_created' and recipient_user_id=auth.uid() and app.can_read_reimbursement(reimbursement_id));
create view public.v_my_reimbursement_notifications with(security_invoker=true) as
 select n.id,n.created_at,n.read_at,r.id as reimbursement_id,r.project_id,r.commitment_id,r.amount_minor,r.currency,r.creditor_name,r.activity_title,r.needs_review
 from public.notifications n join public.v_reimbursements r on r.id=n.reimbursement_id where n.kind='reimbursement_created' and r.status='open';
revoke all on public.v_my_reimbursement_notifications from public,anon,service_role;
grant select on public.v_my_reimbursement_notifications to authenticated;

alter function app.process_domain_event(uuid) rename to process_domain_event_before_reimbursements;
create function app.process_domain_event(p_event uuid) returns void language plpgsql security definer set search_path='' as $$
declare e app.domain_events%rowtype; rule app.automation_rules%rowtype;
begin
 select * into strict e from app.domain_events where id=p_event for update;
 if e.event_type not in('reimbursement.created','reimbursement.cancelled') then perform app.process_domain_event_before_reimbursements(p_event); return; end if;
 if exists(select 1 from app.domain_event_processing where event_id=p_event) then return; end if;
 for rule in select * from app.automation_rules where enabled and event_type=e.event_type order by priority,id loop
  if rule.action_type<>'notify_reimbursement_debtor' then raise exception 'Unsupported reimbursement action'; end if;
  insert into public.notifications(project_id,reimbursement_id,domain_event_id,recipient_user_id,kind)
  select r.project_id,r.id,e.id,m.user_id,'reimbursement_created' from public.reimbursement_requests r
  join public.project_members m on m.id=r.debtor_member_id join public.projects p on p.id=r.project_id join public.commitments c on c.id=r.commitment_id
  where r.id=e.resource_id and r.status='open' and m.status='active' and m.deleted_at is null and m.user_id is not null and p.deleted_at is null and c.deleted_at is null
  on conflict do nothing;
  insert into app.automation_action_runs(event_id,rule_id) values(e.id,rule.id);
 end loop;
 insert into app.domain_event_processing(event_id) values(e.id);
end $$;
alter function app.emit_domain_event(text,uuid,uuid,jsonb,text) rename to emit_domain_event_before_reimbursements;
create function app.emit_domain_event(p_type text,p_project uuid,p_resource uuid,p_payload jsonb,p_key text) returns uuid language plpgsql security definer set search_path='' as $$
declare r public.reimbursement_requests%rowtype; e uuid; prior app.domain_events%rowtype;
begin
 if p_type not in('reimbursement.created','reimbursement.cancelled') or p_type is null then return app.emit_domain_event_before_reimbursements(p_type,p_project,p_resource,p_payload,p_key); end if;
 select * into r from public.reimbursement_requests where id=p_resource and project_id=p_project;
 if not found or not app.can_read_reimbursement(r.id) or auth.uid() is null
 or not app.has_role(r.project_id,array['organizer','member']::public.member_role[])
 or not (app.is_organizer(r.project_id) or app.current_member_id(r.project_id)=r.creditor_member_id)
 or not app.is_writable_project(r.project_id)
 or p_payload is distinct from jsonb_build_object('activity_id',r.commitment_id,'payment_id',r.payment_id)
 or (p_type='reimbursement.created' and (r.status<>'open' or p_key<>'created'))
 or (p_type='reimbursement.cancelled' and (r.status<>'cancelled' or p_key<>'cancelled')) then raise exception 'Invalid reimbursement fact' using errcode='22023'; end if;
 insert into app.domain_events(event_type,project_id,actor_user_id,resource_type,resource_id,payload,deduplication_key)
 values(p_type,p_project,auth.uid(),'reimbursement',r.id,p_payload,p_key)
 on conflict(event_type,resource_id,deduplication_key) do nothing returning id into e;
 if e is null then
  select * into strict prior from app.domain_events where event_type=p_type and resource_id=p_resource and deduplication_key=p_key;
  if prior.project_id is distinct from p_project or prior.payload is distinct from p_payload then raise exception 'Conflicting reimbursement event retry'; end if;
  e:=prior.id;
 end if;
 perform app.process_domain_event(e); return e;
end $$;
create function app.tg_reimbursement_events() returns trigger language plpgsql security definer set search_path='' as $$
begin
 perform app.emit_domain_event(case when tg_op='INSERT' then 'reimbursement.created' else 'reimbursement.cancelled' end,new.project_id,new.id,jsonb_build_object('activity_id',new.commitment_id,'payment_id',new.payment_id),case when tg_op='INSERT' then 'created' else 'cancelled' end);
 return new;
end $$;
revoke all on function app.process_domain_event(uuid),app.emit_domain_event(text,uuid,uuid,jsonb,text),app.tg_reimbursement_events() from public,anon,authenticated,service_role;
create trigger reimbursement_events after insert or update of status on public.reimbursement_requests for each row execute function app.tg_reimbursement_events();

alter function app._health_findings(uuid) rename to _health_findings_before_reimbursements;
create function app._health_findings(p_project uuid)
returns table(code text,severity text,subject_type text,subject_id uuid,subject_label text,params jsonb,message text,resolution text,affects_health boolean,dismissible boolean)
language sql stable security invoker set search_path='' as $$
 select * from app._health_findings_before_reimbursements(p_project)
 union all
 select 'reimbursement_outstanding','warning','reimbursement',r.id,r.activity_title,
 jsonb_build_object('activity_id',r.commitment_id),
 'You owe '||r.creditor_name||' '||app.format_money(r.amount_minor,r.currency)||'.',
 r.activity_title||' reimbursement is outstanding.',false,false
 from public.v_reimbursements r join public.projects p on p.id=r.project_id
 where r.project_id=p_project and r.status='open' and not r.needs_review and r.is_debtor and p.status<>'archived';
$$;
revoke all on function app._health_findings(uuid) from public;
grant execute on function app._health_findings(uuid) to authenticated,service_role;
