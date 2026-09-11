-- Domain operations only: no email service or platform-admin override.
revoke update, delete on public.invitations from authenticated;

create or replace function public.create_invitation(p_project_id uuid, p_email text, p_role public.member_role)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_member uuid; v_id uuid; v_email text := lower(btrim(p_email));
begin
  if auth.uid() is null then raise exception 'orchestr:auth_required:Sign in required' using errcode='42501'; end if;
  select id into v_member from public.project_members where project_id=p_project_id
    and user_id=auth.uid() and role='organizer' and status='active' and deleted_at is null;
  if v_member is null then raise exception 'orchestr:forbidden:Only an organizer can invite' using errcode='42501'; end if;
  if p_role is null or p_role not in ('member','viewer') then raise exception 'orchestr:invalid_role:Choose Member or Viewer'; end if;
  if v_email is null or length(v_email)>254 or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' then
    raise exception 'orchestr:invalid_email:Enter a valid email address'; end if;
  -- Serialize creation/acceptance within a project; also makes the pending cap race safe.
  perform 1 from public.projects where id=p_project_id and deleted_at is null and status<>'archived' for update;
  if not found then raise exception 'orchestr:project_read_only:Project is unavailable or archived'; end if;
  if exists(select 1 from public.project_members m left join auth.users u on u.id=m.user_id
    where m.project_id=p_project_id and m.status='active' and m.deleted_at is null
      and (lower(m.email)=v_email or lower(u.email)=v_email)) then
    raise exception 'orchestr:already_member:This person is already a member of the project.'; end if;
  update public.invitations set status='expired' where project_id=p_project_id and status='pending' and expires_at<=now();
  if exists(select 1 from public.invitations where project_id=p_project_id and lower(email)=v_email and status='pending') then
    raise exception 'orchestr:invitation_pending:Invitation already pending.'; end if;
  if (select count(*) from public.invitations where project_id=p_project_id and status='pending')>=25 then
    raise exception 'orchestr:rate_limited:Too many pending invitations for this project'; end if;
  insert into public.invitations(project_id,email,role,invited_by) values(p_project_id,v_email,p_role,v_member) returning id into v_id;
  return v_id;
end $$;

create or replace function public.list_my_invitations()
returns table(id uuid, project_id uuid, token text, project_name text, inviter_name text, role public.member_role, created_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select i.id,i.project_id,i.token,p.name,m.display_name,i.role,i.created_at
  from public.invitations i join public.projects p on p.id=i.project_id
  join public.project_members m on m.id=i.invited_by
  where auth.uid() is not null and lower(i.email)=(select lower(email) from auth.users where id=auth.uid())
    and i.status='pending' and i.expires_at>now() and p.deleted_at is null and p.status<>'archived'
  order by i.created_at desc;
$$;

create or replace function public.decline_invitation(p_token text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_inv public.invitations%rowtype;
begin
  if auth.uid() is null then raise exception 'orchestr:auth_required:Sign in required' using errcode='42501'; end if;
  select * into v_inv from public.invitations where token=p_token for update;
  if v_inv.id is null or v_inv.status<>'pending' or v_inv.expires_at<=now()
    or lower(v_inv.email) is distinct from (select lower(email) from auth.users where id=auth.uid()) then
    raise exception 'orchestr:invalid_invitation:Invitation is unavailable'; end if;
  update public.invitations set status='declined' where id=v_inv.id;
  return v_inv.project_id;
end $$;

create or replace function public.accept_invitation(p_token text)
returns uuid
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_email text;
  v_inv public.invitations%rowtype;
  v_member uuid;
  v_name text;
begin
  if v_uid is null then
    raise exception 'orchestr:auth_required:you must be signed in' using errcode = '42501';
  end if;
  perform set_config('app.bypass_member_guard', 'on', true);

  select lower(email), coalesce(nullif(btrim(display_name),''), split_part(email,'@',1))
    into v_email, v_name
  from public.users where id = v_uid;
  select lower(email) into v_email from auth.users where id=v_uid;

  perform 1 from public.projects where id=(select project_id from public.invitations where token=p_token)
    and deleted_at is null and status<>'archived' for update;
  if not found then raise exception 'orchestr:invalid_invitation:Invitation is unavailable'; end if;
  select * into v_inv from public.invitations where token = p_token for update;

  if v_inv.id is null then
    raise exception 'orchestr:invalid_invitation:this invitation link is invalid or has expired' using errcode = 'P0001';
  end if;

  if v_inv.status <> 'pending' or v_inv.expires_at <= now() then
    raise exception 'orchestr:invalid_invitation:this invitation link is invalid or has expired' using errcode = 'P0001';
  end if;

  if lower(v_inv.email) is distinct from v_email then
    raise exception 'orchestr:invitation_email_mismatch:this invitation was sent to a different email address'
      using errcode = 'P0001';
  end if;

  -- already linked?
  select id into v_member from public.project_members
   where project_id = v_inv.project_id and user_id = v_uid;
  if v_member is not null then
    if exists(select 1 from public.project_members where id=v_member and status='active' and deleted_at is null) then
      raise exception 'orchestr:already_member:This person is already a member of the project.';
    end if;
    update public.project_members set status='active', role=v_inv.role, deleted_at=null, joined_at=now()
     where id=v_member;
  else
    -- claim a matching name-only row
    select id into v_member from public.project_members
     where project_id = v_inv.project_id and user_id is null
       and lower(email) = v_email and status <> 'removed' and deleted_at is null
     limit 1;
    if v_member is not null then
      update public.project_members
         set user_id = v_uid, role=v_inv.role, status = 'active', joined_at = now()
       where id = v_member;
    else
      insert into public.project_members
        (project_id, user_id, display_name, email, role, status, invited_at, joined_at)
      values
        (v_inv.project_id, v_uid, left(v_name,80), v_email, v_inv.role, 'active', v_inv.created_at, now())
      returning id into v_member;
    end if;
  end if;

  update public.invitations
     set status = 'accepted', accepted_at = now(), accepted_member_id = v_member
   where id = v_inv.id;

  insert into public.audit_log
    (project_id, actor_user_id, actor_member_id, source, action, entity_type, entity_id, after)
  values
    (v_inv.project_id, v_uid, v_member, 'rpc', 'update', 'invitations', v_inv.id,
     jsonb_build_object('status','accepted','accepted_member_id',v_member));

  perform set_config('app.bypass_member_guard', 'off', true);
  return v_inv.project_id;
end;
$$;

revoke execute on function public.accept_invitation(text) from public;
grant execute on function public.accept_invitation(text) to authenticated;


revoke all on function public.create_invitation(uuid,text,public.member_role) from public;
revoke all on function public.list_my_invitations() from public;
revoke all on function public.decline_invitation(text) from public;
grant execute on function public.create_invitation(uuid,text,public.member_role) to authenticated;
grant execute on function public.list_my_invitations() to authenticated;
grant execute on function public.decline_invitation(text) to authenticated;

-- Token previews use the same authoritative email and validity rules as the inbox.
create or replace function public.get_invitation(p_token text)
returns table(project_name text, inviter_name text, role public.member_role, status public.invitation_status)
language sql stable security definer set search_path = '' as $$
  select p.name,m.display_name,i.role,i.status from public.invitations i
  join public.projects p on p.id=i.project_id
  left join public.project_members m on m.id=i.invited_by
  where i.token=p_token and auth.uid() is not null
    and lower(i.email)=(select lower(email) from auth.users where id=auth.uid())
    and i.status='pending' and i.expires_at>now() and p.deleted_at is null and p.status<>'archived';
$$;
