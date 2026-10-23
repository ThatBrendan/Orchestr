-- Private, transactional domain facts and system automation. No historical backfill.
create table app.domain_event_types (
 event_type text primary key check(event_type ~ '^[a-z][a-z_]*\.[a-z][a-z_]*$'),
 resource_type text not null,
 unique(event_type,resource_type)
);
insert into app.domain_event_types values ('activity.created','activity'),('activity.completed','activity');

-- Deliberately retain identifiers without cascading domain FKs: facts survive deletion.
-- The emitter validates the live resource/project relationship before insertion.
create table app.domain_events (
 id uuid primary key default gen_random_uuid(),
 event_type text not null,
 project_id uuid not null,
 actor_user_id uuid,
 resource_type text not null,
 resource_id uuid not null,
 payload jsonb not null default '{}' check(jsonb_typeof(payload)='object'),
 deduplication_key text not null check(length(deduplication_key) between 1 and 200),
 created_at timestamptz not null default now(),
 foreign key(event_type,resource_type) references app.domain_event_types(event_type,resource_type),
 unique(event_type,resource_id,deduplication_key)
);
create index domain_events_project_created_idx on app.domain_events(project_id,created_at);
create table app.automation_rules (
 id text primary key,
 event_type text not null references app.domain_event_types(event_type),
 enabled boolean not null default true,
 condition_handler text not null check(condition_handler in ('always','activity_live')),
 action_type text not null check(action_type in ('notify_activity_collaborators')),
 action_config jsonb not null default '{}' check(action_config='{}'::jsonb),
 priority integer not null default 100,
 check(action_type <> 'notify_activity_collaborators' or event_type='activity.created')
);
create table app.domain_event_processing (
 event_id uuid primary key references app.domain_events(id),
 processed_at timestamptz not null default now()
);
create table app.automation_action_runs (
 event_id uuid not null references app.domain_events(id),
 rule_id text not null references app.automation_rules(id),
 executed_at timestamptz not null default now(),
 primary key(event_id,rule_id)
);

-- No API/worker grants in Phase 1. Only migration owner/definer paths access these.
do $$ declare t text; begin
 foreach t in array array['domain_event_types','domain_events','automation_rules','domain_event_processing','automation_action_runs'] loop
 execute format('alter table app.%I enable row level security',t);
 execute format('alter table app.%I force row level security',t);
 execute format('revoke all on app.%I from public, anon, authenticated, service_role',t);
 end loop;
end $$;
create function app.tg_domain_event_immutable() returns trigger
language plpgsql set search_path='' as $$ begin
 raise exception 'orchestr:event_immutable:Domain event facts and receipts are append-only.' using errcode='P0001';
end $$;
create trigger immutable before update or delete on app.domain_events for each row execute function app.tg_domain_event_immutable();
create trigger immutable before update or delete on app.domain_event_processing for each row execute function app.tg_domain_event_immutable();
create trigger immutable before update or delete on app.automation_action_runs for each row execute function app.tg_domain_event_immutable();

create function app.process_domain_event(p_event uuid) returns void
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
  if exists(select 1 from app.automation_action_runs where event_id=e.id and rule_id=r.id) then continue; end if;
  case r.action_type
   when 'notify_activity_collaborators' then
    insert into public.notifications(project_id,commitment_id,recipient_user_id)
    select e.project_id,e.resource_id,m.user_id from public.project_members m
    where m.project_id=e.project_id and m.status='active' and m.deleted_at is null
      and m.user_id is not null and m.user_id is distinct from e.actor_user_id
    on conflict(recipient_user_id,commitment_id,kind) do nothing;
   else raise exception 'Unsupported domain action: %',r.action_type;
  end case;
  insert into app.automation_action_runs(event_id,rule_id) values(e.id,r.id);
 end loop;
 insert into app.domain_event_processing(event_id) values(e.id);
end $$;

create function app.emit_domain_event(p_type text,p_project uuid,p_resource uuid,p_payload jsonb,p_key text)
returns uuid language plpgsql security definer set search_path='' as $$
declare c public.commitments%rowtype; v_actor uuid; v_id uuid; prior app.domain_events%rowtype;
begin
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
 insert into app.domain_events(event_type,project_id,actor_user_id,resource_type,resource_id,payload,deduplication_key)
 values(p_type,p_project,v_actor,'activity',p_resource,p_payload,p_key)
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

create function app.tg_activity_domain_events() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.deleted_at is not null then return new; end if;
 if tg_op='INSERT' then
  perform app.emit_domain_event('activity.created',new.project_id,new.id,jsonb_build_object('category_id',new.area_id),'created');
 elsif new.status='completed' and old.status is distinct from new.status then
  -- The row update lock serializes transitions. Reopening/recompletion is a new fact.
  perform app.emit_domain_event('activity.completed',new.project_id,new.id,jsonb_build_object('category_id',new.area_id),
   'completion:'||(select count(*)+1 from app.domain_events where resource_id=new.id and event_type='activity.completed')::text);
 end if;
 return new;
end $$;
revoke all on function app.tg_domain_event_immutable() from public,anon,authenticated,service_role;
revoke all on function app.process_domain_event(uuid) from public,anon,authenticated,service_role;
revoke all on function app.emit_domain_event(text,uuid,uuid,jsonb,text) from public,anon,authenticated,service_role;
revoke all on function app.tg_activity_domain_events() from public,anon,authenticated,service_role;
insert into app.automation_rules(id,event_type,condition_handler,action_type)
values('activity_created_collaborators','activity.created','activity_live','notify_activity_collaborators');
-- Atomic replacement; keep inbox schema, RLS, recipient semantics, and uniqueness.
drop trigger activity_created_notifications on public.commitments;
drop function app.tg_activity_created_notifications();
create trigger activity_domain_events after insert or update of status on public.commitments
for each row execute function app.tg_activity_domain_events();
