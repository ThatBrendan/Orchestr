-- Purpose-specific approval-only join links. No project RLS or invitations changes.
create table app.project_join_links (
 id uuid primary key default gen_random_uuid(),
 project_id uuid not null references public.projects(id),
 token_hash text not null unique check(token_hash ~ '^[0-9a-f]{64}$'),
 created_by_user_id uuid not null references public.users(id),
 created_at timestamptz not null default now(),
 revoked_at timestamptz,
 approval_required boolean not null default true check(approval_required),
 default_role public.member_role not null default 'member' check(default_role='member'),
 unique(project_id,id)
);
create unique index project_join_links_one_active on app.project_join_links(project_id) where revoked_at is null;
create table app.project_join_requests (
 id uuid primary key default gen_random_uuid(),
 project_id uuid not null references public.projects(id),
 join_link_id uuid not null,
 requester_user_id uuid not null references public.users(id),
 requested_role public.member_role not null default 'member' check(requested_role='member'),
 status text not null default 'pending' check(status in ('pending','approved','declined')),
 requested_at timestamptz not null default now(),
 reviewed_at timestamptz,
 reviewed_by_user_id uuid references public.users(id),
 member_id uuid,
 foreign key(project_id,join_link_id) references app.project_join_links(project_id,id),
 foreign key(project_id,member_id) references public.project_members(project_id,id),
 unique(project_id,id),
 check((status='pending' and reviewed_at is null and reviewed_by_user_id is null and member_id is null)
    or (status='approved' and reviewed_at is not null and reviewed_by_user_id is not null and member_id is not null)
    or (status='declined' and reviewed_at is not null and reviewed_by_user_id is not null and member_id is null))
);
create unique index project_join_requests_one_pending on app.project_join_requests(project_id,requester_user_id) where status='pending';
create index project_join_requests_queue on app.project_join_requests(project_id,status,requested_at,id);
create index project_join_requests_user on app.project_join_requests(requester_user_id,project_id,requested_at desc);
alter table app.project_join_links enable row level security;
alter table app.project_join_links force row level security;
alter table app.project_join_requests enable row level security;
alter table app.project_join_requests force row level security;
revoke all on app.project_join_links,app.project_join_requests from public,anon,authenticated,service_role;
-- Audit link metadata only: neither raw tokens nor hashes enter audit snapshots.
create function app.tg_audit_join_link() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.audit_log(project_id,actor_user_id,actor_member_id,source,action,entity_type,entity_id,before,after)
 values(new.project_id,auth.uid(),app.current_member_id(new.project_id),'rpc',
 case when tg_op='INSERT' then 'create'::public.audit_action else 'update'::public.audit_action end,
 'project_join_links',new.id,case when tg_op='UPDATE' then to_jsonb(old)-'token_hash' end,to_jsonb(new)-'token_hash');
 return new;
end $$;
create trigger audit after insert or update on app.project_join_links for each row execute function app.tg_audit_join_link();
create trigger audit after insert or update on app.project_join_requests for each row execute function app.tg_audit_row();

-- Reuse the inbox storage, mark-read RPC and Activity view without changing Activity behavior.
alter table public.notifications alter column commitment_id drop not null;
alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add column join_request_id uuid;
alter table public.notifications add constraint notifications_join_request_fk foreign key(project_id,join_request_id) references app.project_join_requests(project_id,id);
alter table public.notifications add constraint notifications_kind_resource check(
 (kind='activity_created' and commitment_id is not null and join_request_id is null)
 or (kind in ('project_join_requested','project_member_approved') and commitment_id is null and join_request_id is not null));
create unique index notifications_join_recipient_kind on public.notifications(recipient_user_id,join_request_id,kind) where join_request_id is not null;
create policy notifications_read_join on public.notifications for select to authenticated using(
 recipient_user_id=(select auth.uid()) and app.is_member(project_id)
 and (kind='project_member_approved' or (kind='project_join_requested' and app.is_organizer(project_id)))
 and exists(select 1 from public.projects p where p.id=project_id and p.deleted_at is null));
create view public.v_my_join_notifications with(security_invoker=true) as
 select n.id,n.project_id,n.join_request_id,n.kind,n.created_at,n.read_at,p.name project_name
 from public.notifications n join public.projects p on p.id=n.project_id
 where n.kind in ('project_join_requested','project_member_approved') and p.deleted_at is null;
revoke all on public.v_my_join_notifications from public,anon;
grant select on public.v_my_join_notifications to authenticated;

insert into app.domain_event_types values('project.join_requested','join_request'),('project.member_approved','join_request');
alter table app.automation_rules drop constraint automation_rules_action_type_check;
alter table app.automation_rules add constraint automation_rules_action_type_check check(action_type in ('notify_activity_collaborators','notify_join_organizers','notify_approved_requester'));
alter table app.automation_rules drop constraint automation_rules_condition_handler_check;
alter table app.automation_rules add constraint automation_rules_condition_handler_check check(condition_handler in ('always','activity_live','join_project_live'));
alter table app.automation_rules add constraint automation_rules_join_event_check check(
 (action_type<>'notify_join_organizers' or event_type='project.join_requested') and
 (action_type<>'notify_approved_requester' or event_type='project.member_approved'));

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
   else raise exception 'Unsupported domain action: %',r.action_type;
  end case;
  insert into app.automation_action_runs(event_id,rule_id) values(e.id,r.id);
 end loop;
 insert into app.domain_event_processing(event_id) values(e.id);
