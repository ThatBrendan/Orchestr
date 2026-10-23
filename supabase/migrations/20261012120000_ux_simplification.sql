-- Phase 14 UX simplification. Existing authorization, ledger and event rules remain authoritative.
create function public.ensure_project_join_link(p_project uuid) returns text
language plpgsql security definer set search_path='' as $$
declare token text;
begin
 -- Same project lock as disable/regenerate serializes concurrent copy requests.
 perform app.require_join_organizer(p_project);
 select app.bearer_token_decrypt(token_ciphertext,'project_join') into token
 from app.project_join_links where project_id=p_project and revoked_at is null;
 if token is not null then return token; end if;
 return public.regenerate_project_join_link(p_project);
end $$;
revoke all on function public.ensure_project_join_link(uuid) from public,anon,authenticated,service_role;
grant execute on function public.ensure_project_join_link(uuid) to authenticated;

-- Project timezone is read while holding the same project lock as Decision commands.
create function app.decision_end_of_day(p_day date,p_timezone text) returns timestamptz
language sql stable set search_path='' as $$
 select ((p_day + 1)::timestamp at time zone p_timezone) - interval '1 second';
$$;
revoke all on function app.decision_end_of_day(date,text) from public,anon,authenticated,service_role;
create function public.create_decision_date(p_project uuid,p_title text,p_description text,p_deadline_date date,p_options jsonb,p_id uuid default gen_random_uuid()) returns uuid
language plpgsql security definer set search_path='' as $$
declare zone text;
begin
 if not app.has_role(p_project,array['organizer','member']::public.member_role[]) then
  raise exception 'orchestr:not_authorized:You cannot create decisions.' using errcode='42501'; end if;
 select timezone into zone from public.projects where id=p_project and deleted_at is null and status<>'archived' for update;
 if not found then raise exception 'orchestr:project_archived:This project is unavailable or read-only.' using errcode='42501'; end if;
 return public.create_decision(p_project,p_title,p_description,app.decision_end_of_day(p_deadline_date,zone),p_options,p_id);
end $$;
create function public.edit_decision_date(p_decision uuid,p_title text,p_description text,p_deadline_date date,p_options jsonb default null,p_preserve_deadline boolean default false) returns void
language plpgsql security definer set search_path='' as $$
declare d public.decisions%rowtype; zone text; deadline timestamptz;
begin
 d:=app.require_decision(p_decision,true);
 select timezone into zone from public.projects where id=d.project_id;
 deadline:=case when p_preserve_deadline then d.voting_deadline else app.decision_end_of_day(p_deadline_date,zone) end;
 perform public.edit_decision(p_decision,p_title,p_description,deadline,p_options);
end $$;
revoke all on function public.create_decision_date(uuid,text,text,date,jsonb,uuid),public.edit_decision_date(uuid,text,text,date,jsonb,boolean) from public,anon,authenticated,service_role;
grant execute on function public.create_decision_date(uuid,text,text,date,jsonb,uuid),public.edit_decision_date(uuid,text,text,date,jsonb,boolean) to authenticated;

create or replace function app.normalize_payment_link(p_provider text,p_url text) returns text
language plpgsql immutable set search_path='' as $$
declare u text:=btrim(p_url,E' \t\r\n'); parts text[]; host text; suffix text; label text;
begin
 if p_provider is null or p_provider not in('monzo','revolut','paypal','custom') then raise exception 'orchestr:payment_link_provider:Choose a supported payment provider.'; end if;
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
 if p_provider='paypal' and (host<>'paypal.me' or suffix !~ '^/[A-Za-z0-9]{1,20}/?$') then
 raise exception 'orchestr:payment_link_url:Use your reusable PayPal.Me profile link without an amount, query or fragment.'; end if;
 return 'https://'||host||suffix;
end $$;
revoke all on function app.normalize_payment_link(text,text) from public,anon,authenticated,service_role;

alter table public.user_payment_links drop constraint user_payment_links_provider_check;
alter table public.user_payment_links add constraint user_payment_links_provider_check check(provider in('monzo','revolut','paypal','custom'));
create or replace function public.save_my_payment_link(p_provider text,p_url text,p_label text default null,p_id uuid default null,p_enabled boolean default true) returns uuid
language plpgsql security definer set search_path='' as $$
declare owner uuid:=auth.uid(); result uuid; label text; normalized text;
begin
 if owner is null then raise exception 'orchestr:auth_required:Sign in to manage payment links.' using errcode='42501'; end if;
 perform 1 from public.users where id=owner for update;
 if p_id is not null and not exists(select 1 from public.user_payment_links where id=p_id and user_id=owner and deleted_at is null) then raise exception 'orchestr:not_authorized:You can only manage your own payment links.' using errcode='42501'; end if;
 normalized:=app.normalize_payment_link(p_provider,p_url);
 label:=case p_provider when 'monzo' then 'Monzo' when 'revolut' then 'Revolut' when 'paypal' then 'PayPal' else btrim(p_label) end;
 if label is null or length(label) not between 1 and 60 or label ~ '[[:cntrl:]]' or p_enabled is null then raise exception 'orchestr:payment_link_label:Enter a label of 1 to 60 characters.'; end if;
 if p_id is null then
 insert into public.user_payment_links(user_id,provider,payment_url,display_label,is_enabled) values(owner,p_provider,normalized,label,p_enabled) returning id into result;
 else
 update public.user_payment_links set provider=p_provider,payment_url=normalized,display_label=label,is_enabled=p_enabled,is_default=is_default and p_enabled where id=p_id returning id into result;
 end if; return result;
end $$;

create or replace function public.get_my_attention()
returns table (
  project_id uuid,
  project_name text,
  code text,
  severity text,
  subject_type text,
  subject_id uuid,
  subject_label text,
  params jsonb,
  message text,
  resolution text
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    p.id            as project_id,
    p.name          as project_name,
    f.code, f.severity, f.subject_type, f.subject_id, f.subject_label,
    f.params, f.message, f.resolution
  from public.projects p
  join public.project_members m
    on m.project_id = p.id
   and m.user_id = auth.uid()
   and m.status = 'active'
   and m.deleted_at is null
  cross join lateral app._health_findings(p.id) f
  left join public.finding_dismissals d
    on d.project_id = p.id
   and d.code = f.code
   and d.subject_type = f.subject_type
   and d.subject_id is not distinct from f.subject_id
  where p.deleted_at is null
    and p.status in ('draft', 'active')
    and f.severity in ('blocker', 'warning')
    and case
          when not f.dismissible then false
          when d.state = 'dismissed' then true
          when d.state = 'snoozed'
            and d.snoozed_until >= (now() at time zone p.timezone)::date then true
          else false
        end = false
  order by
    case f.severity when 'blocker' then 0 else 1 end,
    p.name,
    f.subject_label, p.id, f.code, f.subject_type, f.subject_id;
$$;

revoke execute on function public.get_my_attention() from public;
grant execute on function public.get_my_attention() to authenticated;
