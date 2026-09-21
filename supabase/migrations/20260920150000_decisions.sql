-- Decisions are advisory choices; only explicit conversion creates an Activity.
create table public.decisions (
 id uuid primary key default gen_random_uuid(), project_id uuid not null references public.projects(id),
 title text not null check(length(btrim(title)) between 1 and 200), description text check(length(description)<=4000),
 created_by uuid not null references public.users(id), status text not null default 'open' check(status in ('open','resolved')),
 voting_deadline timestamptz, deadline_version bigint not null default 1, voting_started boolean not null default false,
 vote_revision bigint not null default 0, resolved_option_id uuid, resolved_at timestamptz, resolved_by uuid references public.users(id),
 converted_activity_id uuid references public.commitments(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz,
 unique(project_id,id),
 check((status='open' and resolved_option_id is null and resolved_at is null and resolved_by is null and converted_activity_id is null)
 or (status='resolved' and resolved_option_id is not null and resolved_at is not null and resolved_by is not null))
);
create table public.decision_options (
 id uuid primary key default gen_random_uuid(), project_id uuid not null, decision_id uuid not null,
 title text not null check(length(btrim(title)) between 1 and 200), estimated_cost_minor bigint check(estimated_cost_minor between 0 and 1000000000000),
 sort_order integer not null, created_at timestamptz not null default now(),
 foreign key(project_id,decision_id) references public.decisions(project_id,id), unique(decision_id,id)
);
alter table public.decisions add constraint decision_resolved_option foreign key(id,resolved_option_id) references public.decision_options(decision_id,id);
create table public.decision_votes (
 id uuid primary key default gen_random_uuid(), project_id uuid not null, decision_id uuid not null, option_id uuid not null,
 voter_user_id uuid not null references public.users(id), revision bigint not null,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 foreign key(project_id,decision_id) references public.decisions(project_id,id),
 foreign key(decision_id,option_id) references public.decision_options(decision_id,id), unique(decision_id,voter_user_id)
);
create index decisions_project on public.decisions(project_id,created_at desc) where deleted_at is null;
create index decisions_deadline on public.decisions(voting_deadline) where status='open' and deleted_at is null and voting_deadline is not null;
create index decision_options_parent on public.decision_options(decision_id,sort_order);
create index decision_votes_option on public.decision_votes(decision_id,option_id);
alter table public.decisions enable row level security; alter table public.decisions force row level security;
alter table public.decision_options enable row level security; alter table public.decision_options force row level security;
alter table public.decision_votes enable row level security; alter table public.decision_votes force row level security;
revoke all on public.decisions,public.decision_options,public.decision_votes from public,anon,authenticated,service_role;
grant select on public.decisions,public.decision_options,public.decision_votes to authenticated;
create policy decisions_read on public.decisions for select to authenticated using(deleted_at is null and app.is_member(project_id)
 and exists(select 1 from public.projects p where p.id=project_id and p.deleted_at is null));
create policy decision_options_read on public.decision_options for select to authenticated using(exists(select 1 from public.decisions d where d.id=decision_id and d.project_id=project_id));
-- Totals are returned by the authorized read model; clients never list others' ballots.
create policy decision_votes_own on public.decision_votes for select to authenticated using(voter_user_id=auth.uid() and exists(select 1 from public.decisions d where d.id=decision_id and d.project_id=project_id));
create trigger audit after insert or update or delete on public.decisions for each row execute function app.tg_audit_row();
create trigger audit after insert or update or delete on public.decision_options for each row execute function app.tg_audit_row();
create function app.tg_audit_decision_vote() returns trigger language plpgsql security definer set search_path='' as $$
declare r public.decision_votes%rowtype; begin
 r:=case when tg_op='DELETE' then old else new end;
 insert into public.audit_log(project_id,actor_user_id,actor_member_id,source,action,entity_type,entity_id,before,after)
 values(r.project_id,auth.uid(),app.current_member_id(r.project_id),'rpc',
 case tg_op when 'INSERT' then 'create'::public.audit_action when 'DELETE' then 'delete'::public.audit_action else 'update'::public.audit_action end,
 'decision_votes',r.id,case when tg_op<>'INSERT' then jsonb_build_object('decision_id',old.decision_id,'revision',old.revision) end,
 case when tg_op<>'DELETE' then jsonb_build_object('decision_id',new.decision_id,'revision',new.revision) end);
 return r;
end $$;
create trigger audit after insert or update or delete on public.decision_votes for each row execute function app.tg_audit_decision_vote();
create function app.can_manage_decision(p_decision uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.decisions d join public.projects p on p.id=d.project_id where d.id=p_decision and d.deleted_at is null and p.deleted_at is null
 and app.has_role(d.project_id,array['organizer','member']::public.member_role[]) and (app.is_organizer(d.project_id) or d.created_by=auth.uid()))
$$;
create function app.require_decision(p_decision uuid,p_manage boolean default false) returns public.decisions
language plpgsql security definer set search_path='' as $$ declare d public.decisions%rowtype; begin
 select * into d from public.decisions where id=p_decision;
 if not found or auth.uid() is null or not app.is_member(d.project_id) then raise exception 'orchestr:not_authorized:This decision is unavailable.' using errcode='42501'; end if;
 perform 1 from public.projects where id=d.project_id and deleted_at is null and status<>'archived' for update;
 if not found then raise exception 'orchestr:project_archived:This project is unavailable or read-only.' using errcode='42501'; end if;
 select * into d from public.decisions where id=p_decision and deleted_at is null for update;
 if not found or not app.is_member(d.project_id) or (p_manage and not app.can_manage_decision(d.id)) then
  raise exception 'orchestr:not_authorized:You cannot change this decision.' using errcode='42501'; end if;
 return d;
end $$;
create function app.validate_decision(p_title text,p_description text,p_deadline timestamptz,p_options jsonb) returns void
language plpgsql set search_path='' as $$ declare o jsonb; begin
 if p_title is null or length(btrim(p_title)) not between 1 and 200 or length(p_description)>4000 then raise exception 'orchestr:validation:Enter a question up to 200 characters and a description up to 4000 characters.' using errcode='22023'; end if;
 if p_deadline is not null and p_deadline<=clock_timestamp() then raise exception 'orchestr:validation:Choose a future voting deadline.' using errcode='22023'; end if;
 if p_options is null then return; end if;
 if jsonb_typeof(p_options)<>'array' or jsonb_array_length(p_options) not between 2 and 20 then raise exception 'orchestr:validation:Add between 2 and 20 options.' using errcode='22023'; end if;
 for o in select value from jsonb_array_elements(p_options) loop
  if jsonb_typeof(o)<>'object' or jsonb_typeof(o->'title') is distinct from 'string' or o->>'title' is null or length(btrim(o->>'title')) not between 1 and 200
   or o - array['title','estimated_cost_minor'] <> '{}'::jsonb then raise exception 'orchestr:validation:Each option needs a title up to 200 characters.' using errcode='22023'; end if;
  if o->>'estimated_cost_minor' is not null and (coalesce(o->>'estimated_cost_minor','') !~ '^[0-9]{1,13}$' or (o->>'estimated_cost_minor')::numeric>1000000000000) then
   raise exception 'orchestr:validation:Estimated costs must be non-negative whole minor units.' using errcode='22023'; end if;
 end loop;
 if (select count(distinct lower(btrim(value->>'title'))) from jsonb_array_elements(p_options))<>jsonb_array_length(p_options) then
  raise exception 'orchestr:validation:Give each option a different title.' using errcode='22023'; end if;
end $$;
create function public.create_decision(p_project uuid,p_title text,p_description text,p_deadline timestamptz,p_options jsonb,p_id uuid default gen_random_uuid()) returns uuid
language plpgsql security definer set search_path='' as $$ declare d public.decisions%rowtype; begin
 if not app.has_role(p_project,array['organizer','member']::public.member_role[]) then raise exception 'orchestr:not_authorized:You cannot create decisions.' using errcode='42501'; end if;
 perform 1 from public.projects where id=p_project and deleted_at is null and status<>'archived' for update;
 if not found or not app.has_role(p_project,array['organizer','member']::public.member_role[]) then raise exception 'orchestr:project_archived:This project is unavailable or read-only.' using errcode='42501'; end if;
 select * into d from public.decisions where id=p_id;
 if found then
  if d.project_id=p_project and d.created_by=auth.uid() and d.deleted_at is null then return d.id; end if;
  raise exception 'orchestr:not_authorized:This request is unavailable.' using errcode='42501';
 end if;
 if p_options is null then raise exception 'orchestr:validation:Add at least two options.' using errcode='22023'; end if;
 perform app.validate_decision(p_title,p_description,p_deadline,p_options);
 insert into public.decisions(id,project_id,title,description,created_by,voting_deadline) values(p_id,p_project,btrim(p_title),nullif(btrim(p_description),''),auth.uid(),p_deadline);
 insert into public.decision_options(project_id,decision_id,title,estimated_cost_minor,sort_order)
 select p_project,p_id,btrim(o->>'title'),(o->>'estimated_cost_minor')::bigint,n::int from jsonb_array_elements(p_options) with ordinality q(o,n);
 perform app.emit_domain_event('decision.created',p_project,p_id,'{}','created');
 return p_id;
end $$;
create function public.edit_decision(p_decision uuid,p_title text,p_description text,p_deadline timestamptz,p_options jsonb default null) returns void
language plpgsql security definer set search_path='' as $$ declare d public.decisions%rowtype; begin
 d:=app.require_decision(p_decision,true);
 if d.status<>'open' then raise exception 'orchestr:decision_resolved:This decision can no longer be changed.'; end if;
 -- An unchanged elapsed deadline is allowed when editing only title/description.
 perform app.validate_decision(p_title,p_description,case when p_deadline is distinct from d.voting_deadline then p_deadline end,p_options);
 if p_options is not null then
  if d.voting_started then raise exception 'orchestr:options_locked:Options cannot be changed after voting has begun.'; end if;
  delete from public.decision_options where decision_id=d.id;
  insert into public.decision_options(project_id,decision_id,title,estimated_cost_minor,sort_order)
  select d.project_id,d.id,btrim(o->>'title'),(o->>'estimated_cost_minor')::bigint,n::int from jsonb_array_elements(p_options) with ordinality q(o,n);
 end if;
 update public.decisions set title=btrim(p_title),description=nullif(btrim(p_description),''),voting_deadline=p_deadline,
 deadline_version=deadline_version+case when voting_deadline is distinct from p_deadline then 1 else 0 end,updated_at=now() where id=d.id;
end $$;
create function public.cast_decision_vote(p_decision uuid,p_option uuid) returns void
language plpgsql security definer set search_path='' as $$ declare d public.decisions%rowtype; old_option uuid; rev bigint; begin
 d:=app.require_decision(p_decision);
 if d.status<>'open' then raise exception 'orchestr:decision_resolved:This decision is already resolved.'; end if;
 if d.voting_deadline is not null and d.voting_deadline<=clock_timestamp() then raise exception 'orchestr:voting_closed:Voting has closed.'; end if;
 if p_option is not null and not exists(select 1 from public.decision_options where id=p_option and decision_id=d.id and project_id=d.project_id) then raise exception 'orchestr:validation:This option is not available.' using errcode='22023'; end if;
 select option_id into old_option from public.decision_votes where decision_id=d.id and voter_user_id=auth.uid();
 if old_option is not distinct from p_option then return; end if;
 update public.decisions set voting_started=true,vote_revision=vote_revision+1,updated_at=now() where id=d.id returning vote_revision into rev;
 if p_option is null then delete from public.decision_votes where decision_id=d.id and voter_user_id=auth.uid(); return; end if;
 insert into public.decision_votes(project_id,decision_id,option_id,voter_user_id,revision) values(d.project_id,d.id,p_option,auth.uid(),rev)
 on conflict(decision_id,voter_user_id) do update set option_id=excluded.option_id,revision=excluded.revision,updated_at=now();
 perform app.emit_domain_event('decision.vote_cast',d.project_id,d.id,'{}','vote:'||rev);
end $$;
create function public.resolve_decision(p_decision uuid,p_option uuid) returns void
language plpgsql security definer set search_path='' as $$ declare d public.decisions%rowtype; begin
 d:=app.require_decision(p_decision,true);
 if d.status='resolved' then
  if d.resolved_option_id=p_option then return; end if;
  raise exception 'orchestr:decision_resolved:This decision is already resolved with a different option.';
 end if;
 if not exists(select 1 from public.decision_options where id=p_option and decision_id=d.id and project_id=d.project_id) then raise exception 'orchestr:validation:Choose an option from this decision.' using errcode='22023'; end if;
 update public.decisions set status='resolved',resolved_option_id=p_option,resolved_at=now(),resolved_by=auth.uid(),updated_at=now() where id=d.id;
 perform app.emit_domain_event('decision.resolved',d.project_id,d.id,jsonb_build_object('resolved_option_id',p_option),'resolved');
end $$;
create function public.soft_delete_decision(p_decision uuid) returns void language plpgsql security definer set search_path='' as $$ declare d public.decisions%rowtype; begin
 d:=app.require_decision(p_decision,true); update public.decisions set deleted_at=now(),updated_at=now() where id=d.id;
end $$;
create function public.convert_decision_to_activity(p_decision uuid,p_category uuid,p_activity_type text default 'other') returns uuid
language plpgsql security definer set search_path='' as $$ declare d public.decisions%rowtype; o public.decision_options%rowtype; c public.commitments%rowtype; begin
 d:=app.require_decision(p_decision,true);
 if d.status<>'resolved' then raise exception 'orchestr:decision_open:Resolve this decision before creating an activity.'; end if;
 if d.converted_activity_id is not null then return d.converted_activity_id; end if;
 if p_activity_type is null or p_activity_type not in ('other','task','booking','purchase','event') then raise exception 'orchestr:validation:Choose a supported activity type.' using errcode='22023'; end if;
 if p_category is null or not exists(select 1 from public.project_areas where id=p_category and project_id=d.project_id) then raise exception 'orchestr:category_required:Choose a Category in this project.' using errcode='22023'; end if;
 select * into strict o from public.decision_options where id=d.resolved_option_id and decision_id=d.id;
 c:=public.create_activity_in_category(d.project_id,p_category,jsonb_build_object('title',o.title,'kind','other','activity_type',p_activity_type,'estimated_cost_minor',o.estimated_cost_minor,'notes','Selected for: '||d.title),null);
 update public.decisions set converted_activity_id=c.id,updated_at=now() where id=d.id;
 return c.id;
end $$;
create function public.get_decisions(p_project uuid,p_decision uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$ declare result jsonb; begin
 if not app.is_member(p_project) or not exists(select 1 from public.projects where id=p_project and deleted_at is null) then raise exception 'orchestr:not_authorized:This decision is unavailable.' using errcode='42501'; end if;
 select coalesce(jsonb_agg(q.doc order by q.created_at desc),'[]'::jsonb) into result from (
 select d.created_at,to_jsonb(d)||jsonb_build_object('can_manage',app.can_manage_decision(d.id),'writable',app.is_writable_project(d.project_id),
 'deadline_reached',d.voting_deadline is not null and d.voting_deadline<=statement_timestamp(),
 'can_vote',d.status='open' and app.is_writable_project(d.project_id) and (d.voting_deadline is null or d.voting_deadline>statement_timestamp()),
 'my_option_id',(select option_id from public.decision_votes where decision_id=d.id and voter_user_id=auth.uid()),
 'vote_count',(select count(*) from public.decision_votes where decision_id=d.id),
 'options',(select coalesce(jsonb_agg(to_jsonb(o)||jsonb_build_object('vote_count',(select count(*) from public.decision_votes v where v.option_id=o.id)) order by o.sort_order),'[]'::jsonb) from public.decision_options o where o.decision_id=d.id)) doc
 from public.decisions d where d.project_id=p_project and d.deleted_at is null and (p_decision is null or d.id=p_decision) order by d.created_at desc limit 200
 ) q;
 return result;
end $$;
create function app.tg_project_decisions_deleted() returns trigger language plpgsql security definer set search_path='' as $$ begin
 update public.decisions set deleted_at=new.deleted_at,updated_at=now() where project_id=new.id and deleted_at is null; return new;
end $$;
create trigger decisions_soft_delete after update of deleted_at on public.projects for each row when(old.deleted_at is null and new.deleted_at is not null) execute function app.tg_project_decisions_deleted();
revoke all on function app.tg_audit_decision_vote(),app.can_manage_decision(uuid),app.require_decision(uuid,boolean),app.validate_decision(text,text,timestamptz,jsonb),app.tg_project_decisions_deleted() from public,anon,authenticated,service_role;
revoke all on function public.create_decision(uuid,text,text,timestamptz,jsonb,uuid),public.edit_decision(uuid,text,text,timestamptz,jsonb),public.cast_decision_vote(uuid,uuid),public.resolve_decision(uuid,uuid),public.soft_delete_decision(uuid),public.convert_decision_to_activity(uuid,uuid,text),public.get_decisions(uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function public.create_decision(uuid,text,text,timestamptz,jsonb,uuid),public.edit_decision(uuid,text,text,timestamptz,jsonb),public.cast_decision_vote(uuid,uuid),public.resolve_decision(uuid,uuid),public.soft_delete_decision(uuid),public.convert_decision_to_activity(uuid,uuid,text),public.get_decisions(uuid,uuid) to authenticated;

-- Meaningful Decision notifications use system automation, never mutation-side fan-out.
insert into app.domain_event_types values('decision.created','decision'),('decision.vote_cast','decision'),('decision.deadline_reached','decision'),('decision.resolved','decision');
alter table public.notifications add column decision_id uuid;
alter table public.notifications add column domain_event_id uuid references app.domain_events(id);
alter table public.notifications add constraint notifications_decision_fk foreign key(project_id,decision_id) references public.decisions(project_id,id);
alter table public.notifications drop constraint notifications_kind_resource;
alter table public.notifications add constraint notifications_kind_resource check(
 (kind='activity_created' and commitment_id is not null and join_request_id is null and decision_id is null and domain_event_id is null)
 or (kind in ('project_join_requested','project_member_approved') and commitment_id is null and join_request_id is not null and decision_id is null and domain_event_id is null)
 or (kind in ('decision_deadline_reached','decision_resolved') and commitment_id is null and join_request_id is null and decision_id is not null and domain_event_id is not null));
create unique index notifications_decision_event on public.notifications(recipient_user_id,domain_event_id) where domain_event_id is not null;
create policy notifications_read_decision on public.notifications for select to authenticated using(
 recipient_user_id=auth.uid() and app.is_member(project_id) and exists(select 1 from public.decisions d where d.id=decision_id and d.deleted_at is null)
 and (kind='decision_resolved' or (kind='decision_deadline_reached' and exists(select 1 from public.decisions d where d.id=decision_id and (d.created_by=auth.uid() or app.is_organizer(d.project_id))))));
create view public.v_my_decision_notifications with(security_invoker=true) as
 select n.id,n.project_id,n.decision_id,n.kind,n.created_at,n.read_at,d.title decision_title,o.title selected_title
 from public.notifications n join public.decisions d on d.id=n.decision_id left join public.decision_options o on o.id=d.resolved_option_id
 where n.kind in ('decision_deadline_reached','decision_resolved') and d.deleted_at is null;
revoke all on public.v_my_decision_notifications from public,anon; grant select on public.v_my_decision_notifications to authenticated;
alter table app.automation_rules drop constraint automation_rules_action_type_check;
alter table app.automation_rules add constraint automation_rules_action_type_check check(action_type in ('notify_activity_collaborators','notify_join_organizers','notify_approved_requester','notify_decision_managers','notify_decision_members'));
alter table app.automation_rules drop constraint automation_rules_condition_handler_check;
alter table app.automation_rules add constraint automation_rules_condition_handler_check check(condition_handler in ('always','activity_live','join_project_live','decision_live'));
alter table app.automation_rules add constraint automation_rules_decision_event_check check((action_type<>'notify_decision_managers' or event_type='decision.deadline_reached') and (action_type<>'notify_decision_members' or event_type='decision.resolved'));
insert into app.automation_rules(id,event_type,condition_handler,action_type) values
 ('decision_deadline_managers','decision.deadline_reached','decision_live','notify_decision_managers'),
 ('decision_resolved_members','decision.resolved','decision_live','notify_decision_members');

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
   else raise exception 'Unsupported domain action: %',r.action_type;
  end case;
  insert into app.automation_action_runs(event_id,rule_id) values(e.id,r.id);
 end loop;
 insert into app.domain_event_processing(event_id) values(e.id);
end $$;

create or replace function app.emit_domain_event(p_type text,p_project uuid,p_resource uuid,p_payload jsonb,p_key text)
returns uuid language plpgsql security definer set search_path='' as $$
declare d public.decisions%rowtype; c public.commitments%rowtype; v_actor uuid; v_id uuid; prior app.domain_events%rowtype; j app.project_join_requests%rowtype; v_resource_type text;
begin
 if p_type in ('decision.created','decision.vote_cast','decision.deadline_reached','decision.resolved') then
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

-- One trusted bounded evaluator. Project -> Decision lock order matches mutations.
create function app.evaluate_decision_deadlines() returns integer language plpgsql security definer set search_path='' as $$
declare candidate record; d public.decisions%rowtype; n integer:=0; begin
 if auth.uid() is not null then raise exception 'Trusted scheduler context required' using errcode='42501'; end if;
 for candidate in select q.id,q.project_id from public.decisions q join public.projects p on p.id=q.project_id
  where q.status='open' and q.deleted_at is null and p.deleted_at is null and p.status<>'archived' and q.voting_deadline<=clock_timestamp()
   and not exists(select 1 from app.domain_events e where e.event_type='decision.deadline_reached' and e.resource_id=q.id and e.deduplication_key='deadline:'||q.deadline_version)
  order by q.voting_deadline,q.id limit 100 loop
  perform 1 from public.projects where id=candidate.project_id and deleted_at is null and status<>'archived' for update skip locked;
  if not found then continue; end if;
  select * into d from public.decisions where id=candidate.id and deleted_at is null and status='open' and voting_deadline<=clock_timestamp() for update skip locked;
  if not found then continue; end if;
  perform app.emit_domain_event('decision.deadline_reached',d.project_id,d.id,'{}','deadline:'||d.deadline_version); n:=n+1;
 end loop;
 return n;
end $$;
revoke all on function app.evaluate_decision_deadlines() from public,anon,authenticated,service_role;
create extension if not exists pg_cron with schema pg_catalog;
select cron.schedule('orchestrio-decision-deadlines','* * * * *','select app.evaluate_decision_deadlines()');

-- Decision sharing uses the Phase 3 envelope, with narrower resource manager rules.
alter table app.resource_share_policies drop constraint resource_share_policies_handler_check;
alter table app.resource_share_policies drop constraint resource_share_policies_check;
alter table app.resource_share_policies add constraint resource_share_policy_handler check(
 (resource_type='activity' and handler='activity_member_v1') or (resource_type='decision' and handler='decision_member_v1'));
insert into app.resource_share_policies(resource_type,access_mode,handler) values('decision','member_only','decision_member_v1');
create or replace function app.share_resource_policy(p_type text,p_resource uuid,p_mode text default 'member_only')
returns table(project_id uuid,can_read boolean,can_manage boolean,writable boolean)
language plpgsql stable security definer set search_path='' as $$ declare h text; begin
 select handler into h from app.resource_share_policies where resource_type=p_type and access_mode=p_mode;
 case h
 when 'activity_member_v1' then
  return query select c.project_id,app.is_member(c.project_id),app.has_role(c.project_id,array['organizer','member']::public.member_role[]),p.status<>'archived'
  from public.commitments c join public.projects p on p.id=c.project_id where c.id=p_resource and c.deleted_at is null and p.deleted_at is null;
 when 'decision_member_v1' then
  return query select d.project_id,app.is_member(d.project_id),app.can_manage_decision(d.id),p.status<>'archived'
  from public.decisions d join public.projects p on p.id=d.project_id where d.id=p_resource and d.deleted_at is null and p.deleted_at is null;
 else return;
 end case;
end $$;

-- Recomputed attention; no duplicate deadline/calendar rows or financial joins.
create or replace function app._health_findings(p_project uuid)
returns table (code text,severity text,subject_type text,subject_id uuid,subject_label text,
 params jsonb,message text,resolution text,affects_health boolean,dismissible boolean)
language sql stable security invoker set search_path='' as $$
 select * from app._health_findings_with_optional_metadata(p_project) where code not in ('missing_booking_reference','missing_owner')
 union all
 select 'decision_needs_resolution','warning','decision',d.id,d.title,jsonb_build_object('voting_deadline',d.voting_deadline),
 d.title||' needs resolving. Voting has closed.','Resolve decision',true,false
 from public.decisions d join public.projects p on p.id=d.project_id
 where d.project_id=p_project and d.status='open' and d.deleted_at is null and d.voting_deadline<=statement_timestamp() and p.status<>'archived' and p.deleted_at is null;
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
  where pay.project_id = p_project and pay.deleted_at is null and pay.status = 'scheduled' and pay.due_on is not null
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
$$;
