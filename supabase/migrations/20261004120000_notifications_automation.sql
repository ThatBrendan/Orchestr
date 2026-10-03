-- Phase 11: recipient-scoped optional delivery. Facts and processing are unaffected.
create table public.user_notification_preferences (
 user_id uuid not null references public.users(id),
 category text not null check(category in ('activities','decisions','payments','reimbursements','project_access')),
 enabled boolean not null check(enabled=false),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 primary key(user_id,category)
);
alter table public.user_notification_preferences enable row level security;
alter table public.user_notification_preferences force row level security;
revoke all on public.user_notification_preferences from public,anon,authenticated,service_role;
grant select on public.user_notification_preferences to authenticated;
create policy preferences_owner on public.user_notification_preferences for select to authenticated using(user_id=auth.uid());
create function public.set_my_notification_preference(p_category text,p_enabled boolean) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if p_category is null or p_category not in ('activities','decisions','payments','reimbursements','project_access') or p_enabled is null then raise exception 'Invalid notification preference' using errcode='22023'; end if;
 if p_enabled then delete from public.user_notification_preferences where user_id=auth.uid() and category=p_category;
 else insert into public.user_notification_preferences(user_id,category,enabled) values(auth.uid(),p_category,false) on conflict(user_id,category) do nothing;
 end if;
end $$;
revoke all on function public.set_my_notification_preference(text,boolean) from public,anon,service_role;
grant execute on function public.set_my_notification_preference(text,boolean) to authenticated;

-- Static registry: migration-reviewed metadata, never executable configuration.
create function app.notification_policy(p_kind text)
returns table(category text,critical boolean,event_type text,action_type text)
language sql immutable set search_path='' as $$
 select category,critical,event_type,action_type from (values
 ('activity_created','activities',false,'activity.created','notify_activity_collaborators'),
 ('activity_due_soon','activities',false,'activity.due_soon','notify_activity_responsible'),
 ('decision_deadline_reached','decisions',false,'decision.deadline_reached','notify_decision_managers'),
 ('decision_resolved','decisions',false,'decision.resolved','notify_decision_members'),
 ('payment_due_soon','payments',false,'payment.due_soon','notify_payment_responsible'),
 ('reimbursement_created','reimbursements',false,'reimbursement.created','notify_reimbursement_debtor'),
 ('reimbursement_payment_acknowledged','reimbursements',true,'reimbursement.payment_acknowledged','notify_reimbursement_creditor'),
 ('reimbursement_payment_acknowledgement_withdrawn','reimbursements',true,'reimbursement.payment_acknowledgement_withdrawn','notify_reimbursement_creditor'),
 ('reimbursement_receipt_confirmed','reimbursements',true,'reimbursement.receipt_confirmed','notify_receipt_debtor'),
 ('project_join_requested','project_access',false,'project.join_requested','notify_join_organizers'),
 ('project_member_approved','project_access',true,'project.member_approved','notify_approved_requester')
 ) v(kind,category,critical,event_type,action_type) where kind=p_kind;
