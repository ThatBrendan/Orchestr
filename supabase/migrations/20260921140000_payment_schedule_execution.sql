alter table public.activity_payment_schedules add constraint payment_schedule_finite_date check(isfinite(due_on));
create or replace function app.guard_activity_payment_schedule()
returns trigger language plpgsql security definer set search_path='' as $$
declare
  c public.commitments%rowtype;
  scheduled_total bigint;
  net_paid bigint;
begin
  if auth.uid() is not null and not app.has_role(new.project_id,array['organizer','member']::public.member_role[]) then
    raise exception 'orchestr:not_authorized:Schedule unavailable.' using errcode='42501'; end if;
  select * into c
  from public.commitments
  where id = coalesce(new.commitment_id, old.commitment_id)
  for update;
  if not found or c.deleted_at is not null or c.project_id is distinct from new.project_id then
    raise exception 'orchestr:not_authorized:Activity unavailable.' using errcode='42501';
  end if;
  if not app.is_writable_project(c.project_id) then
    raise exception 'orchestr:project_archived:This project is read-only.' using errcode='P0001';
  end if;
  if tg_op = 'UPDATE' and (new.commitment_id is distinct from old.commitment_id or new.project_id is distinct from old.project_id or new.id is distinct from old.id or new.created_at is distinct from old.created_at) then
    raise exception 'orchestr:immutable_column:A payment schedule cannot move to another Activity.' using errcode='P0001';
  end if;
  if tg_op = 'UPDATE' and old.deleted_at is null and old.amount_minor is distinct from new.amount_minor then
    select coalesce(sum(case when p.direction='outgoing' then p.amount_minor else -p.amount_minor end),0)::bigint
      into net_paid
      from public.payments p
     where p.payment_schedule_id = old.id and p.status='paid' and p.deleted_at is null;
    if new.amount_minor < greatest(net_paid, 0) then
      raise exception 'orchestr:invalid_payment_schedule:The amount cannot be less than the net paid amount.';
    end if;
  end if;
  if tg_op <> 'DELETE' and new.deleted_at is null then
    select coalesce(sum(s.amount_minor),0)::bigint into scheduled_total
      from public.activity_payment_schedules s
     where s.commitment_id = new.commitment_id and s.deleted_at is null and s.id <> new.id;
    if scheduled_total + new.amount_minor > app.effective_commitment_cost(c.actual_cost_minor,c.confirmed_cost_minor,c.estimated_cost_minor) then
      raise exception 'orchestr:invalid_payment_schedule:Payments cannot exceed the Activity cost.';
    end if;
  end if;
  if tg_op = 'UPDATE' and old.deleted_at is null and new.deleted_at is not null and exists (
    select 1 from public.payments p where p.payment_schedule_id=old.id
  ) then
    raise exception 'orchestr:invalid_payment_schedule:This payment cannot be deleted because it has payment history.';
  end if;
  return coalesce(new, old);
end $$;

-- Narrow domain delete avoids exposing deleted rows through SELECT policies.
create function public.soft_delete_payment_schedule(p_schedule uuid) returns void
language plpgsql security definer set search_path='' as $$
declare s public.activity_payment_schedules%rowtype;
begin
 select * into s from public.activity_payment_schedules where id=p_schedule and deleted_at is null;
 if not found or not app.has_role(s.project_id,array['organizer','member']::public.member_role[]) or not app.is_writable_project(s.project_id) then
  raise exception 'orchestr:not_authorized:Schedule unavailable.' using errcode='42501'; end if;
 perform 1 from public.commitments where id=s.commitment_id and deleted_at is null for update;
 if not found then raise exception 'orchestr:not_authorized:Activity unavailable.' using errcode='42501'; end if;
 update public.activity_payment_schedules set deleted_at=now() where id=s.id and deleted_at is null;
end $$;
revoke all on function public.soft_delete_payment_schedule(uuid) from public,anon,service_role;
grant execute on function public.soft_delete_payment_schedule(uuid) to authenticated;