end $$;

create or replace function app.emit_domain_event(p_type text,p_project uuid,p_resource uuid,p_payload jsonb,p_key text)
returns uuid language plpgsql security definer set search_path='' as $$
declare c public.commitments%rowtype; v_actor uuid; v_id uuid; prior app.domain_events%rowtype; j app.project_join_requests%rowtype; v_resource_type text;
begin
 if p_type in ('project.join_requested','project.member_approved') then
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

insert into app.automation_rules(id,event_type,condition_handler,action_type) values
 ('join_request_organizers','project.join_requested','join_project_live','notify_join_organizers'),
 ('join_approved_requester','project.member_approved','join_project_live','notify_approved_requester');

create function app.require_join_organizer(p_project uuid,p_write boolean default true) returns void
language plpgsql security definer set search_path='' as $$ begin
 if auth.uid() is null or not app.is_organizer(p_project) then
  raise exception 'orchestr:not_authorized:Only a project organiser can manage access.' using errcode='42501'; end if;
 perform 1 from public.projects where id=p_project and deleted_at is null and (not p_write or status<>'archived') for update;
 if not found then raise exception 'orchestr:project_archived:This project is unavailable or read-only.' using errcode='42501'; end if;
 -- Recheck after acquiring the lock, since membership can change while waiting.
 if not app.is_organizer(p_project) then raise exception 'orchestr:not_authorized:Only a project organiser can manage access.' using errcode='42501'; end if;
end $$;

create function public.get_project_join_access(p_project uuid,p_offset integer default 0) returns jsonb
language plpgsql security definer set search_path='' as $$ declare v_requests jsonb; begin
 perform app.require_join_organizer(p_project,false);
 select coalesce(jsonb_agg(to_jsonb(q) order by q.requested_at,q.id),'[]'::jsonb) into v_requests from (
  select j.id,u.display_name,j.requested_at from app.project_join_requests j join public.users u on u.id=j.requester_user_id
  where j.project_id=p_project and j.status='pending' order by j.requested_at,j.id limit 25 offset greatest(0,least(coalesce(p_offset,0),10000))
 ) q;
 return jsonb_build_object('active',exists(select 1 from app.project_join_links where project_id=p_project and revoked_at is null),
 'requests',v_requests,'pending_count',(select count(*) from app.project_join_requests where project_id=p_project and status='pending'));
end $$;

create function public.regenerate_project_join_link(p_project uuid) returns text
language plpgsql security definer set search_path='' as $$ declare token text; begin
 perform app.require_join_organizer(p_project);
 token:=encode(extensions.gen_random_bytes(32),'hex');
 update app.project_join_links set revoked_at=now() where project_id=p_project and revoked_at is null;
 insert into app.project_join_links(project_id,token_hash,created_by_user_id)
 values(p_project,encode(extensions.digest(token,'sha256'),'hex'),auth.uid());
 return token;
end $$;
create function public.disable_project_join_link(p_project uuid) returns void
language plpgsql security definer set search_path='' as $$ begin
 perform app.require_join_organizer(p_project);
 update app.project_join_links set revoked_at=now() where project_id=p_project and revoked_at is null;
end $$;

-- Uniform minimal response: project ID is returned ONLY to an active member.
create function public.resolve_project_join_link(p_token text) returns jsonb
language plpgsql stable security definer set search_path='' as $$ declare l app.project_join_links%rowtype; s text; begin
 if p_token is null or p_token !~ '^[0-9a-f]{64}$' then return jsonb_build_object('state','unavailable'); end if;
 select j.* into l from app.project_join_links j join public.projects p on p.id=j.project_id
 where j.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and j.revoked_at is null and p.deleted_at is null and p.status<>'archived';
 if not found then return jsonb_build_object('state','unavailable'); end if;
 if auth.uid() is null then return jsonb_build_object('state','sign_in'); end if;
 if app.is_member(l.project_id) then return jsonb_build_object('state','member','project_id',l.project_id); end if;
 select status into s from app.project_join_requests where project_id=l.project_id and requester_user_id=auth.uid() and status='pending';
 return jsonb_build_object('state',case when s='pending' then 'pending' else 'eligible' end);
