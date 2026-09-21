-- Contextual history for two explicitly supported resources. No notification rule.
create table public.resource_comments (
 id uuid primary key default gen_random_uuid(),
 project_id uuid not null references public.projects(id),
 resource_type text not null check(resource_type in ('activity','decision')),
 resource_id uuid not null,
 author_user_id uuid not null references public.users(id),
 author_name text not null,
 body text not null check(length(body) between 1 and 4000 and body ~ '[^[:space:]]'),
 created_at timestamptz not null default clock_timestamp(),
 deleted_at timestamptz
);
create index resource_comments_page on public.resource_comments(resource_type,resource_id,created_at desc,id desc) where deleted_at is null;
alter table public.resource_comments enable row level security;
alter table public.resource_comments force row level security;
revoke all on public.resource_comments from public,anon,authenticated,service_role;
grant select on public.resource_comments to authenticated;
create policy resource_comments_read on public.resource_comments for select to authenticated using (
 deleted_at is null and app.is_member(project_id)
 and exists(select 1 from public.projects p where p.id=resource_comments.project_id and p.deleted_at is null)
 and ((resource_type='activity' and exists(select 1 from public.commitments c where c.id=resource_id and c.project_id=resource_comments.project_id and c.deleted_at is null))
 or (resource_type='decision' and exists(select 1 from public.decisions d where d.id=resource_id and d.project_id=resource_comments.project_id and d.deleted_at is null)))
);

-- Static resolver, independent of share links. Lock order matches project/domain writes.
create function app.require_comment_resource(p_type text,p_resource uuid,p_write boolean default false)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_project uuid; v_status public.project_status; begin
 if p_type='activity' then
  select project_id into v_project from public.commitments where id=p_resource and deleted_at is null;
 elsif p_type='decision' then
  select project_id into v_project from public.decisions where id=p_resource and deleted_at is null;
 end if;
 if v_project is null or auth.uid() is null or not app.is_member(v_project) then
  raise exception 'orchestr:not_authorized:This item is no longer available.' using errcode='42501';
 end if;
 if p_write then
  select status into v_status from public.projects where id=v_project and deleted_at is null for update;
 else
  select status into v_status from public.projects where id=v_project and deleted_at is null;
 end if;
 if not found or not app.is_member(v_project) then raise exception 'orchestr:not_authorized:This item is no longer available.' using errcode='42501'; end if;
 if p_write and v_status='archived' then raise exception 'orchestr:project_archived:Comments cannot be changed while this project is archived.' using errcode='42501'; end if;
 if p_type='activity' then
  if p_write then perform 1 from public.commitments where id=p_resource and project_id=v_project and deleted_at is null for update;
  else perform 1 from public.commitments where id=p_resource and project_id=v_project and deleted_at is null; end if;
 else
  if p_write then perform 1 from public.decisions where id=p_resource and project_id=v_project and deleted_at is null for update;
  else perform 1 from public.decisions where id=p_resource and project_id=v_project and deleted_at is null; end if;
 end if;
 if not found then raise exception 'orchestr:not_authorized:This item is no longer available.' using errcode='42501'; end if;
 return v_project;
end $$;

-- Retain metadata audit history, not a second copy of conversational text.
create function app.tg_audit_resource_comment() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.audit_log(project_id,actor_user_id,actor_member_id,source,action,entity_type,entity_id,before,after)
 values(new.project_id,auth.uid(),app.current_member_id(new.project_id),'rpc',
 case when tg_op='INSERT' then 'create'::public.audit_action else 'soft_delete'::public.audit_action end,
 'resource_comments',new.id,case when tg_op='UPDATE' then to_jsonb(old)-'body'-'author_name' end,to_jsonb(new)-'body'-'author_name');
 return new;
end $$;
create trigger audit after insert or update on public.resource_comments for each row execute function app.tg_audit_resource_comment();

