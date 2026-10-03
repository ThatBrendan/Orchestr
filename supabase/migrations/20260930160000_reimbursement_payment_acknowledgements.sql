-- A debtor claim is not evidence of receipt. No financial ledger mutation.
create table public.reimbursement_payment_acknowledgements(
 id uuid primary key default gen_random_uuid(),project_id uuid not null,
 reimbursement_request_id uuid not null,debtor_member_id uuid not null,
 created_by_user_id uuid not null references public.users(id),
 acknowledged_at timestamptz not null default clock_timestamp(),withdrawn_at timestamptz,
 unique(project_id,reimbursement_request_id,id),
 foreign key(project_id,reimbursement_request_id) references public.reimbursement_requests(project_id,id),
 foreign key(project_id,debtor_member_id) references public.project_members(project_id,id),
 check(withdrawn_at is null or withdrawn_at>=acknowledged_at)
);
create unique index acknowledgement_one_active on public.reimbursement_payment_acknowledgements(reimbursement_request_id) where withdrawn_at is null;
create index acknowledgement_request_history on public.reimbursement_payment_acknowledgements(reimbursement_request_id,acknowledged_at desc);
alter table public.reimbursement_payment_acknowledgements enable row level security;
alter table public.reimbursement_payment_acknowledgements force row level security;
revoke all on public.reimbursement_payment_acknowledgements from public,anon,authenticated,service_role;
grant select on public.reimbursement_payment_acknowledgements to authenticated;
create policy acknowledgement_read on public.reimbursement_payment_acknowledgements for select to authenticated using(app.can_read_reimbursement(reimbursement_request_id));
create function app.guard_payment_acknowledgement() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='DELETE' then raise exception 'orchestr:immutable_column:Payment-sent history cannot be deleted.'; end if;
 if (to_jsonb(new)-'withdrawn_at') is distinct from (to_jsonb(old)-'withdrawn_at') or old.withdrawn_at is not null or new.withdrawn_at is null then
 raise exception 'orchestr:immutable_column:Undo payment sent instead of editing its history.'; end if;
 return new;
end $$;
create trigger acknowledgement_identity before update or delete on public.reimbursement_payment_acknowledgements for each row execute function app.guard_payment_acknowledgement();
create trigger audit_row after insert or update on public.reimbursement_payment_acknowledgements for each row execute function app.tg_audit_row();
revoke all on function app.guard_payment_acknowledgement() from public,anon,authenticated,service_role;
create function app.has_active_payment_acknowledgement(p_request uuid) returns boolean language sql stable security definer set search_path='' as $$
 select app.can_read_reimbursement(p_request) and exists(select 1 from public.reimbursement_payment_acknowledgements where reimbursement_request_id=p_request and withdrawn_at is null);
$$;
revoke all on function app.has_active_payment_acknowledgement(uuid) from public,anon;
grant execute on function app.has_active_payment_acknowledgement(uuid) to authenticated,service_role;
create function app.can_acknowledge_reimbursement(p_request uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.reimbursement_requests r join public.project_members d on d.id=r.debtor_member_id join public.project_members c on c.id=r.creditor_member_id
 where r.id=p_request and app.can_read_reimbursement(r.id) and app.is_writable_project(r.project_id) and r.status='open'
 and not app.reimbursement_needs_review(r.id) and d.user_id=auth.uid() and d.status='active' and d.deleted_at is null and c.status='active' and c.deleted_at is null);
$$;
revoke all on function app.can_acknowledge_reimbursement(uuid) from public,anon,service_role;
grant execute on function app.can_acknowledge_reimbursement(uuid) to authenticated;
-- This internal lock helper is not a client mutation API.
create function app.lock_acknowledgement_request(p_request uuid) returns public.reimbursement_requests
language plpgsql security definer set search_path='' as $$
declare r public.reimbursement_requests%rowtype;
begin
 select * into r from public.reimbursement_requests where id=p_request;
 if not found or not app.can_read_reimbursement(r.id) or app.current_member_id(r.project_id) is distinct from r.debtor_member_id then raise exception 'orchestr:not_authorized:Only the person who owes this reimbursement can update payment sent.' using errcode='42501'; end if;
 perform 1 from public.commitments where id=r.commitment_id and deleted_at is null for update;
 perform 1 from public.projects where id=r.project_id and deleted_at is null and status<>'archived' for share;
 select * into r from public.reimbursement_requests where id=p_request for update;
 perform 1 from public.project_members where id in(r.debtor_member_id,r.creditor_member_id) order by id for share;
 if not app.can_acknowledge_reimbursement(r.id) then raise exception 'orchestr:not_authorized:This reimbursement is not available for a payment-sent update. Review its current status.' using errcode='42501'; end if;
 return r;
