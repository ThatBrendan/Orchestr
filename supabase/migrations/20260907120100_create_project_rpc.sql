-- ============================================================================
-- 20260907120100_create_project_rpc
-- Browser project creation must bootstrap membership before any project row is
-- returned. The existing AFTER INSERT trigger remains the founder authority.
-- ============================================================================

create or replace function public.create_project(
  p_name text,
  p_timezone text,
  p_currency text,
  p_starts_on date default null,
  p_ends_on date default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_project uuid;
  v_founders int;
begin
  if v_uid is null then
    raise exception 'orchestr:auth_required:you must be signed in' using errcode = '42501';
  end if;

  if p_name is null or char_length(btrim(p_name)) not between 1 and 120 then
    raise exception 'orchestr:invalid_project_name:project name must be between 1 and 120 characters'
      using errcode = 'P0001';
  end if;

  insert into public.projects (name, timezone, currency, starts_on, ends_on)
  values (btrim(p_name), p_timezone, p_currency, p_starts_on, p_ends_on)
  returning id into v_project;

  select count(*)
    into v_founders
    from public.project_members
   where project_id = v_project
     and user_id = v_uid
     and role = 'organizer'
     and status = 'active'
     and deleted_at is null;

  if v_founders <> 1 then
    raise exception 'orchestr:project_bootstrap_failed:project founding membership was not created'
      using errcode = 'P0001';
  end if;

  return v_project;
end;
$$;

revoke execute on function public.create_project(text, text, text, date, date) from public;
grant execute on function public.create_project(text, text, text, date, date) to authenticated;

revoke insert on public.projects from authenticated;
drop policy if exists projects_insert_authed on public.projects;