$$;
revoke all on function app.notification_policy(text) from public,anon,authenticated,service_role;
create table app.notification_delivery_receipts (
 event_id uuid not null references app.domain_events(id),
 rule_id text not null references app.automation_rules(id),
 recipient_user_id uuid not null,
 outcome text not null check(outcome in ('delivered','preference_suppressed')),
 notification_id uuid,
 created_at timestamptz not null default clock_timestamp(),
 primary key(event_id,rule_id,recipient_user_id),
 check((outcome='delivered')=(notification_id is not null))
);
alter table app.notification_delivery_receipts enable row level security;
alter table app.notification_delivery_receipts force row level security;
revoke all on app.notification_delivery_receipts from public,anon,authenticated,service_role;
create trigger immutable before update or delete on app.notification_delivery_receipts for each row execute function app.tg_domain_event_immutable();
create function app.tg_notification_delivery() returns trigger language plpgsql security definer set search_path='' as $$
declare policy record; event_uuid uuid; rule_key text; allow_delivery boolean;
begin
 select * into strict policy from app.notification_policy(new.kind);
 -- Legacy Activity/access rows intentionally keep their original nullable event FK contract.
 select e.id into strict event_uuid from app.domain_events e where e.project_id=new.project_id
 and e.event_type=policy.event_type and (e.id=new.domain_event_id or (new.domain_event_id is null and e.resource_id=coalesce(new.commitment_id,new.join_request_id)));
 select r.id into strict rule_key from app.automation_rules r where r.event_type=policy.event_type and r.action_type=policy.action_type and r.enabled;
 if tg_when='AFTER' then
  insert into app.notification_delivery_receipts(event_id,rule_id,recipient_user_id,outcome,notification_id)
  values(event_uuid,rule_key,new.recipient_user_id,'delivered',new.id) on conflict do nothing;
  return new;
 end if;
 -- This is deliberately recipient-scoped; it cannot short-circuit event/rule execution.
 if exists(select 1 from app.notification_delivery_receipts where event_id=event_uuid and rule_id=rule_key and recipient_user_id=new.recipient_user_id) then return null; end if;
 allow_delivery:=policy.critical or not exists(select 1 from public.user_notification_preferences where user_id=new.recipient_user_id and category=policy.category and not enabled);
 if not allow_delivery then
  insert into app.notification_delivery_receipts(event_id,rule_id,recipient_user_id,outcome) values(event_uuid,rule_key,new.recipient_user_id,'preference_suppressed') on conflict do nothing;
  return null;
 end if;
 return new;
end $$;
revoke all on function app.tg_notification_delivery() from public,anon,authenticated,service_role;
create trigger notification_preference before insert on public.notifications for each row execute function app.tg_notification_delivery();
create trigger notification_delivered after insert on public.notifications for each row execute function app.tg_notification_delivery();

-- Known shared assignee-or-Organizer strategy; feature eligibility stays with its handler.
create function app.activity_responsible_recipients(p_activity uuid) returns table(user_id uuid)
language sql stable security definer set search_path='' as $$
 select m.user_id from public.commitments c join public.project_members m on m.project_id=c.project_id
 where c.id=p_activity and m.status='active' and m.deleted_at is null and m.user_id is not null
 and (m.id=c.owner_member_id or (m.role='organizer' and not exists(select 1 from public.project_members owner where owner.id=c.owner_member_id and owner.project_id=c.project_id and owner.status='active' and owner.deleted_at is null and owner.user_id is not null)));
$$;
revoke all on function app.activity_responsible_recipients(uuid) from public,anon,authenticated,service_role;
create function app.activity_due_soon(p_activity uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.commitments c join public.projects p on p.id=c.project_id
 where c.id=p_activity and c.deleted_at is null and c.status not in ('completed','cancelled')
 and p.deleted_at is null and p.status<>'archived' and c.recurrence_frequency is null
 and c.starts_at is not null and isfinite(c.starts_at)
 and (c.starts_at at time zone p.timezone)::date between (statement_timestamp() at time zone p.timezone)::date and (statement_timestamp() at time zone p.timezone)::date+3
 and (c.is_all_day or c.starts_at>=statement_timestamp())
 and exists(select 1 from app.activity_responsible_recipients(c.id)));