end $$;
revoke all on function app.lock_acknowledgement_request(uuid) from public,anon,authenticated,service_role;
create function public.acknowledge_reimbursement_payment(p_request uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare r public.reimbursement_requests%rowtype; result uuid;
begin
 r:=app.lock_acknowledgement_request(p_request);
 select id into result from public.reimbursement_payment_acknowledgements where reimbursement_request_id=r.id and withdrawn_at is null;
 if found then return result; end if;
 insert into public.reimbursement_payment_acknowledgements(project_id,reimbursement_request_id,debtor_member_id,created_by_user_id)
 values(r.project_id,r.id,r.debtor_member_id,auth.uid()) returning id into result;
 return result;
end $$;
create function public.withdraw_reimbursement_payment_acknowledgement(p_acknowledgement uuid) returns void language plpgsql security definer set search_path='' as $$
declare a public.reimbursement_payment_acknowledgements%rowtype;
begin
 select * into a from public.reimbursement_payment_acknowledgements where id=p_acknowledgement;
 if not found then raise exception 'orchestr:not_authorized:Payment-sent update unavailable.' using errcode='42501'; end if;
 perform app.lock_acknowledgement_request(a.reimbursement_request_id);
 update public.reimbursement_payment_acknowledgements set withdrawn_at=clock_timestamp() where id=a.id and withdrawn_at is null;
end $$;
revoke all on function public.acknowledge_reimbursement_payment(uuid),public.withdraw_reimbursement_payment_acknowledgement(uuid) from public,anon,service_role;
grant execute on function public.acknowledge_reimbursement_payment(uuid),public.withdraw_reimbursement_payment_acknowledgement(uuid) to authenticated;
create view public.v_reimbursement_payment_status with(security_invoker=true) as
 select r.id as reimbursement_request_id,
 (select a.id from public.reimbursement_payment_acknowledgements a where a.reimbursement_request_id=r.id and a.withdrawn_at is null) as active_acknowledgement_id,
 app.can_acknowledge_reimbursement(r.id) and not app.has_active_payment_acknowledgement(r.id) as can_acknowledge,
 app.can_acknowledge_reimbursement(r.id) and app.has_active_payment_acknowledgement(r.id) as can_withdraw,
 coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'acknowledged_at',a.acknowledged_at,'withdrawn_at',a.withdrawn_at) order by a.acknowledged_at desc,a.id desc) from public.reimbursement_payment_acknowledgements a where a.reimbursement_request_id=r.id),'[]'::jsonb) as history
 from public.v_reimbursements r;
revoke all on public.v_reimbursement_payment_status from public,anon,service_role;
grant select on public.v_reimbursement_payment_status to authenticated;
-- Preserve Phase8 validation/read contract and add only the active-claim exclusion.
alter function public.get_reimbursement_payment_options(uuid) rename to get_reimbursement_payment_options_before_acknowledgements;
revoke all on function public.get_reimbursement_payment_options_before_acknowledgements(uuid) from public,anon,authenticated,service_role;
create function public.get_reimbursement_payment_options(p_request uuid)
returns table(id uuid,provider text,payment_url text,display_label text,is_default boolean)
language sql stable security definer set search_path='' as $$
 select * from public.get_reimbursement_payment_options_before_acknowledgements(p_request) where not app.has_active_payment_acknowledgement(p_request);
$$;
revoke all on function public.get_reimbursement_payment_options(uuid) from public,anon,service_role;
grant execute on function public.get_reimbursement_payment_options(uuid) to authenticated;
-- No creditor attention until a confirmation action exists.
alter function app._health_findings(uuid) rename to _health_findings_before_acknowledgements;
create function app._health_findings(p_project uuid)
returns table(code text,severity text,subject_type text,subject_id uuid,subject_label text,params jsonb,message text,resolution text,affects_health boolean,dismissible boolean)
language sql stable security invoker set search_path='' as $$
 select * from app._health_findings_before_acknowledgements(p_project) f where f.code<>'reimbursement_outstanding' or not app.has_active_payment_acknowledgement(f.subject_id);
$$;
revoke all on function app._health_findings(uuid) from public;
grant execute on function app._health_findings(uuid) to authenticated,service_role;
create or replace view public.v_my_reimbursement_notifications with(security_invoker=true) as
 select n.id,n.created_at,n.read_at,r.id as reimbursement_id,r.project_id,r.commitment_id,r.amount_minor,r.currency,r.creditor_name,r.activity_title,r.needs_review
 from public.notifications n join public.v_reimbursements r on r.id=n.reimbursement_id where n.kind='reimbursement_created' and r.status='open' and not app.has_active_payment_acknowledgement(r.id);

