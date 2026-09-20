-- Share links are routing envelopes, never memberships or alternate content APIs.
-- A separate Vault key isolates share-key rotation from join links; crypto is shared.
select vault.create_secret(encode(extensions.gen_random_bytes(32),'hex'),
 'orchestrio.resource_share_token_key','Encrypt private resource share tokens')
where not exists(select 1 from vault.secrets where name='orchestrio.resource_share_token_key');

create function app.bearer_token_valid(p_token text) returns boolean
language sql immutable set search_path='' as $$ select coalesce(p_token ~ '^[0-9a-f]{64}$',false) $$;
create function app.bearer_token_generate() returns text
language sql volatile set search_path='' as $$ select encode(extensions.gen_random_bytes(32),'hex') $$;
create function app.bearer_token_hash(p_token text) returns text
language sql immutable set search_path='' as $$ select encode(extensions.digest(p_token,'sha256'),'hex') $$;
create function app.bearer_token_encrypt(p_token text,p_purpose text) returns bytea
language plpgsql security definer set search_path='' as $$ declare k text; begin
 if p_purpose not in ('project_join','resource_share') or p_purpose is null or not app.bearer_token_valid(p_token) then
  raise exception 'Unsupported bearer token context' using errcode='22023'; end if;
 select decrypted_secret into strict k from vault.decrypted_secrets where name='orchestrio.'||p_purpose||'_token_key';
 return extensions.pgp_sym_encrypt(p_token,k,'cipher-algo=aes256');
end $$;
create function app.bearer_token_decrypt(p_ciphertext bytea,p_purpose text) returns text
language plpgsql security definer set search_path='' as $$ declare k text; begin
 if p_purpose not in ('project_join','resource_share') or p_purpose is null then
  raise exception 'Unsupported bearer token context' using errcode='22023'; end if;
 if p_ciphertext is null then return null; end if;
 select decrypted_secret into strict k from vault.decrypted_secrets where name='orchestrio.'||p_purpose||'_token_key';
 return extensions.pgp_sym_decrypt(p_ciphertext,k);
end $$;
revoke all on function app.bearer_token_valid(text),app.bearer_token_generate(),app.bearer_token_hash(text),
 app.bearer_token_encrypt(text,text),app.bearer_token_decrypt(bytea,text) from public,anon,authenticated,service_role;