-- Phase 6 execution: one scheduled-event pipeline, seven project-local days.
-- Date values are part of the key: changing back to an already-notified date does not resend.
insert into app.domain_event_types values ('payment.due_soon','payment_schedule');
alter table app.automation_rules drop constraint automation_rules_action_type_check;
alter table app.automation_rules add constraint automation_rules_action_type_check check(action_type in ('notify_activity_collaborators','notify_join_organizers','notify_approved_requester','notify_decision_managers','notify_decision_members','notify_payment_responsible'));
alter table app.automation_rules add constraint automation_rules_payment_event_check check(action_type<>'notify_payment_responsible' or event_type='payment.due_soon');
insert into app.automation_rules(id,event_type,condition_handler,action_type) values ('payment_due_responsible','payment.due_soon','always','notify_payment_responsible');

alter table public.notifications add column payment_schedule_id uuid;
alter table public.notifications add constraint notifications_schedule_fk foreign key(project_id,payment_schedule_id) references public.activity_payment_schedules(project_id,id);
alter table public.notifications drop constraint notifications_kind_resource;
alter table public.notifications add constraint notifications_kind_resource check(
 (kind='activity_created' and commitment_id is not null and join_request_id is null and decision_id is null and domain_event_id is null and payment_schedule_id is null)
 or (kind in ('project_join_requested','project_member_approved') and commitment_id is null and join_request_id is not null and decision_id is null and domain_event_id is null and payment_schedule_id is null)
 or (kind in ('decision_deadline_reached','decision_resolved') and commitment_id is null and join_request_id is null and decision_id is not null and domain_event_id is not null and payment_schedule_id is null)
 or (kind='payment_due_soon' and commitment_id is null and join_request_id is null and decision_id is null and domain_event_id is not null and payment_schedule_id is not null));
create policy notifications_read_payment on public.notifications for select to authenticated using (
 kind='payment_due_soon' and recipient_user_id=auth.uid() and app.is_member(project_id)
 and exists(select 1 from public.activity_payment_schedules s join public.commitments c on c.id=s.commitment_id join public.projects p on p.id=s.project_id where s.id=payment_schedule_id and s.deleted_at is null and c.deleted_at is null and p.deleted_at is null));
create view public.v_my_payment_notifications with(security_invoker=true) as
 select n.id,n.project_id,n.created_at,n.read_at,s.commitment_id,s.title,s.due_on,
 s.outstanding_minor,p.currency
 from public.notifications n join public.v_activity_payment_schedule_financials s on s.payment_schedule_id=n.payment_schedule_id
 join public.projects p on p.id=n.project_id where n.kind='payment_due_soon' and p.deleted_at is null;
revoke all on public.v_my_payment_notifications from public,anon;
grant select on public.v_my_payment_notifications to authenticated;

-- Shared eligibility rechecked under the Activity lock by the trusted evaluator.
create function app.payment_schedule_due(p_schedule uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.v_activity_payment_schedule_financials s
 join public.commitments c on c.id=s.commitment_id join public.projects p on p.id=s.project_id
 where s.payment_schedule_id=p_schedule and s.outstanding_minor>0 and c.deleted_at is null
 and c.status not in ('cancelled','completed') and p.deleted_at is null and p.status<>'archived'
 and s.due_on between (statement_timestamp() at time zone p.timezone)::date and (statement_timestamp() at time zone p.timezone)::date+7);
$$;
revoke all on function app.payment_schedule_due(uuid) from public,anon,authenticated,service_role;

