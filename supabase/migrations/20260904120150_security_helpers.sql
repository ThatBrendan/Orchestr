-- ============================================================================
-- 20260904120150_security_helpers
-- Functions that reference application tables (public.projects / public.project_members)
-- and therefore MUST be created after 20260904120100_tables.sql.
--
-- Moved verbatim from 20260904120000_core_schema_enums_helpers.sql — an
-- implementation-order fix only. No change to approved behaviour or security
-- properties (SECURITY DEFINER · STABLE · SET search_path = '' · fully-qualified
-- names · no dynamic SQL · REVOKE EXECUTE FROM PUBLIC · authenticated/service_role
-- grants only). See docs/BACKEND_IMPLEMENTATION.md §7.
--
-- Source of truth: docs/DATABASE_SCHEMA.md §7.10, §8.2 ; docs/SECURITY_RLS.md §4.1-4.2
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Blocks child writes while the parent project is archived, except when the write
-- is itself a nested trigger effect (soft-delete / cancel cascades, un-archive).
-- (docs/DATABASE_SCHEMA.md §7.10)  — attached to the child tables in 20260904120300.
-- ---------------------------------------------------------------------------
create or replace function app.tg_enforce_project_writable()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_project uuid := coalesce(new.project_id, old.project_id);
  v_status  public.project_status;
begin
  if pg_trigger_depth() > 1 then
    return coalesce(new, old);   -- nested effect of another trigger: allow
  end if;
  select status into v_status from public.projects where id = v_project;
  if v_status = 'archived' then
    raise exception 'orchestr:project_archived:this project is archived and read-only' using errcode = 'P0001';
  end if;
  return coalesce(new, old);
end;
$$;

-- ---------------------------------------------------------------------------
-- SECURITY DEFINER membership helpers  (docs/SECURITY_RLS.md §4.1-4.2)
--   * SET search_path = ''  -> every reference fully schema-qualified
--   * only ever read the CALLER's own membership (auth.uid())
--   * no dynamic SQL; args are uuid / enum[]
-- ---------------------------------------------------------------------------

-- NOTE: these check *membership* only, not project.deleted_at. Deleted-project
-- invisibility is enforced by (a) `deleted_at is null` in every policy and
-- (b) the project soft-delete cascade that soft-deletes the membership rows too.
-- Keeping deleted_at out of here lets an organizer's own soft-delete pass its
-- UPDATE ... WITH CHECK (which re-evaluates against the row it just marked deleted).
create or replace function app.is_member(p_project uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.project_members m
    where m.project_id = p_project
      and m.user_id   = auth.uid()
      and m.status    = 'active'
      and m.deleted_at is null
  );
$$;

create or replace function app.has_role(p_project uuid, p_roles public.member_role[])
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.project_members m
    where m.project_id = p_project
      and m.user_id   = auth.uid()
      and m.status    = 'active'
      and m.deleted_at is null
      and m.role = any (p_roles)
  );
$$;

create or replace function app.is_organizer(p_project uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select app.has_role(p_project, array['organizer']::public.member_role[]);
$$;

create or replace function app.current_member_id(p_project uuid)
returns uuid language sql stable security definer set search_path = '' as $$
  select m.id
  from public.project_members m
  where m.project_id = p_project
    and m.user_id = auth.uid()
    and m.status = 'active'
    and m.deleted_at is null
  limit 1;
$$;

create or replace function app.is_writable_project(p_project uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.projects
    where id = p_project and deleted_at is null and status <> 'archived'
  );
$$;

-- ---------------------------------------------------------------------------
-- Grants (moved verbatim from 20260904120000). `app` schema USAGE is granted
-- in 20260904120000; these are the per-function EXECUTE grants.
-- ---------------------------------------------------------------------------
revoke execute on function
  app.is_member(uuid), app.has_role(uuid, public.member_role[]), app.is_organizer(uuid),
  app.current_member_id(uuid), app.is_writable_project(uuid)
from public;

grant execute on function
  app.is_member(uuid), app.has_role(uuid, public.member_role[]), app.is_organizer(uuid),
  app.current_member_id(uuid), app.is_writable_project(uuid)
to authenticated, service_role;