$$;
revoke all on function app.activity_due_soon(uuid) from public,anon,authenticated,service_role;
insert into app.domain_event_types values('activity.due_soon','activity');
alter table app.automation_rules drop constraint automation_rules_action_type_check;
alter table app.automation_rules add constraint automation_rules_action_type_check check(action_type in ('notify_activity_collaborators','notify_join_organizers','notify_approved_requester','notify_decision_managers','notify_decision_members','notify_payment_responsible','notify_reimbursement_debtor','notify_reimbursement_creditor','notify_receipt_debtor','notify_activity_responsible'));
alter table app.automation_rules add constraint activity_due_action check(action_type<>'notify_activity_responsible' or event_type='activity.due_soon');
insert into app.automation_rules(id,event_type,condition_handler,action_type) values('activity_due_responsible','activity.due_soon','activity_live','notify_activity_responsible');
alter table public.notifications add column activity_reminder_id uuid;
alter table public.notifications add constraint notification_reminder_fk foreign key(project_id,activity_reminder_id) references public.commitments(project_id,id);
alter table public.notifications add constraint reminder_kind_check check((kind='activity_due_soon')=(activity_reminder_id is not null));
create policy notifications_read_reminder on public.notifications for select to authenticated using(kind='activity_due_soon' and recipient_user_id=auth.uid() and app.is_member(project_id) and exists(select 1 from public.commitments c join public.projects p on p.id=c.project_id where c.id=activity_reminder_id and c.deleted_at is null and p.deleted_at is null));
alter table public.notifications drop constraint notifications_kind_resource;
alter table public.notifications add constraint notifications_kind_resource check(((receipt_confirmation_id is null and ((payment_acknowledgement_id is null and (
 (kind='activity_created' and commitment_id is not null and join_request_id is null and decision_id is null and domain_event_id is null and payment_schedule_id is null and reimbursement_id is null)
 or(kind in('project_join_requested','project_member_approved') and commitment_id is null and join_request_id is not null and decision_id is null and domain_event_id is null and payment_schedule_id is null and reimbursement_id is null)
 or(kind in('decision_deadline_reached','decision_resolved') and commitment_id is null and join_request_id is null and decision_id is not null and domain_event_id is not null and payment_schedule_id is null and reimbursement_id is null)
 or(kind='payment_due_soon' and commitment_id is null and join_request_id is null and decision_id is null and domain_event_id is not null and payment_schedule_id is not null and reimbursement_id is null)
 or(kind='reimbursement_created' and commitment_id is null and join_request_id is null and decision_id is null and domain_event_id is not null and payment_schedule_id is null and reimbursement_id is not null)))
 or(kind in('reimbursement_payment_acknowledged','reimbursement_payment_acknowledgement_withdrawn') and commitment_id is null and join_request_id is null and decision_id is null and payment_schedule_id is null and domain_event_id is not null and reimbursement_id is not null and payment_acknowledgement_id is not null))) or
(kind='reimbursement_receipt_confirmed' and receipt_confirmation_id is not null and reimbursement_id is not null and domain_event_id is not null and payment_acknowledgement_id is null and commitment_id is null and join_request_id is null and decision_id is null and payment_schedule_id is null)) or (kind='activity_due_soon' and commitment_id is null and activity_reminder_id is not null and domain_event_id is not null and join_request_id is null and decision_id is null and payment_schedule_id is null and reimbursement_id is null and payment_acknowledgement_id is null and receipt_confirmation_id is null));
-- Preserve legacy view shape; upcoming notifications have their own projection.
create or replace view public.v_my_activity_notifications with(security_invoker=true) as
 select n.id,n.project_id,n.commitment_id,n.created_at,n.read_at,c.title activity_title,p.name project_name
 from public.notifications n join public.commitments c on c.id=n.commitment_id and c.project_id=n.project_id join public.projects p on p.id=n.project_id
 where n.kind='activity_created' and n.recipient_user_id=auth.uid() and app.is_member(n.project_id) and c.deleted_at is null and p.deleted_at is null;

alter function app.process_domain_event(uuid) rename to process_domain_event_before_phase11;
create function app.process_domain_event(p_event uuid) returns void language plpgsql security definer set search_path='' as $$
declare e app.domain_events%rowtype; r app.automation_rules%rowtype;
begin
 select * into strict e from app.domain_events where id=p_event for update;
 if e.event_type<>'activity.due_soon' then perform app.process_domain_event_before_phase11(p_event); return; end if;
 if exists(select 1 from app.domain_event_processing where event_id=e.id) then return; end if;
 for r in select * from app.automation_rules where enabled and event_type=e.event_type order by priority,id loop
  if r.action_type<>'notify_activity_responsible' or r.condition_handler<>'activity_live' then raise exception 'Unsupported Activity reminder action'; end if;
  if app.activity_due_soon(e.resource_id) and exists(select 1 from public.commitments c where c.id=e.resource_id and e.deduplication_key='start:'||extract(epoch from c.starts_at)::text||':3') then
   insert into public.notifications(project_id,activity_reminder_id,domain_event_id,recipient_user_id,kind)
   select e.project_id,e.resource_id,e.id,m.user_id,'activity_due_soon' from app.activity_responsible_recipients(e.resource_id) m on conflict do nothing;
  end if;
  insert into app.automation_action_runs(event_id,rule_id) values(e.id,r.id);
 end loop;
 insert into app.domain_event_processing(event_id) values(e.id);