create or replace function app.process_domain_event(p_event uuid) returns void
language plpgsql security definer set search_path='' as $$
declare e app.domain_events%rowtype; r app.automation_rules%rowtype;
begin
 -- Serialize concurrent retries; effects and receipts commit together.
 select * into strict e from app.domain_events where id=p_event for update;
 if exists(select 1 from app.domain_event_processing where event_id=e.id) then return; end if;
 for r in select * from app.automation_rules where enabled and event_type=e.event_type order by priority,id loop
  if r.condition_handler='activity_live' and not exists(
   select 1 from public.commitments where id=e.resource_id and project_id=e.project_id and deleted_at is null
  ) then continue; end if;
  if r.condition_handler='join_project_live' and not exists(select 1 from public.projects where id=e.project_id and deleted_at is null) then continue; end if;
  if r.condition_handler='decision_live' and not exists(select 1 from public.decisions d join public.projects p on p.id=d.project_id where d.id=e.resource_id and d.project_id=e.project_id and d.deleted_at is null and p.deleted_at is null and p.status<>'archived') then continue; end if;
  if exists(select 1 from app.automation_action_runs where event_id=e.id and rule_id=r.id) then continue; end if;
  case r.action_type
   when 'notify_activity_collaborators' then
    insert into public.notifications(project_id,commitment_id,recipient_user_id)
    select e.project_id,e.resource_id,m.user_id from public.project_members m
    where m.project_id=e.project_id and m.status='active' and m.deleted_at is null
      and m.user_id is not null and m.user_id is distinct from e.actor_user_id
    on conflict(recipient_user_id,commitment_id,kind) do nothing;
   when 'notify_join_organizers' then
    insert into public.notifications(project_id,join_request_id,recipient_user_id,kind)
    select e.project_id,e.resource_id,m.user_id,'project_join_requested' from public.project_members m
    where m.project_id=e.project_id and m.role='organizer' and m.status='active' and m.deleted_at is null
      and m.user_id is not null and m.user_id is distinct from e.actor_user_id
    on conflict do nothing;
   when 'notify_approved_requester' then
    insert into public.notifications(project_id,join_request_id,recipient_user_id,kind)
    select e.project_id,e.resource_id,j.requester_user_id,'project_member_approved' from app.project_join_requests j
    where j.id=e.resource_id and j.project_id=e.project_id and j.status='approved'
    on conflict do nothing;
   when 'notify_decision_managers' then
    insert into public.notifications(project_id,decision_id,domain_event_id,recipient_user_id,kind)
    select d.project_id,d.id,e.id,m.user_id,'decision_deadline_reached' from public.decisions d join public.project_members m on m.project_id=d.project_id
    where d.id=e.resource_id and d.status='open' and d.deadline_version::text=split_part(e.deduplication_key,':',2)
     and m.status='active' and m.deleted_at is null and m.user_id is not null and (m.role='organizer' or (m.role='member' and m.user_id=d.created_by)) on conflict do nothing;
   when 'notify_decision_members' then
    insert into public.notifications(project_id,decision_id,domain_event_id,recipient_user_id,kind)
    select e.project_id,e.resource_id,e.id,m.user_id,'decision_resolved' from public.project_members m
    where m.project_id=e.project_id and m.status='active' and m.deleted_at is null and m.user_id is not null and m.user_id is distinct from e.actor_user_id on conflict do nothing;
   when 'notify_payment_responsible' then
    if app.payment_schedule_due(e.resource_id) then
     insert into public.notifications(project_id,payment_schedule_id,domain_event_id,recipient_user_id,kind)
     select e.project_id,e.resource_id,e.id,m.user_id,'payment_due_soon'
     from public.activity_payment_schedules s join public.commitments c on c.id=s.commitment_id
     join public.project_members m on m.project_id=c.project_id
     where s.id=e.resource_id and e.deduplication_key='due:'||s.due_on||':7'
       and m.status='active' and m.deleted_at is null and m.user_id is not null
       and (m.id=c.owner_member_id or (m.role='organizer' and not exists(
         select 1 from public.project_members owner where owner.id=c.owner_member_id and owner.project_id=c.project_id
         and owner.status='active' and owner.deleted_at is null and owner.user_id is not null)))
     on conflict do nothing;
    end if;
   else raise exception 'Unsupported domain action: %',r.action_type;
  end case;
  insert into app.automation_action_runs(event_id,rule_id) values(e.id,r.id);
 end loop;
 insert into app.domain_event_processing(event_id) values(e.id);
end $$;