insert into app.domain_event_types values('reimbursement.payment_acknowledged','reimbursement_payment_acknowledgement'),('reimbursement.payment_acknowledgement_withdrawn','reimbursement_payment_acknowledgement');
alter table app.automation_rules drop constraint automation_rules_action_type_check;
alter table app.automation_rules add constraint automation_rules_action_type_check check(action_type in('notify_activity_collaborators','notify_join_organizers','notify_approved_requester','notify_decision_managers','notify_decision_members','notify_payment_responsible','notify_reimbursement_debtor','notify_reimbursement_creditor'));
alter table app.automation_rules add constraint acknowledgement_action_event check(action_type<>'notify_reimbursement_creditor' or event_type in('reimbursement.payment_acknowledged','reimbursement.payment_acknowledgement_withdrawn'));
insert into app.automation_rules(id,event_type,condition_handler,action_type) values
 ('acknowledgement_creditor','reimbursement.payment_acknowledged','always','notify_reimbursement_creditor'),
 ('withdrawal_creditor','reimbursement.payment_acknowledgement_withdrawn','always','notify_reimbursement_creditor');
alter table public.notifications add column payment_acknowledgement_id uuid;
alter table public.notifications add constraint notification_acknowledgement_fk foreign key(project_id,reimbursement_id,payment_acknowledgement_id) references public.reimbursement_payment_acknowledgements(project_id,reimbursement_request_id,id);
alter table public.notifications drop constraint notifications_kind_resource;
alter table public.notifications add constraint notifications_kind_resource check(
 (payment_acknowledgement_id is null and (
 (kind='activity_created' and commitment_id is not null and join_request_id is null and decision_id is null and domain_event_id is null and payment_schedule_id is null and reimbursement_id is null)
 or(kind in('project_join_requested','project_member_approved') and commitment_id is null and join_request_id is not null and decision_id is null and domain_event_id is null and payment_schedule_id is null and reimbursement_id is null)
 or(kind in('decision_deadline_reached','decision_resolved') and commitment_id is null and join_request_id is null and decision_id is not null and domain_event_id is not null and payment_schedule_id is null and reimbursement_id is null)
 or(kind='payment_due_soon' and commitment_id is null and join_request_id is null and decision_id is null and domain_event_id is not null and payment_schedule_id is not null and reimbursement_id is null)
 or(kind='reimbursement_created' and commitment_id is null and join_request_id is null and decision_id is null and domain_event_id is not null and payment_schedule_id is null and reimbursement_id is not null)))
 or(kind in('reimbursement_payment_acknowledged','reimbursement_payment_acknowledgement_withdrawn') and commitment_id is null and join_request_id is null and decision_id is null and payment_schedule_id is null and domain_event_id is not null and reimbursement_id is not null and payment_acknowledgement_id is not null));
drop index public.notification_reimbursement_recipient;
create unique index notification_reimbursement_recipient on public.notifications(recipient_user_id,reimbursement_id,kind) where reimbursement_id is not null and payment_acknowledgement_id is null;
create unique index notification_acknowledgement_recipient on public.notifications(recipient_user_id,payment_acknowledgement_id,kind) where payment_acknowledgement_id is not null;
create policy notification_acknowledgement_read on public.notifications for select to authenticated using(kind in('reimbursement_payment_acknowledged','reimbursement_payment_acknowledgement_withdrawn') and recipient_user_id=auth.uid() and app.can_read_reimbursement(reimbursement_id));
create view public.v_my_payment_acknowledgement_notifications with(security_invoker=true) as
 select n.id,n.kind,n.created_at,n.read_at,r.id as reimbursement_id,r.project_id,r.commitment_id,r.amount_minor,r.currency,r.debtor_name,r.activity_title,r.needs_review
 from public.notifications n join public.v_reimbursements r on r.id=n.reimbursement_id join public.reimbursement_payment_acknowledgements a on a.id=n.payment_acknowledgement_id
 where r.status='open' and (
 (n.kind='reimbursement_payment_acknowledged' and a.withdrawn_at is null)
 or(n.kind='reimbursement_payment_acknowledgement_withdrawn' and a.withdrawn_at is not null and not exists(select 1 from public.reimbursement_payment_acknowledgements newer where newer.reimbursement_request_id=r.id and (newer.acknowledged_at,newer.id)>(a.acknowledged_at,a.id))));