create table app.resource_share_policies (
 resource_type text not null,
 access_mode text not null check(access_mode='member_only'),
 handler text not null check(handler='activity_member_v1'),
 requires_auth boolean not null default true check(requires_auth),
 requires_membership boolean not null default true check(requires_membership),
 primary key(resource_type,access_mode),
 check(resource_type='activity' and handler='activity_member_v1')
);
insert into app.resource_share_policies(resource_type,access_mode,handler) values('activity','member_only','activity_member_v1');
create table app.resource_share_links (
 id uuid primary key default gen_random_uuid(),
 project_id uuid not null references public.projects(id),
 resource_type text not null,
 resource_id uuid not null,
 access_mode text not null default 'member_only',
 token_hash text not null unique check(token_hash ~ '^[0-9a-f]{64}$'),
 token_ciphertext bytea,
 created_by_user_id uuid not null references public.users(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 expires_at timestamptz,
 revoked_at timestamptz,
 foreign key(resource_type,access_mode) references app.resource_share_policies(resource_type,access_mode),
 check(revoked_at is not null or token_ciphertext is not null),
 check(expires_at is null or expires_at>created_at)
);
create unique index resource_share_links_one_current on app.resource_share_links(resource_type,resource_id,access_mode) where revoked_at is null;
create index resource_share_links_project on app.resource_share_links(project_id);
alter table app.resource_share_policies enable row level security;
alter table app.resource_share_policies force row level security;
alter table app.resource_share_links enable row level security;
alter table app.resource_share_links force row level security;
revoke all on app.resource_share_policies,app.resource_share_links from public,anon,authenticated,service_role;

-- This is the reviewed resource policy boundary. Registration alone cannot execute a
-- new handler. No dynamic tables/functions/SQL; each new handler needs a forward migration.
-- Activity SELECT RLS uses app.is_member(project_id) and deleted_at is null. Match it,
-- also reject deleted parents, and never use the token itself as an authorization input.
create function app.share_resource_policy(p_type text,p_resource uuid,p_mode text default 'member_only')
returns table(project_id uuid,can_read boolean,can_manage boolean,writable boolean)
language plpgsql stable security definer set search_path='' as $$ declare h text; begin
 select handler into h from app.resource_share_policies where resource_type=p_type and access_mode=p_mode;
 case h
 when 'activity_member_v1' then
  return query select c.project_id,app.is_member(c.project_id),
   app.has_role(c.project_id,array['organizer','member']::public.member_role[]),p.status<>'archived'
  from public.commitments c join public.projects p on p.id=c.project_id
  where c.id=p_resource and c.deleted_at is null and p.deleted_at is null;
 else return;
 end case;
end $$;
create function app.require_share_manager(p_type text,p_resource uuid,p_write boolean) returns uuid
language plpgsql security definer set search_path='' as $$ declare r record; begin
 select * into r from app.share_resource_policy(p_type,p_resource);
 if not found or auth.uid() is null or not r.can_read or not r.can_manage then
  raise exception 'orchestr:not_authorized:This shared item is unavailable.' using errcode='42501'; end if;
 -- Serialize all mutations/recovery with project lifecycle and other managers.
 perform 1 from public.projects where id=r.project_id for update;
 select * into r from app.share_resource_policy(p_type,p_resource);
 if not found or not r.can_read or not r.can_manage then
  raise exception 'orchestr:not_authorized:This shared item is unavailable.' using errcode='42501'; end if;
 if p_write and not r.writable then
  raise exception 'orchestr:project_archived:This project is read-only.' using errcode='42501'; end if;
 return r.project_id;
end $$;
create function app.tg_audit_resource_share_link() returns trigger
language plpgsql security definer set search_path='' as $$ begin
 insert into public.audit_log(project_id,actor_user_id,actor_member_id,source,action,entity_type,entity_id,before,after)
 values(new.project_id,auth.uid(),app.current_member_id(new.project_id),'rpc',
 case when tg_op='INSERT' then 'create'::public.audit_action else 'update'::public.audit_action end,
 'resource_share_links',new.id,
 case when tg_op='UPDATE' then to_jsonb(old)-array['token_hash','token_ciphertext'] end,
 to_jsonb(new)-array['token_hash','token_ciphertext']);
 return new;
end $$;
create trigger audit after insert or update on app.resource_share_links for each row execute function app.tg_audit_resource_share_link();

create function public.get_resource_share_link(p_resource_type text,p_resource_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$ declare p uuid; l app.resource_share_links%rowtype; begin
 p:=app.require_share_manager(p_resource_type,p_resource_id,false);
 select * into l from app.resource_share_links where project_id=p and resource_type=p_resource_type
  and resource_id=p_resource_id and access_mode='member_only' and revoked_at is null
  and (expires_at is null or expires_at>statement_timestamp());
 if not found then return jsonb_build_object('active',false,'token',null); end if;
 return jsonb_build_object('active',true,'token',app.bearer_token_decrypt(l.token_ciphertext,'resource_share'));
end $$;
-- Internal lifecycle helper: create is idempotent, regeneration explicitly rotates.
create function app.issue_resource_share_link(p_type text,p_resource uuid,p_rotate boolean) returns text
language plpgsql security definer set search_path='' as $$ declare p uuid; l app.resource_share_links%rowtype; t text; begin
 p:=app.require_share_manager(p_type,p_resource,true);
 select * into l from app.resource_share_links where project_id=p and resource_type=p_type
  and resource_id=p_resource and access_mode='member_only' and revoked_at is null;
 if found and not p_rotate and (l.expires_at is null or l.expires_at>statement_timestamp()) then
  return app.bearer_token_decrypt(l.token_ciphertext,'resource_share');
 end if;
 update app.resource_share_links set revoked_at=now(),updated_at=now(),token_ciphertext=null
 where project_id=p and resource_type=p_type and resource_id=p_resource and access_mode='member_only' and revoked_at is null;
 t:=app.bearer_token_generate();
 insert into app.resource_share_links(project_id,resource_type,resource_id,token_hash,token_ciphertext,created_by_user_id)
 values(p,p_type,p_resource,app.bearer_token_hash(t),app.bearer_token_encrypt(t,'resource_share'),auth.uid());
 return t;
end $$;
create function public.create_resource_share_link(p_resource_type text,p_resource_id uuid) returns text
language sql security definer set search_path='' as $$ select app.issue_resource_share_link(p_resource_type,p_resource_id,false) $$;
create function public.regenerate_resource_share_link(p_resource_type text,p_resource_id uuid) returns text
language sql security definer set search_path='' as $$ select app.issue_resource_share_link(p_resource_type,p_resource_id,true) $$;
create function public.disable_resource_share_link(p_resource_type text,p_resource_id uuid) returns void
language plpgsql security definer set search_path='' as $$ declare p uuid; begin
 p:=app.require_share_manager(p_resource_type,p_resource_id,true);
 update app.resource_share_links set revoked_at=now(),updated_at=now(),token_ciphertext=null
 where project_id=p and resource_type=p_resource_type and resource_id=p_resource_id and access_mode='member_only' and revoked_at is null;
end $$;

create function public.resolve_shared_resource(p_token text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare l app.resource_share_links%rowtype; policy app.resource_share_policies%rowtype; r record; begin
 if not app.bearer_token_valid(p_token) then return jsonb_build_object('state','unavailable'); end if;
 select * into l from app.resource_share_links where token_hash=app.bearer_token_hash(p_token)
  and revoked_at is null and (expires_at is null or expires_at>statement_timestamp());
 if not found then return jsonb_build_object('state','unavailable'); end if;
 select * into policy from app.resource_share_policies where resource_type=l.resource_type and access_mode=l.access_mode;
 if not found then return jsonb_build_object('state','unavailable'); end if;
 select * into r from app.share_resource_policy(l.resource_type,l.resource_id,l.access_mode);
 if not found or r.project_id is distinct from l.project_id then return jsonb_build_object('state','unavailable'); end if;
 if policy.requires_auth and auth.uid() is null then return jsonb_build_object('state','sign_in'); end if;
 if (policy.requires_membership and not app.is_member(l.project_id)) or not r.can_read then
  return jsonb_build_object('state','unavailable'); end if;
 -- Route identifiers only. No content, project title, extra rights, or arbitrary destination.
 return jsonb_build_object('state','authorized','resource_type',l.resource_type,'resource_id',l.resource_id,'project_id',l.project_id);
end $$;
revoke all on function app.share_resource_policy(text,uuid,text),app.require_share_manager(text,uuid,boolean),
 app.issue_resource_share_link(text,uuid,boolean),app.tg_audit_resource_share_link() from public,anon,authenticated,service_role;
revoke all on function public.get_resource_share_link(text,uuid),public.create_resource_share_link(text,uuid),
 public.regenerate_resource_share_link(text,uuid),public.disable_resource_share_link(text,uuid),public.resolve_shared_resource(text)
 from public,anon,authenticated,service_role;
grant execute on function public.get_resource_share_link(text,uuid),public.create_resource_share_link(text,uuid),
 public.regenerate_resource_share_link(text,uuid),public.disable_resource_share_link(text,uuid) to authenticated;
grant execute on function public.resolve_shared_resource(text) to anon,authenticated;

-- Phase 2 uses the same private crypto helpers; signatures, ACLs and semantics retained.
create or replace function public.get_project_join_access(p_project uuid,p_offset integer default 0) returns jsonb
language plpgsql security definer set search_path='' as $$ declare v_requests jsonb; v_token text; begin
 perform app.require_join_organizer(p_project,false);
 select coalesce(jsonb_agg(to_jsonb(q) order by q.requested_at,q.id),'[]'::jsonb) into v_requests from (
  select j.id,u.display_name,j.requested_at from app.project_join_requests j join public.users u on u.id=j.requester_user_id
  where j.project_id=p_project and j.status='pending' order by j.requested_at,j.id limit 25 offset greatest(0,least(coalesce(p_offset,0),10000))
 ) q;
 select app.bearer_token_decrypt(l.token_ciphertext,'project_join') into v_token
 from app.project_join_links l
 where l.project_id=p_project and l.revoked_at is null;
 return jsonb_build_object('token',v_token,'active',exists(select 1 from app.project_join_links where project_id=p_project and revoked_at is null),
 'requests',v_requests,'pending_count',(select count(*) from app.project_join_requests where project_id=p_project and status='pending'));
end $$;

create or replace function public.regenerate_project_join_link(p_project uuid) returns text
language plpgsql security definer set search_path='' as $$ declare token text; begin
 perform app.require_join_organizer(p_project);
 token:=app.bearer_token_generate();
 update app.project_join_links set revoked_at=now(),token_ciphertext=null where project_id=p_project and revoked_at is null;
 insert into app.project_join_links(project_id,token_hash,created_by_user_id,token_ciphertext)
 values(p_project,app.bearer_token_hash(token),auth.uid(),app.bearer_token_encrypt(token,'project_join'));
 return token;
end $$;
create or replace function public.resolve_project_join_link(p_token text) returns jsonb
language plpgsql stable security definer set search_path='' as $$ declare l app.project_join_links%rowtype; s text; begin
 if not app.bearer_token_valid(p_token) then return jsonb_build_object('state','unavailable'); end if;
 select j.* into l from app.project_join_links j join public.projects p on p.id=j.project_id
 where j.token_hash=app.bearer_token_hash(p_token) and j.revoked_at is null and p.deleted_at is null and p.status<>'archived';
 if not found then return jsonb_build_object('state','unavailable'); end if;
 if auth.uid() is null then return jsonb_build_object('state','sign_in'); end if;
 if app.is_member(l.project_id) then return jsonb_build_object('state','member','project_id',l.project_id); end if;
 select status into s from app.project_join_requests where project_id=l.project_id and requester_user_id=auth.uid() and status='pending';
 return jsonb_build_object('state',case when s='pending' then 'pending' else 'eligible' end);
end $$;
create or replace function public.request_project_access(p_token text) returns jsonb
language plpgsql security definer set search_path='' as $$ declare l app.project_join_links%rowtype; r uuid; begin
 if auth.uid() is null then raise exception 'orchestr:auth_required:Sign in to request access.' using errcode='42501'; end if;
 if not app.bearer_token_valid(p_token) then raise exception 'orchestr:join_unavailable:This join link is no longer available.'; end if;
 select * into l from app.project_join_links where token_hash=app.bearer_token_hash(p_token);
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