end $$;
alter function app.emit_domain_event(text,uuid,uuid,jsonb,text) rename to emit_domain_event_before_phase11;
create function app.emit_domain_event(p_type text,p_project uuid,p_resource uuid,p_payload jsonb,p_key text) returns uuid language plpgsql security definer set search_path='' as $$
declare c public.commitments%rowtype; event_uuid uuid;
begin
 if p_type is distinct from 'activity.due_soon' then return app.emit_domain_event_before_phase11(p_type,p_project,p_resource,p_payload,p_key); end if;
 select * into c from public.commitments where id=p_resource and project_id=p_project;
 if not found or auth.uid() is not null or not app.activity_due_soon(c.id) or p_payload is distinct from '{}'::jsonb or p_key is distinct from 'start:'||extract(epoch from c.starts_at)::text||':3' then raise exception 'Invalid Activity reminder fact' using errcode='22023'; end if;
 insert into app.domain_events(event_type,project_id,resource_type,resource_id,payload,deduplication_key) values(p_type,p_project,'activity',c.id,'{}',p_key) on conflict(event_type,resource_id,deduplication_key) do nothing returning id into event_uuid;
 if event_uuid is null then select id into strict event_uuid from app.domain_events where event_type=p_type and resource_id=p_resource and deduplication_key=p_key and project_id=p_project and payload='{}'; end if;
 perform app.process_domain_event(event_uuid); return event_uuid;
end $$;
revoke all on function app.process_domain_event(uuid),app.emit_domain_event(text,uuid,uuid,jsonb,text) from public,anon,authenticated,service_role;

create table app.scheduled_evaluator_runs (
 id bigint generated always as identity primary key,
 evaluator text not null check(evaluator in ('decision_deadlines','payment_schedule_due_soon','activity_due_soon')),
 resource_id uuid,
 emitted_count integer not null default 0,
 error_code text,
 created_at timestamptz not null default clock_timestamp()
);
alter table app.scheduled_evaluator_runs enable row level security;
alter table app.scheduled_evaluator_runs force row level security;
revoke all on app.scheduled_evaluator_runs from public,anon,authenticated,service_role;
create trigger immutable before update or delete on app.scheduled_evaluator_runs for each row execute function app.tg_domain_event_immutable();
create function app.evaluate_activity_due_soon() returns integer language plpgsql security definer set search_path='' as $$
declare candidate record; c public.commitments%rowtype; n integer:=0;
begin
 if auth.uid() is not null then raise exception 'Trusted scheduler context required' using errcode='42501'; end if;
 for candidate in select q.id,q.project_id from public.commitments q where app.activity_due_soon(q.id)
 and not exists(select 1 from app.domain_events e where e.event_type='activity.due_soon' and e.resource_id=q.id and e.deduplication_key='start:'||extract(epoch from q.starts_at)::text||':3') order by q.starts_at,q.id limit 100 loop
  begin
   perform 1 from public.projects where id=candidate.project_id and deleted_at is null and status<>'archived' for update skip locked;
   if not found then continue; end if;
   select * into c from public.commitments where id=candidate.id for update skip locked;
   if not found or not app.activity_due_soon(c.id) then continue; end if;
   perform app.emit_domain_event('activity.due_soon',c.project_id,c.id,'{}','start:'||extract(epoch from c.starts_at)::text||':3'); n:=n+1;
  exception when others then
   insert into app.scheduled_evaluator_runs(evaluator,resource_id,error_code) values('activity_due_soon',candidate.id,sqlstate);
  end;
 end loop;
 return n;