revoke all on public.v_my_payment_acknowledgement_notifications from public,anon,service_role;
grant select on public.v_my_payment_acknowledgement_notifications to authenticated;
alter function app.process_domain_event(uuid) rename to process_domain_event_before_acknowledgements;
create function app.process_domain_event(p_event uuid) returns void language plpgsql security definer set search_path='' as $$
declare e app.domain_events%rowtype; rule app.automation_rules%rowtype;
begin
 select * into strict e from app.domain_events where id=p_event for update;
 if e.event_type not in('reimbursement.payment_acknowledged','reimbursement.payment_acknowledgement_withdrawn') then perform app.process_domain_event_before_acknowledgements(p_event); return; end if;
 if exists(select 1 from app.domain_event_processing where event_id=p_event) then return; end if;
 for rule in select * from app.automation_rules where enabled and event_type=e.event_type order by priority,id loop
  if rule.action_type<>'notify_reimbursement_creditor' or rule.condition_handler<>'always' then raise exception 'Unsupported acknowledgement action'; end if;
  insert into public.notifications(project_id,reimbursement_id,payment_acknowledgement_id,domain_event_id,recipient_user_id,kind)
  select r.project_id,r.id,a.id,e.id,m.user_id,replace(e.event_type,'.','_') from public.reimbursement_payment_acknowledgements a
  join public.reimbursement_requests r on r.id=a.reimbursement_request_id join public.project_members m on m.id=r.creditor_member_id
  join public.projects p on p.id=r.project_id join public.commitments c on c.id=r.commitment_id
  where a.id=e.resource_id and r.status='open' and m.status='active' and m.deleted_at is null and m.user_id is not null and m.user_id<>e.actor_user_id and p.deleted_at is null and c.deleted_at is null
  on conflict do nothing;
  insert into app.automation_action_runs(event_id,rule_id) values(e.id,rule.id);
 end loop;
 insert into app.domain_event_processing(event_id) values(e.id);
end $$;
alter function app.emit_domain_event(text,uuid,uuid,jsonb,text) rename to emit_domain_event_before_acknowledgements;
create function app.emit_domain_event(p_type text,p_project uuid,p_resource uuid,p_payload jsonb,p_key text) returns uuid language plpgsql security definer set search_path='' as $$
declare a public.reimbursement_payment_acknowledgements%rowtype; r public.reimbursement_requests%rowtype; e uuid; prior app.domain_events%rowtype;
begin
 if p_type not in('reimbursement.payment_acknowledged','reimbursement.payment_acknowledgement_withdrawn') or p_type is null then return app.emit_domain_event_before_acknowledgements(p_type,p_project,p_resource,p_payload,p_key); end if;
 select * into a from public.reimbursement_payment_acknowledgements where id=p_resource and project_id=p_project;
 if not found then raise exception 'Invalid acknowledgement fact' using errcode='22023'; end if;
 select * into strict r from public.reimbursement_requests where id=a.reimbursement_request_id;
 if not app.can_acknowledge_reimbursement(r.id) or a.created_by_user_id is distinct from auth.uid() or a.debtor_member_id<>r.debtor_member_id
 or p_payload is distinct from jsonb_build_object('activity_id',r.commitment_id,'reimbursement_request_id',r.id)
 or (p_type='reimbursement.payment_acknowledged' and (a.withdrawn_at is not null or p_key is distinct from 'acknowledged'))
 or (p_type='reimbursement.payment_acknowledgement_withdrawn' and (a.withdrawn_at is null or p_key is distinct from 'withdrawn')) then raise exception 'Invalid acknowledgement fact' using errcode='22023'; end if;
 insert into app.domain_events(event_type,project_id,actor_user_id,resource_type,resource_id,payload,deduplication_key)
 values(p_type,p_project,auth.uid(),'reimbursement_payment_acknowledgement',a.id,p_payload,p_key)
 on conflict(event_type,resource_id,deduplication_key) do nothing returning id into e;
 if e is null then
  select * into strict prior from app.domain_events where event_type=p_type and resource_id=p_resource and deduplication_key=p_key;
  if prior.project_id is distinct from p_project or prior.payload is distinct from p_payload or prior.actor_user_id is distinct from auth.uid() then raise exception 'Conflicting acknowledgement event retry'; end if;
  e:=prior.id;
 end if;
 perform app.process_domain_event(e); return e;
end $$;
create function app.tg_acknowledgement_events() returns trigger language plpgsql security definer set search_path='' as $$
declare activity uuid;
begin
 select commitment_id into strict activity from public.reimbursement_requests where id=new.reimbursement_request_id;
 perform app.emit_domain_event(case when tg_op='INSERT' then 'reimbursement.payment_acknowledged' else 'reimbursement.payment_acknowledgement_withdrawn' end,new.project_id,new.id,jsonb_build_object('activity_id',activity,'reimbursement_request_id',new.reimbursement_request_id),case when tg_op='INSERT' then 'acknowledged' else 'withdrawn' end);
 return new;
end $$;
revoke all on function app.process_domain_event(uuid),app.emit_domain_event(text,uuid,uuid,jsonb,text),app.tg_acknowledgement_events() from public,anon,authenticated,service_role;
create trigger acknowledgement_events after insert or update of withdrawn_at on public.reimbursement_payment_acknowledgements for each row execute function app.tg_acknowledgement_events();