create or replace function app.emit_domain_event(p_type text,p_project uuid,p_resource uuid,p_payload jsonb,p_key text)
returns uuid language plpgsql security definer set search_path='' as $$
declare schedule_row public.activity_payment_schedules%rowtype; comment_row public.resource_comments%rowtype; d public.decisions%rowtype; c public.commitments%rowtype; v_actor uuid; v_id uuid; prior app.domain_events%rowtype; j app.project_join_requests%rowtype; v_resource_type text;
begin
 if p_type='payment.due_soon' then
  select * into schedule_row from public.activity_payment_schedules where id=p_resource and project_id=p_project and deleted_at is null;
  if not found or auth.uid() is not null or not app.payment_schedule_due(p_resource)
   or p_key is distinct from 'due:'||schedule_row.due_on||':7'
   or p_payload is distinct from jsonb_build_object('activity_id',schedule_row.commitment_id) then
   raise exception 'Invalid payment due fact' using errcode='22023'; end if;
  v_actor:=null; v_resource_type:='payment_schedule';
 elsif p_type='comment.created' then
  select * into comment_row from public.resource_comments where id=p_resource and project_id=p_project and deleted_at is null;
  if not found or auth.uid() is distinct from comment_row.author_user_id or p_key is distinct from 'created'
   or p_payload is distinct from jsonb_build_object('parent_resource_type',comment_row.resource_type,'parent_resource_id',comment_row.resource_id) then
   raise exception 'Invalid comment fact' using errcode='22023';
  end if;
  if app.require_comment_resource(comment_row.resource_type,comment_row.resource_id,true) is distinct from p_project then
   raise exception 'Invalid comment binding' using errcode='22023'; end if;
  v_actor:=auth.uid(); v_resource_type:='comment';
 elsif p_type in ('decision.created','decision.vote_cast','decision.deadline_reached','decision.resolved') then
  select * into d from public.decisions where id=p_resource and project_id=p_project and deleted_at is null;
  if not found or not exists(select 1 from public.projects where id=p_project and deleted_at is null and status<>'archived') then raise exception 'Invalid decision event context' using errcode='22023'; end if;
  if (p_type='decision.created' and (auth.uid() is distinct from d.created_by or p_key is distinct from 'created'))
   or (p_type='decision.vote_cast' and (p_key is distinct from 'vote:'||d.vote_revision or not exists(select 1 from public.decision_votes where decision_id=d.id and voter_user_id=auth.uid() and revision=d.vote_revision)))
   or (p_type='decision.deadline_reached' and (auth.uid() is not null or d.status<>'open' or d.voting_deadline is null or d.voting_deadline>clock_timestamp() or p_key is distinct from 'deadline:'||d.deadline_version))
   or (p_type='decision.resolved' and (d.status<>'resolved' or auth.uid() is distinct from d.resolved_by or p_key is distinct from 'resolved'))
   or p_payload is distinct from (case when p_type='decision.resolved' then jsonb_build_object('resolved_option_id',d.resolved_option_id) else '{}'::jsonb end) then
   raise exception 'Invalid decision fact' using errcode='22023'; end if;
  v_actor:=case when p_type='decision.deadline_reached' then null else auth.uid() end; v_resource_type:='decision';
 elsif p_type in ('project.join_requested','project.member_approved') then
  select * into j from app.project_join_requests where id=p_resource and project_id=p_project;
  if not found or p_payload is distinct from '{}'::jsonb
    or (p_type='project.join_requested' and (j.status<>'pending' or auth.uid() is distinct from j.requester_user_id or p_key<>'requested'))
    or (p_type='project.member_approved' and (j.status<>'approved' or auth.uid() is distinct from j.reviewed_by_user_id or p_key<>'approved'
      or not exists(select 1 from public.project_members where id=j.member_id and project_id=j.project_id and user_id=j.requester_user_id and status='active' and deleted_at is null))) then
   raise exception 'Invalid join event context' using errcode='22023';
  end if;
  v_actor:=auth.uid(); v_resource_type:='join_request';
 else
 if p_type not in ('activity.created','activity.completed') or p_type is null then
  raise exception 'Unregistered emission handler' using errcode='22023';
 end if;
 select * into c from public.commitments where id=p_resource and project_id=p_project;
 if not found or c.deleted_at is not null then raise exception 'Invalid event resource/project' using errcode='22023'; end if;
 if p_type='activity.completed' and c.status<>'completed' then raise exception 'Activity is not completed' using errcode='22023'; end if;
 if p_payload is null or p_payload is distinct from jsonb_build_object('category_id',c.area_id) then
  raise exception 'Invalid activity event payload' using errcode='22023';
 end if;
 -- Actor is never supplied by a caller. Preserve existing system-insert fallback.
 v_actor:=coalesce(auth.uid(),(select user_id from public.project_members where id=c.created_by and project_id=c.project_id));
 v_resource_type:='activity';
 end if;
 insert into app.domain_events(event_type,project_id,actor_user_id,resource_type,resource_id,payload,deduplication_key)
 values(p_type,p_project,v_actor,v_resource_type,p_resource,p_payload,p_key)
 on conflict(event_type,resource_id,deduplication_key) do nothing returning id into v_id;
 if v_id is null then
  select * into strict prior from app.domain_events where event_type=p_type and resource_id=p_resource and deduplication_key=p_key;
  if prior.project_id is distinct from p_project or prior.payload is distinct from p_payload then
   raise exception 'Conflicting event retry' using errcode='22023';
  end if;
  v_id:=prior.id;
 end if;
 perform app.process_domain_event(v_id);
 return v_id;