end $$;
create function public.request_project_access(p_token text) returns jsonb
language plpgsql security definer set search_path='' as $$ declare l app.project_join_links%rowtype; r uuid; begin
 if auth.uid() is null then raise exception 'orchestr:auth_required:Sign in to request access.' using errcode='42501'; end if;
 if p_token is null or p_token !~ '^[0-9a-f]{64}$' then raise exception 'orchestr:join_unavailable:This join link is no longer available.'; end if;
 select * into l from app.project_join_links where token_hash=encode(extensions.digest(p_token,'sha256'),'hex');
 if not found then raise exception 'orchestr:join_unavailable:This join link is no longer available.'; end if;
 perform 1 from public.projects where id=l.project_id and deleted_at is null and status<>'archived' for update;
 if not found or not exists(select 1 from app.project_join_links where id=l.id and revoked_at is null) then raise exception 'orchestr:join_unavailable:This join link is no longer available.'; end if;
 if app.is_member(l.project_id) then return jsonb_build_object('state','member','project_id',l.project_id); end if;
 if exists(select 1 from app.project_join_requests where project_id=l.project_id and requester_user_id=auth.uid() and status='pending') then return jsonb_build_object('state','pending'); end if;
 if (select count(*) from app.project_join_requests where project_id=l.project_id and status='pending')>=100
 or (select count(*) from app.project_join_requests where project_id=l.project_id and requester_user_id=auth.uid() and requested_at>now()-interval '1 day')>=5 then
 raise exception 'orchestr:rate_limited:Please try requesting access later.'; end if;
 insert into app.project_join_requests(project_id,join_link_id,requester_user_id) values(l.project_id,l.id,auth.uid()) returning id into r;
 perform app.emit_domain_event('project.join_requested',l.project_id,r,'{}','requested');
 return jsonb_build_object('state','pending');
end $$;

create function public.review_project_join_request(p_request uuid,p_approve boolean) returns void
language plpgsql security definer set search_path='' as $$
declare j app.project_join_requests%rowtype; m uuid; v_email text; v_name text; old_bypass text; begin
 if p_approve is null then raise exception 'orchestr:validation:Choose Approve or Decline.'; end if;
 select * into j from app.project_join_requests where id=p_request;
 if not found then raise exception 'orchestr:not_authorized:Access request unavailable.' using errcode='42501'; end if;
 perform app.require_join_organizer(j.project_id);
 select * into j from app.project_join_requests where id=p_request for update;
 if j.status=(case when p_approve then 'approved' else 'declined' end) then return; end if;
 if j.status<>'pending' then raise exception 'orchestr:already_reviewed:This request has already been reviewed.'; end if;
 if not p_approve then
  update app.project_join_requests set status='declined',reviewed_at=now(),reviewed_by_user_id=auth.uid() where id=j.id;
  return;
 end if;
 select id into m from public.project_members where project_id=j.project_id and user_id=j.requester_user_id and status='active' and deleted_at is null;
 if m is not null then
  -- Direct invitation or another authoritative path already activated this user.
  update app.project_join_requests set status='approved',reviewed_at=now(),reviewed_by_user_id=auth.uid(),member_id=m where id=j.id;
  return;
 end if;
 select lower(a.email),coalesce(nullif(btrim(u.display_name),''),split_part(a.email,'@',1)) into v_email,v_name
 from public.users u join auth.users a on a.id=u.id where u.id=j.requester_user_id;
 if not found then raise exception 'orchestr:not_found:Requester is no longer available.'; end if;
 select id into m from public.project_members where project_id=j.project_id and user_id=j.requester_user_id;
 old_bypass:=current_setting('app.bypass_member_guard',true);
 perform set_config('app.bypass_member_guard','on',true);
 if m is not null then
  update public.project_members set status='active',role='member',deleted_at=null,joined_at=now() where id=m;
 else
  select id into m from public.project_members where project_id=j.project_id and user_id is null and lower(email)=v_email and status<>'removed' and deleted_at is null limit 1;
  if m is not null then
   update public.project_members set user_id=j.requester_user_id,role='member',status='active',joined_at=now() where id=m;
  else
   insert into public.project_members(project_id,user_id,display_name,email,role,status,joined_at)
   values(j.project_id,j.requester_user_id,left(v_name,80),v_email,'member','active',now()) returning id into m;
  end if;
 end if;
 perform set_config('app.bypass_member_guard',coalesce(old_bypass,''),true);
 update app.project_join_requests set status='approved',reviewed_at=now(),reviewed_by_user_id=auth.uid(),member_id=m where id=j.id;
 perform app.emit_domain_event('project.member_approved',j.project_id,j.id,'{}','approved');
end $$;

revoke all on function app.tg_audit_join_link(),app.require_join_organizer(uuid,boolean) from public,anon,authenticated,service_role;
revoke all on function public.get_project_join_access(uuid,integer),public.regenerate_project_join_link(uuid),public.disable_project_join_link(uuid),public.resolve_project_join_link(text),public.request_project_access(text),public.review_project_join_request(uuid,boolean) from public,anon,authenticated,service_role;
grant execute on function public.resolve_project_join_link(text) to anon,authenticated;
grant execute on function public.get_project_join_access(uuid,integer),public.regenerate_project_join_link(uuid),public.disable_project_join_link(uuid),public.request_project_access(text),public.review_project_join_request(uuid,boolean) to authenticated;
