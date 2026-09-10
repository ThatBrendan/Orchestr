-- Narrow soft-delete commands: UPDATE with an id predicate also requires SELECT
-- visibility of the new row. Keep deleted rows hidden; authorize the pre-image
-- explicitly and execute the existing update/cascade/audit triggers unchanged.

create or replace function public.soft_delete_commitment(p_commitment uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_row public.commitments%rowtype;
begin
  select * into v_row from public.commitments where id = p_commitment and deleted_at is null for update;
  if not found or not coalesce((app.has_role(v_row.project_id, array['organizer','member']::public.member_role[]) and (app.is_organizer(v_row.project_id) or v_row.created_by = app.current_member_id(v_row.project_id) or v_row.owner_member_id = app.current_member_id(v_row.project_id))), false) then
    raise exception 'orchestr:not_authorized:Not found or you do not have permission to delete this commitment.' using errcode = '42501';
  end if;
  if not app.is_writable_project(v_row.project_id) then
    raise exception 'orchestr:project_archived:This project is read-only.' using errcode = 'P0001';
  end if;
  update public.commitments set deleted_at = now() where id = p_commitment;
  return p_commitment;
end;
$$;
revoke all on function public.soft_delete_commitment(uuid) from public, anon;
grant execute on function public.soft_delete_commitment(uuid) to authenticated;

create or replace function public.soft_delete_task(p_task uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_row public.tasks%rowtype;
begin
  select * into v_row from public.tasks where id = p_task and deleted_at is null for update;
  if not found or not coalesce((app.has_role(v_row.project_id, array['organizer','member']::public.member_role[]) and (app.is_organizer(v_row.project_id) or v_row.created_by = app.current_member_id(v_row.project_id) or v_row.assignee_member_id = app.current_member_id(v_row.project_id))), false) then
    raise exception 'orchestr:not_authorized:Not found or you do not have permission to delete this task.' using errcode = '42501';
  end if;
  if not app.is_writable_project(v_row.project_id) then
    raise exception 'orchestr:project_archived:This project is read-only.' using errcode = 'P0001';
  end if;
  update public.tasks set deleted_at = now() where id = p_task;
  return p_task;
end;
$$;
revoke all on function public.soft_delete_task(uuid) from public, anon;
grant execute on function public.soft_delete_task(uuid) to authenticated;

create or replace function public.soft_delete_project(p_project uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_row public.projects%rowtype;
begin
  select * into v_row from public.projects where id = p_project and deleted_at is null for update;
  if not found or not coalesce((app.is_organizer(v_row.id)), false) then
    raise exception 'orchestr:not_authorized:Not found or you do not have permission to delete this project.' using errcode = '42501';
  end if;
  if not app.is_writable_project(v_row.id) then
    raise exception 'orchestr:project_archived:This project is read-only.' using errcode = 'P0001';
  end if;
  update public.projects set deleted_at = now() where id = p_project;
  return p_project;
end;
$$;
revoke all on function public.soft_delete_project(uuid) from public, anon;
grant execute on function public.soft_delete_project(uuid) to authenticated;

-- Archived project fields are read-only; only the existing status transition
-- may unarchive. Reject editing fields in the same request as unarchiving.
create or replace function app.tg_project_fields_writable()
returns trigger language plpgsql set search_path = '' as $$
begin
  if old.status = 'archived' and
    (to_jsonb(new) - array['status','archived_at','updated_at']) is distinct from
    (to_jsonb(old) - array['status','archived_at','updated_at']) then
    raise exception 'orchestr:project_archived:Unarchive this project before editing it.' using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function app.tg_project_fields_writable() from public;
create trigger fields_writable before update on public.projects
for each row execute function app.tg_project_fields_writable();