end $$;

create function app.evaluate_payment_schedule_deadlines() returns integer language plpgsql security definer set search_path='' as $$
declare candidate record; s public.activity_payment_schedules%rowtype; n integer:=0;
begin
 if auth.uid() is not null then raise exception 'Trusted scheduler context required' using errcode='42501'; end if;
 for candidate in select q.id,q.project_id,q.commitment_id from public.activity_payment_schedules q
 where q.deleted_at is null and app.payment_schedule_due(q.id)
 and not exists(select 1 from app.domain_events e where e.event_type='payment.due_soon' and e.resource_id=q.id and e.deduplication_key='due:'||q.due_on||':7')
 order by q.due_on,q.id limit 100 loop
  perform 1 from public.projects where id=candidate.project_id and deleted_at is null and status<>'archived' for update skip locked;
  if not found then continue; end if;
  perform 1 from public.commitments where id=candidate.commitment_id and deleted_at is null for update skip locked;
  if not found then continue; end if;
  select * into s from public.activity_payment_schedules where id=candidate.id and deleted_at is null for update skip locked;
  if not found or not app.payment_schedule_due(s.id) then continue; end if;
  perform app.emit_domain_event('payment.due_soon',s.project_id,s.id,jsonb_build_object('activity_id',s.commitment_id),'due:'||s.due_on||':7');
  n:=n+1;
 end loop;
 return n;
end $$;
revoke all on function app.evaluate_payment_schedule_deadlines() from public,anon,authenticated,service_role;
create function app.evaluate_scheduled_domain_events() returns void language plpgsql security definer set search_path='' as $$
begin
 perform app.evaluate_decision_deadlines();
 perform app.evaluate_payment_schedule_deadlines();
end $$;
revoke all on function app.evaluate_scheduled_domain_events() from public,anon,authenticated,service_role;
-- Update the existing job in place; retain its name and operational history.
select cron.schedule('orchestrio-decision-deadlines','* * * * *','select app.evaluate_scheduled_domain_events()');

create or replace function app._health_findings(p_project uuid)
returns table (code text,severity text,subject_type text,subject_id uuid,subject_label text,
 params jsonb,message text,resolution text,affects_health boolean,dismissible boolean)
language sql stable security invoker set search_path='' as $$
 select * from app._health_findings_with_optional_metadata(p_project) h where code not in ('missing_booking_reference','missing_owner')
 and not (h.subject_type='payment' and exists(select 1 from public.payments p where p.id=h.subject_id and p.payment_schedule_id is not null))
 union all
 select 'decision_needs_resolution','warning','decision',d.id,d.title,jsonb_build_object('voting_deadline',d.voting_deadline),
 d.title||' needs resolving. Voting has closed.','Resolve decision',true,false
 from public.decisions d join public.projects p on p.id=d.project_id
 where d.project_id=p_project and d.status='open' and d.deleted_at is null and d.voting_deadline<=statement_timestamp() and p.status<>'archived' and p.deleted_at is null
 union all
 select case when s.due_on<(statement_timestamp() at time zone p.timezone)::date then 'payment_overdue' else 'payment_due_soon' end,
 case when s.due_on<(statement_timestamp() at time zone p.timezone)::date then 'blocker' else 'warning' end,
 'payment_schedule',s.payment_schedule_id,s.title,jsonb_build_object('activity_id',s.commitment_id,'amount_minor',s.outstanding_minor,'currency',p.currency,'due_on',s.due_on),
 s.title||case when s.due_on<(statement_timestamp() at time zone p.timezone)::date then ' is overdue. ' else ' is due on '||to_char(s.due_on,'FMDD Month')||'. ' end||app.format_money(s.outstanding_minor,p.currency)||' outstanding.',
 'Record payment',true,false
 from public.v_activity_payment_schedule_financials s join public.commitments c on c.id=s.commitment_id join public.projects p on p.id=s.project_id
 where s.project_id=p_project and s.outstanding_minor>0 and c.deleted_at is null and c.status not in ('cancelled','completed')
 and p.deleted_at is null and p.status<>'archived' and s.due_on<=(statement_timestamp() at time zone p.timezone)::date+7;
