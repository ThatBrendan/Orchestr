-- Personal routing preferences only. No financial views, ledger or settlement changes.
create function app.normalize_payment_link(p_provider text,p_url text) returns text
language plpgsql immutable set search_path='' as $$
declare u text:=btrim(p_url,E' \t\r\n'); parts text[]; host text; suffix text; label text;
begin
 if p_provider is null or p_provider not in('monzo','revolut','custom') then raise exception 'orchestr:payment_link_provider:Choose a supported payment provider.'; end if;
 if u is null or length(u)=0 or length(u)>2048 then raise exception 'orchestr:payment_link_url:Enter a payment link of at most 2048 characters.'; end if;
 -- Restricted URI parser: split scheme/authority/tail, then validate each component.
 parts:=regexp_match(u,'^([A-Za-z][A-Za-z0-9+.-]*)://([^/?#]+)(.*)$');
 if parts is null or lower(parts[1])<>'https' then raise exception 'orchestr:payment_link_url:Use an HTTPS payment link.'; end if;
 host:=lower(parts[2]); suffix:=parts[3];
 if length(host)>253 or host !~ '^[a-z0-9.-]+$' or host !~ '\.[a-z]{2,63}$'
 or host ~ '(^|\.)(localhost|local|internal|lan|home|test|invalid|onion|arpa)$' then
 raise exception 'orchestr:payment_link_url:Use a public website address without an IP address, port or login details.'; end if;
 foreach label in array string_to_array(host,'.') loop
  if length(label)>63 or label !~ '^[a-z0-9]([a-z0-9-]*[a-z0-9])?$' then raise exception 'orchestr:payment_link_url:That website address is not valid.'; end if;
 end loop;
 if suffix !~ '^[A-Za-z0-9._~:/?#@!$&''()*+,;=%-]*$' or regexp_replace(suffix,'%[0-9A-Fa-f]{2}','','g') like '%\%%' escape '\' then
 raise exception 'orchestr:payment_link_url:That payment link contains invalid characters.'; end if;
 if p_provider in('monzo','revolut') and (host<>case p_provider when 'monzo' then 'monzo.me' else 'revolut.me' end or suffix !~ '^/[^/?#]+') then
 raise exception 'orchestr:payment_link_url:Use your personal payment link from the selected provider.'; end if;
 return 'https://'||host||suffix;
end $$;
revoke all on function app.normalize_payment_link(text,text) from public,anon,authenticated,service_role;
create table public.user_payment_links(
 id uuid primary key default gen_random_uuid(),user_id uuid not null references public.users(id),
 provider text not null check(provider in('monzo','revolut','custom')),
 payment_url text not null,display_label text not null check(length(btrim(display_label)) between 1 and 60),
 is_enabled boolean not null default true,is_default boolean not null default false,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),deleted_at timestamptz,
 check(not is_default or (is_enabled and deleted_at is null))
);
create unique index user_payment_links_default on public.user_payment_links(user_id) where is_default and deleted_at is null;
create index user_payment_links_owner on public.user_payment_links(user_id,created_at) where deleted_at is null;
alter table public.user_payment_links enable row level security;
alter table public.user_payment_links force row level security;
revoke all on public.user_payment_links from public,anon,authenticated,service_role;
grant select on public.user_payment_links to authenticated;
create policy payment_links_owner_read on public.user_payment_links for select to authenticated using(user_id=auth.uid() and deleted_at is null);
create function app.guard_payment_link() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='UPDATE' and (new.id,new.user_id,new.created_at) is distinct from (old.id,old.user_id,old.created_at) then raise exception 'orchestr:immutable_column:Payment link ownership cannot change.'; end if;
 new.payment_url:=app.normalize_payment_link(new.provider,new.payment_url);
 new.updated_at:=now(); return new;
end $$;
create trigger payment_link_guard before insert or update on public.user_payment_links for each row execute function app.guard_payment_link();
create function app.audit_payment_link() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.audit_log(project_id,actor_user_id,actor_member_id,source,action,entity_type,entity_id,before,after)
 values(null,auth.uid(),null,'rpc',case when tg_op='INSERT' then 'create'::public.audit_action when old.deleted_at is null and new.deleted_at is not null then 'soft_delete'::public.audit_action else 'update'::public.audit_action end,'user_payment_links',new.id,
 case when tg_op='INSERT' then null else to_jsonb(old)-array['payment_url','display_label'] end,to_jsonb(new)-array['payment_url','display_label']); return new;
