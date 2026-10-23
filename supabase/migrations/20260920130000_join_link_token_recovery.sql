-- Recover current join credentials only through the existing organiser RPC.
-- Vault is already supported by Supabase; the key is not in this migration.
create extension if not exists supabase_vault with schema vault;
do $$ begin
 if exists(select 1 from app.project_join_links where revoked_at is null) then
  raise exception 'Active hash-only join links cannot be recovered. Resolve legacy links before applying this migration.';
 end if;
 if not exists(select 1 from vault.secrets where name='orchestrio.project_join_token_key') then
  perform vault.create_secret(encode(extensions.gen_random_bytes(32),'hex'),'orchestrio.project_join_token_key','Encrypt private Orchestrio join tokens');
 end if;
end $$;
alter table app.project_join_links add column token_ciphertext bytea;
alter table app.project_join_links add constraint project_join_links_active_ciphertext
 check(revoked_at is not null or token_ciphertext is not null);
-- No table grants or Vault grants change. app remains FORCE RLS and client-inaccessible.
create or replace function app.tg_audit_join_link() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.audit_log(project_id,actor_user_id,actor_member_id,source,action,entity_type,entity_id,before,after)
 values(new.project_id,auth.uid(),app.current_member_id(new.project_id),'rpc',
 case when tg_op='INSERT' then 'create'::public.audit_action else 'update'::public.audit_action end,
 'project_join_links',new.id,case when tg_op='UPDATE' then to_jsonb(old)-'token_hash'-'token_ciphertext' end,to_jsonb(new)-'token_hash'-'token_ciphertext');
 return new;
end $$;
create or replace function public.get_project_join_access(p_project uuid,p_offset integer default 0) returns jsonb
language plpgsql security definer set search_path='' as $$ declare v_requests jsonb; v_token text; begin
 perform app.require_join_organizer(p_project,false);
 select coalesce(jsonb_agg(to_jsonb(q) order by q.requested_at,q.id),'[]'::jsonb) into v_requests from (
  select j.id,u.display_name,j.requested_at from app.project_join_requests j join public.users u on u.id=j.requester_user_id
  where j.project_id=p_project and j.status='pending' order by j.requested_at,j.id limit 25 offset greatest(0,least(coalesce(p_offset,0),10000))
 ) q;
 select extensions.pgp_sym_decrypt(l.token_ciphertext,k.decrypted_secret) into v_token
 from app.project_join_links l cross join vault.decrypted_secrets k
 where l.project_id=p_project and l.revoked_at is null and k.name='orchestrio.project_join_token_key';
 return jsonb_build_object('token',v_token,'active',exists(select 1 from app.project_join_links where project_id=p_project and revoked_at is null),
 'requests',v_requests,'pending_count',(select count(*) from app.project_join_requests where project_id=p_project and status='pending'));
end $$;

create or replace function public.regenerate_project_join_link(p_project uuid) returns text
language plpgsql security definer set search_path='' as $$ declare token text; v_key text; begin
 perform app.require_join_organizer(p_project);
 select decrypted_secret into strict v_key from vault.decrypted_secrets where name='orchestrio.project_join_token_key';
 token:=encode(extensions.gen_random_bytes(32),'hex');
 update app.project_join_links set revoked_at=now(),token_ciphertext=null where project_id=p_project and revoked_at is null;
 insert into app.project_join_links(project_id,token_hash,created_by_user_id,token_ciphertext)
 values(p_project,encode(extensions.digest(token,'sha256'),'hex'),auth.uid(),extensions.pgp_sym_encrypt(token,v_key,'cipher-algo=aes256'));
 return token;
end $$;
create or replace function public.disable_project_join_link(p_project uuid) returns void
language plpgsql security definer set search_path='' as $$ begin
 perform app.require_join_organizer(p_project);
 update app.project_join_links set revoked_at=now(),token_ciphertext=null where project_id=p_project and revoked_at is null;
end $$;