$$;

create or replace function public.get_project_timeline_events(p_project uuid, p_start timestamptz, p_end timestamptz)
returns table (
  project_id uuid,
  occurs_at timestamptz,
  all_day boolean,
  event_type text,
  title text,
  subject_type text,
  subject_id uuid,
  status text,
  occurrence_date date,
  series_id uuid,
  is_recurring_occurrence boolean,
  occurrence_status text
)
language sql stable security invoker set search_path = ''
as $$
  with bounds as (
    select p_start as starts_at, p_end as ends_at
  )
  select c.project_id, c.starts_at, false, 'commitment_start', c.title,
         'commitment', c.id, c.status::text, null::date, null::uuid, false, null::text
  from public.commitments c, bounds b
  where c.project_id = p_project and c.deleted_at is null and c.status <> 'cancelled'
    and c.starts_at is not null and c.recurrence_frequency is null
    and c.starts_at between b.starts_at and b.ends_at
union all
  select c.project_id, c.ends_at, false, 'commitment_end', c.title,
         'commitment', c.id, c.status::text, null::date, null::uuid, false, null::text
  from public.commitments c, bounds b
  where c.project_id = p_project and c.deleted_at is null and c.status <> 'cancelled'
    and c.ends_at is not null and c.recurrence_frequency is null
    and c.ends_at between b.starts_at and b.ends_at
union all
  select pay.project_id, (pay.due_on::timestamp at time zone pr.timezone), true, 'payment_due',
         'Payment due - ' || c.title, 'payment', pay.id, pay.status::text,
         null::date, null::uuid, false, null::text
  from public.payments pay
  join public.commitments c on c.id = pay.commitment_id and c.deleted_at is null
  join public.projects pr on pr.id = pay.project_id
  cross join bounds b
  where pay.project_id = p_project and pay.deleted_at is null and pay.status = 'scheduled' and pay.payment_schedule_id is null and pay.due_on is not null
    and (pay.due_on::timestamp at time zone pr.timezone) between b.starts_at and b.ends_at
union all
  select pay.project_id, (pay.paid_on::timestamp at time zone pr.timezone), true, 'payment_made',
         'Payment made - ' || c.title, 'payment', pay.id, pay.status::text,
         null::date, null::uuid, false, null::text
  from public.payments pay
  join public.commitments c on c.id = pay.commitment_id and c.deleted_at is null
  join public.projects pr on pr.id = pay.project_id
  cross join bounds b
  where pay.project_id = p_project and pay.deleted_at is null and pay.status = 'paid' and pay.paid_on is not null
    and (pay.paid_on::timestamp at time zone pr.timezone) between b.starts_at and b.ends_at
union all
  select t.project_id, (t.due_on::timestamp at time zone pr.timezone), true, 'task_due',
         'Task: ' || t.title, 'task', t.id, t.status::text,
         null::date, null::uuid, false, null::text
  from public.tasks t
  join public.projects pr on pr.id = t.project_id
  cross join bounds b
  where t.project_id = p_project and t.deleted_at is null and t.status in ('open','in_progress')
    and t.due_on is not null and t.recurrence_frequency is null
    and (t.due_on::timestamp at time zone pr.timezone) between b.starts_at and b.ends_at
union all
  select m.project_id, (m.on_date::timestamp at time zone pr.timezone), true, 'milestone',
         m.title, 'milestone', m.id, null::text,
         null::date, null::uuid, false, null::text
  from public.milestones m
  join public.projects pr on pr.id = m.project_id
  cross join bounds b
  where m.project_id = p_project
    and (m.on_date::timestamp at time zone pr.timezone) between b.starts_at and b.ends_at
union all
  select pr.id, (pr.starts_on::timestamp at time zone pr.timezone), true,
         'project_start', pr.name || ' starts', 'project', pr.id, pr.status::text,
         null::date, null::uuid, false, null::text
  from public.projects pr, bounds b
  where pr.id = p_project and pr.deleted_at is null and pr.starts_on is not null
    and (pr.starts_on::timestamp at time zone pr.timezone) between b.starts_at and b.ends_at