create function public.create_resource_comment(p_resource_type text,p_resource_id uuid,p_body text,p_id uuid default gen_random_uuid())
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_project uuid; v_body text; r public.resource_comments%rowtype; v_name text; begin
 v_project:=app.require_comment_resource(p_resource_type,p_resource_id,true);
 v_body:=regexp_replace(p_body,'^[[:space:]]+|[[:space:]]+$','','g');
 if v_body is null or length(v_body) not between 1 and 4000 then raise exception 'orchestr:validation:Enter a comment between 1 and 4000 characters.' using errcode='22023'; end if;
 select * into r from public.resource_comments where id=p_id;
 if found then
  if r.project_id=v_project and r.resource_type=p_resource_type and r.resource_id=p_resource_id and r.author_user_id=auth.uid() and r.body=v_body and r.deleted_at is null then
   return to_jsonb(r)-'deleted_at'||jsonb_build_object('can_delete',true);
  end if;
  raise exception 'orchestr:conflict:This comment request is no longer available.' using errcode='22023';
 end if;
 select coalesce(nullif(btrim(display_name),''),'Member') into v_name from public.users where id=auth.uid();
 insert into public.resource_comments(id,project_id,resource_type,resource_id,author_user_id,author_name,body)
 values(p_id,v_project,p_resource_type,p_resource_id,auth.uid(),coalesce(v_name,'Member'),v_body) returning * into r;
 perform app.emit_domain_event('comment.created',v_project,r.id,jsonb_build_object('parent_resource_type',r.resource_type,'parent_resource_id',r.resource_id),'created');
 return to_jsonb(r)-'deleted_at'||jsonb_build_object('can_delete',true);
end $$;

-- Context arguments prevent using a comment ID through a different resource thread.
create function public.delete_resource_comment(p_resource_type text,p_resource_id uuid,p_comment uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_project uuid; r public.resource_comments%rowtype; begin
 v_project:=app.require_comment_resource(p_resource_type,p_resource_id,true);
 select * into r from public.resource_comments where id=p_comment and resource_type=p_resource_type and resource_id=p_resource_id and project_id=v_project for update;
 if not found or (r.author_user_id<>auth.uid() and not app.is_organizer(v_project)) then
  raise exception 'orchestr:not_authorized:You cannot remove this comment.' using errcode='42501'; end if;
 if r.deleted_at is null then update public.resource_comments set deleted_at=clock_timestamp() where id=r.id; end if;
end $$;

create function public.get_resource_comments(p_resource_type text,p_resource_id uuid,p_before_at timestamptz default null,p_before_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_project uuid; v_write boolean; v_items jsonb; v_cursor jsonb; v_more boolean; begin
 v_project:=app.require_comment_resource(p_resource_type,p_resource_id);
 if (p_before_at is null)<>(p_before_id is null) then raise exception 'orchestr:validation:This comment page is unavailable.' using errcode='22023'; end if;
 v_write:=app.is_writable_project(v_project);
 with candidates as (
  select r.* from public.resource_comments r where r.project_id=v_project and r.resource_type=p_resource_type and r.resource_id=p_resource_id and r.deleted_at is null
   and (p_before_at is null or (r.created_at,r.id)<(p_before_at,p_before_id)) order by r.created_at desc,r.id desc limit 21
 ), page as (select * from candidates order by created_at desc,id desc limit 20)
 select coalesce((select jsonb_agg(to_jsonb(p)-'deleted_at'||jsonb_build_object('can_delete',v_write and (p.author_user_id=auth.uid() or app.is_organizer(v_project))) order by p.created_at,p.id) from page p),'[]'::jsonb),
 (select count(*)>20 from candidates),
 (select jsonb_build_object('created_at',created_at,'id',id) from page order by created_at,id limit 1)
 into v_items,v_more,v_cursor;
 return jsonb_build_object('items',v_items,'next_cursor',case when v_more then v_cursor end,'can_comment',v_write);
end $$;
revoke all on function app.require_comment_resource(text,uuid,boolean),app.tg_audit_resource_comment() from public,anon,authenticated,service_role;
revoke all on function public.create_resource_comment(text,uuid,text,uuid),public.delete_resource_comment(text,uuid,uuid),public.get_resource_comments(text,uuid,timestamptz,uuid) from public,anon,authenticated,service_role;
grant execute on function public.create_resource_comment(text,uuid,text,uuid),public.delete_resource_comment(text,uuid,uuid),public.get_resource_comments(text,uuid,timestamptz,uuid) to authenticated;
insert into app.domain_event_types(event_type,resource_type) values('comment.created','comment');
-- Intentionally no automation rule or notification action for comment.created.

create or replace function app.emit_domain_event(p_type text,p_project uuid,p_resource uuid,p_payload jsonb,p_key text)
returns uuid language plpgsql security definer set search_path='' as $$
declare comment_row public.resource_comments%rowtype; d public.decisions%rowtype; c public.commitments%rowtype; v_actor uuid; v_id uuid; prior app.domain_events%rowtype; j app.project_join_requests%rowtype; v_resource_type text;
begin
 if p_type='comment.created' then
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