end $$;
create trigger payment_link_audit after insert or update on public.user_payment_links for each row execute function app.audit_payment_link();
revoke all on function app.guard_payment_link(),app.audit_payment_link() from public,anon,authenticated,service_role;
create function public.list_my_payment_links() returns setof public.user_payment_links
language sql stable security invoker set search_path='' as $$ select * from public.user_payment_links order by is_default desc,created_at,id; $$;
create function public.save_my_payment_link(p_provider text,p_url text,p_label text default null,p_id uuid default null,p_enabled boolean default true) returns uuid
language plpgsql security definer set search_path='' as $$
declare owner uuid:=auth.uid(); result uuid; label text; normalized text;
begin
 if owner is null then raise exception 'orchestr:auth_required:Sign in to manage payment links.' using errcode='42501'; end if;
 perform 1 from public.users where id=owner for update;
 if p_id is not null and not exists(select 1 from public.user_payment_links where id=p_id and user_id=owner and deleted_at is null) then raise exception 'orchestr:not_authorized:You can only manage your own payment links.' using errcode='42501'; end if;
 normalized:=app.normalize_payment_link(p_provider,p_url);
 label:=case p_provider when 'monzo' then 'Monzo' when 'revolut' then 'Revolut' else btrim(p_label) end;
 if label is null or length(label) not between 1 and 60 or label ~ '[[:cntrl:]]' or p_enabled is null then raise exception 'orchestr:payment_link_label:Enter a label of 1 to 60 characters.'; end if;
 if p_id is null then
 insert into public.user_payment_links(user_id,provider,payment_url,display_label,is_enabled) values(owner,p_provider,normalized,label,p_enabled) returning id into result;
 else
 update public.user_payment_links set provider=p_provider,payment_url=normalized,display_label=label,is_enabled=p_enabled,is_default=is_default and p_enabled where id=p_id returning id into result;
 end if; return result;
end $$;
create function public.delete_my_payment_link(p_id uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'orchestr:auth_required:Sign in to manage payment links.' using errcode='42501'; end if;
 perform 1 from public.users where id=auth.uid() for update;
 if not exists(select 1 from public.user_payment_links where id=p_id and user_id=auth.uid()) then raise exception 'orchestr:not_authorized:You can only manage your own payment links.' using errcode='42501'; end if;
 update public.user_payment_links set deleted_at=now(),is_enabled=false,is_default=false where id=p_id and deleted_at is null;
end $$;
create function public.set_default_payment_link(p_id uuid default null) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'orchestr:auth_required:Sign in to manage payment links.' using errcode='42501'; end if;
 perform 1 from public.users where id=auth.uid() for update;
 if p_id is not null and not exists(select 1 from public.user_payment_links where id=p_id and user_id=auth.uid() and is_enabled and deleted_at is null) then raise exception 'orchestr:not_authorized:Choose one of your enabled payment links.' using errcode='42501'; end if;
 update public.user_payment_links set is_default=false where user_id=auth.uid() and is_default;
 update public.user_payment_links set is_default=true where id=p_id;
end $$;
create function public.get_reimbursement_payment_options(p_request uuid)
returns table(id uuid,provider text,payment_url text,display_label text,is_default boolean)
language sql stable security definer set search_path='' as $$
 select l.id,l.provider,l.payment_url,l.display_label,l.is_default
 from public.reimbursement_requests r join public.projects p on p.id=r.project_id
 join public.project_members debtor on debtor.id=r.debtor_member_id
 join public.project_members creditor on creditor.id=r.creditor_member_id
 join public.user_payment_links l on l.user_id=creditor.user_id
 where r.id=p_request and app.can_read_reimbursement(r.id) and r.status='open'
 and not app.reimbursement_needs_review(r.id) and p.status<>'archived'
 and debtor.user_id=auth.uid() and debtor.status='active' and debtor.deleted_at is null
 and creditor.status='active' and creditor.deleted_at is null
 and l.is_enabled and l.deleted_at is null
 order by l.is_default desc,l.created_at,l.id;
$$;
revoke all on function public.list_my_payment_links(),public.save_my_payment_link(text,text,text,uuid,boolean),public.delete_my_payment_link(uuid),public.set_default_payment_link(uuid),public.get_reimbursement_payment_options(uuid) from public,anon,service_role;
grant execute on function public.list_my_payment_links(),public.save_my_payment_link(text,text,text,uuid,boolean),public.delete_my_payment_link(uuid),public.set_default_payment_link(uuid),public.get_reimbursement_payment_options(uuid) to authenticated;