union all
  select pr.id, (pr.ends_on::timestamp at time zone pr.timezone), true,
         'project_end', pr.name || ' ends', 'project', pr.id, pr.status::text,
         null::date, null::uuid, false, null::text
  from public.projects pr, bounds b
  where pr.id = p_project and pr.deleted_at is null and pr.ends_on is not null
    and (pr.ends_on::timestamp at time zone pr.timezone) between b.starts_at and b.ends_at
union all
  select c.project_id, (rd.occurrence_date::timestamp at time zone pr.timezone), true,
         'recurring_commitment_due', c.title, 'commitment', c.id,
         coalesce(co.status::text, case when rd.occurrence_date < ((now() at time zone pr.timezone)::date) then 'overdue' else 'upcoming' end),
         rd.occurrence_date, c.id, true, co.status::text
  from public.commitments c
  join public.projects pr on pr.id = c.project_id
  cross join bounds b
  join lateral app.recurrence_dates(
    c.recurrence_frequency,
    c.recurrence_interval,
    c.recurrence_start_date,
    case when c.recurrence_active then c.recurrence_end_date else c.recurrence_end_date end,
    (b.starts_at at time zone pr.timezone)::date,
    (b.ends_at at time zone pr.timezone)::date
  ) rd on true
  left join public.commitment_occurrences co
    on co.commitment_id = c.id and co.occurrence_date = rd.occurrence_date
  where c.project_id = p_project and c.deleted_at is null and c.status <> 'cancelled'
    and c.recurrence_frequency is not null
union all
  select t.project_id, (rd.occurrence_date::timestamp at time zone pr.timezone), true,
         'recurring_task_due', 'Task: ' || t.title, 'task', t.id,
         coalesce(tocc.status::text, case when rd.occurrence_date < ((now() at time zone pr.timezone)::date) then 'overdue' else 'upcoming' end),
         rd.occurrence_date, t.id, true, tocc.status::text
  from public.tasks t
  join public.projects pr on pr.id = t.project_id
  cross join bounds b
  join lateral app.recurrence_dates(
    t.recurrence_frequency,
    t.recurrence_interval,
    t.recurrence_start_date,
    case when t.recurrence_active then t.recurrence_end_date else t.recurrence_end_date end,
    (b.starts_at at time zone pr.timezone)::date,
    (b.ends_at at time zone pr.timezone)::date
  ) rd on true
  left join public.task_occurrences tocc
    on tocc.task_id = t.id and tocc.occurrence_date = rd.occurrence_date
  where t.project_id = p_project and t.deleted_at is null and t.status <> 'cancelled'
    and t.recurrence_frequency is not null
    and coalesce(tocc.status, 'completed'::public.occurrence_status) <> 'skipped'
union all
 select d.project_id,d.voting_deadline,false,'decision_deadline',d.title||' — voting closes','decision',d.id,
 case when d.status='resolved' then 'resolved' when d.voting_deadline<=statement_timestamp() then 'voting_closed' else 'voting_open' end,
 null::date,null::uuid,false,null::text
 from public.decisions d where d.project_id=p_project and d.deleted_at is null and d.voting_deadline between p_start and p_end
union all
 select s.project_id,s.due_on::timestamp at time zone p.timezone,true,'payment_schedule_due',
 s.title||' — '||app.format_money(case when s.outstanding_minor=0 then s.scheduled_amount_minor else s.outstanding_minor end,p.currency)||case when s.outstanding_minor=0 then '' else ' outstanding' end,
 'payment_schedule',s.commitment_id,
 case when s.outstanding_minor=0 then 'paid' when s.due_on<(statement_timestamp() at time zone p.timezone)::date then 'overdue'
 when s.net_paid_minor>0 then 'part_paid' when s.due_on=(statement_timestamp() at time zone p.timezone)::date then 'due_today'
 when s.due_on<=(statement_timestamp() at time zone p.timezone)::date+7 then 'due_soon' else 'upcoming' end,
 null::date,null::uuid,false,null::text
 from public.v_activity_payment_schedule_financials s join public.commitments c on c.id=s.commitment_id join public.projects p on p.id=s.project_id
 where s.project_id=p_project and c.deleted_at is null and c.status<>'cancelled' and p.deleted_at is null
 and (s.due_on::timestamp at time zone p.timezone) between p_start and p_end
$$;