end $$;
revoke all on function app.evaluate_activity_due_soon() from public,anon,authenticated,service_role;

create or replace function app.evaluate_decision_deadlines() returns integer language plpgsql security definer set search_path='' as $$
declare candidate record; d public.decisions%rowtype; n integer:=0; begin
 if auth.uid() is not null then raise exception 'Trusted scheduler context required' using errcode='42501'; end if;
 for candidate in select q.id,q.project_id from public.decisions q join public.projects p on p.id=q.project_id
  where q.status='open' and q.deleted_at is null and p.deleted_at is null and p.status<>'archived' and q.voting_deadline<=clock_timestamp()
   and not exists(select 1 from app.domain_events e where e.event_type='decision.deadline_reached' and e.resource_id=q.id and e.deduplication_key='deadline:'||q.deadline_version)
  order by q.voting_deadline,q.id limit 100 loop
  begin
  perform 1 from public.projects where id=candidate.project_id and deleted_at is null and status<>'archived' for update skip locked;
  if not found then continue; end if;
  select * into d from public.decisions where id=candidate.id and deleted_at is null and status='open' and voting_deadline<=clock_timestamp() for update skip locked;
  if not found then continue; end if;
  perform app.emit_domain_event('decision.deadline_reached',d.project_id,d.id,'{}','deadline:'||d.deadline_version); n:=n+1;
  exception when others then
   insert into app.scheduled_evaluator_runs(evaluator,resource_id,error_code) values('decision_deadlines',candidate.id,sqlstate);
  end;
 end loop;
 return n;
end $$;

create or replace function app.evaluate_payment_schedule_deadlines() returns integer language plpgsql security definer set search_path='' as $$
declare candidate record; s public.activity_payment_schedules%rowtype; n integer:=0;
begin
 if auth.uid() is not null then raise exception 'Trusted scheduler context required' using errcode='42501'; end if;
 for candidate in select q.id,q.project_id,q.commitment_id from public.activity_payment_schedules q
 where q.deleted_at is null and app.payment_schedule_due(q.id)
 and not exists(select 1 from app.domain_events e where e.event_type='payment.due_soon' and e.resource_id=q.id and e.deduplication_key='due:'||q.due_on||':7')
 order by q.due_on,q.id limit 100 loop
  begin
  perform 1 from public.projects where id=candidate.project_id and deleted_at is null and status<>'archived' for update skip locked;
  if not found then continue; end if;
  perform 1 from public.commitments where id=candidate.commitment_id and deleted_at is null for update skip locked;
  if not found then continue; end if;
  select * into s from public.activity_payment_schedules where id=candidate.id and deleted_at is null for update skip locked;
  if not found or not app.payment_schedule_due(s.id) then continue; end if;
  perform app.emit_domain_event('payment.due_soon',s.project_id,s.id,jsonb_build_object('activity_id',s.commitment_id),'due:'||s.due_on||':7');
  n:=n+1;
  exception when others then
   insert into app.scheduled_evaluator_runs(evaluator,resource_id,error_code) values('payment_schedule_due_soon',candidate.id,sqlstate);
  end;
 end loop;
 return n;
end $$;
create or replace function app.evaluate_scheduled_domain_events() returns void language plpgsql security definer set search_path='' as $$
declare evaluator text; n integer;
begin
 if auth.uid() is not null then raise exception 'Trusted scheduler context required' using errcode='42501'; end if;
 foreach evaluator in array array['decision_deadlines','payment_schedule_due_soon','activity_due_soon'] loop
  begin
   case evaluator
    when 'decision_deadlines' then n:=app.evaluate_decision_deadlines();
    when 'payment_schedule_due_soon' then n:=app.evaluate_payment_schedule_deadlines();
    when 'activity_due_soon' then n:=app.evaluate_activity_due_soon();
   end case;
   insert into app.scheduled_evaluator_runs(evaluator,emitted_count) values(evaluator,n);
  exception when others then
   insert into app.scheduled_evaluator_runs(evaluator,error_code) values(evaluator,sqlstate);
  end;
 end loop;
end $$;


alter table public.user_notification_preferences add column id uuid not null default gen_random_uuid() unique;
create trigger audit after insert or delete on public.user_notification_preferences for each row execute function app.tg_audit_row();

-- One authorized destination contract, with existing feature-specific visibility intact.
create view public.v_my_notification_inbox with(security_invoker=true) as
 select id,project_id,created_at,read_at,'activity_created'::text kind,'activities'::text category,
 'activity'::text resource_type,commitment_id resource_id,null::text section,'New activity'::text title,
 activity_title||' was added to '||project_name||'.' body from public.v_my_activity_notifications
 union all select id,project_id,created_at,read_at,kind,'project_access','project',project_id,
 case when kind='project_join_requested' then 'people' else null end,
 case when kind='project_join_requested' then 'New project access request' else 'Your access was approved' end,project_name from public.v_my_join_notifications
 union all select id,project_id,created_at,read_at,kind,'decisions','decision',decision_id,null,
 case when kind='decision_resolved' then 'Decision resolved' else 'Voting closed' end,
 decision_title||case when kind='decision_resolved' then ' — '||coalesce(selected_title,'An option')||' was selected.' else ' — Ready to resolve.' end from public.v_my_decision_notifications
 union all select id,project_id,created_at,read_at,'payment_due_soon','payments','activity',commitment_id,'payments',
 case when outstanding_minor>0 then 'Payment due soon' else 'Payment completed' end,title||' — Due '||to_char(due_on,'FMDD Month YYYY') from public.v_my_payment_notifications
 union all select id,project_id,created_at,read_at,'reimbursement_created','reimbursements','activity',commitment_id,'reimbursements',
 case when needs_review then 'Reimbursement needs review' else 'Reimbursement requested' end,activity_title||' — '||creditor_name from public.v_my_reimbursement_notifications
 union all select id,project_id,created_at,read_at,kind,'reimbursements','activity',commitment_id,'reimbursements',
 case when needs_review then 'Reimbursement needs review' when kind='reimbursement_payment_acknowledged' then 'Payment marked as sent' else 'Payment claim withdrawn' end,
 activity_title||' — '||debtor_name from public.v_my_payment_acknowledgement_notifications
 union all select id,project_id,created_at,read_at,'reimbursement_receipt_confirmed','reimbursements','activity',commitment_id,'reimbursements',
 case when confirmation_state='reversed' then 'Settlement reversed' else 'Reimbursement settled' end,activity_title||' — '||creditor_name from public.v_my_receipt_confirmation_notifications
 union all select n.id,n.project_id,n.created_at,n.read_at,n.kind,'activities','activity',c.id,null,
 'Activity coming up',c.title||' — '||to_char(c.starts_at at time zone p.timezone,'FMDD Month YYYY')
 from public.notifications n join public.commitments c on c.id=n.activity_reminder_id join public.projects p on p.id=n.project_id
 where n.kind='activity_due_soon' and c.deleted_at is null and p.deleted_at is null and c.status<>'cancelled';
revoke all on public.v_my_notification_inbox from public,anon,service_role;
grant select on public.v_my_notification_inbox to authenticated;
create index notifications_recipient_cursor on public.notifications(recipient_user_id,created_at desc,id desc);
create function public.mark_all_notifications_read() returns integer language plpgsql security invoker set search_path='' as $$
declare affected integer;
begin
 update public.notifications set read_at=now() where recipient_user_id=auth.uid() and read_at is null and id in(select id from public.v_my_notification_inbox);
 get diagnostics affected=row_count; return affected;
end $$;
create or replace function public.mark_notification_read(p_notification uuid) returns uuid language plpgsql security invoker set search_path='' as $$
declare result uuid;
begin
 update public.notifications set read_at=coalesce(read_at,now()) where id=p_notification and recipient_user_id=auth.uid() and id in(select id from public.v_my_notification_inbox) returning id into result;
 return result;
end $$;
revoke all on function public.mark_all_notifications_read() from public,anon,service_role;
grant execute on function public.mark_all_notifications_read() to authenticated;
