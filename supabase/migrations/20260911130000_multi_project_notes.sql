-- Shared short notes. Client writes use narrow RPCs; legacy notes stay intact.
create table public.project_notes (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  created_by uuid,
  title text not null check (char_length(title) between 1 and 120 and title !~ '^[[:space:]]*$'),
  body text not null check (char_length(body) between 1 and 10000 and body !~ '^[[:space:]]*$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  foreign key (project_id, created_by) references public.project_members(project_id,id) on delete set null (created_by)
);
create index project_notes_active_updated_idx on public.project_notes(project_id, updated_at desc, id) where deleted_at is null;
create index project_notes_creator_idx on public.project_notes(project_id,created_by);

-- No reliable author/date exists for the old shared field: preserve content,
-- leave attribution unknown, and timestamp the import. Preserve deleted projects too.
insert into public.project_notes(project_id,title,body,created_by,deleted_at)
select id,'Project note',notes,null,deleted_at from public.projects
where notes is not null and notes !~ '^[[:space:]]*$';
comment on column public.projects.notes is 'Legacy single note. Preserved for compatibility; new UI uses project_notes.';

alter table public.project_notes enable row level security;
revoke all on public.project_notes from anon, authenticated;
grant select on public.project_notes to authenticated;
grant all on public.project_notes to service_role;
create policy project_notes_read on public.project_notes for select to authenticated
using (deleted_at is null and app.is_member(project_id)
  and exists(select 1 from public.projects p where p.id=project_id and p.deleted_at is null));

create trigger set_updated_at before update on public.project_notes
for each row execute function app.tg_set_updated_at();
create trigger audit after insert or update or delete on public.project_notes
for each row execute function app.tg_audit_row();

-- A single joined read; the view runs with caller RLS, including archived reads.
create view public.v_project_notes with (security_invoker=true) as
select n.*,m.display_name as creator_name from public.project_notes n
left join public.project_members m on m.project_id=n.project_id and m.id=n.created_by;
grant select on public.v_project_notes to authenticated;

create function public.create_project_note(p_project uuid,p_title text,p_body text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
  if not app.has_role(p_project,array['organizer','member']::public.member_role[]) then
    raise exception 'orchestr:not_authorized:You cannot create notes in this project.' using errcode='42501'; end if;
  -- Every create locks the project before counting; concurrent calls cannot exceed 20.
  perform 1 from public.projects where id=p_project and deleted_at is null and status<>'archived' for update;
  if not found then raise exception 'orchestr:project_archived:This project is read-only.'; end if;
  if (select count(*) from public.project_notes where project_id=p_project and deleted_at is null)>=20 then
    raise exception 'orchestr:note_limit:You''ve reached the 20-note limit for this project.'; end if;
  insert into public.project_notes(project_id,created_by,title,body)
  values(p_project,app.current_member_id(p_project),regexp_replace(p_title,'^[[:space:]]+|[[:space:]]+$','','g'),regexp_replace(p_body,'^[[:space:]]+|[[:space:]]+$','','g')) returning id into v_id;
  return v_id;
end $$;

create function public.update_project_note(p_note uuid,p_title text,p_body text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_note public.project_notes%rowtype;
begin
  select * into v_note from public.project_notes where id=p_note and deleted_at is null;
  if not found or not coalesce((app.has_role(v_note.project_id,array['organizer','member']::public.member_role[])
    and (app.is_organizer(v_note.project_id) or v_note.created_by=app.current_member_id(v_note.project_id))),false) then
    raise exception 'orchestr:not_authorized:Not found or you cannot edit this note.' using errcode='42501'; end if;
  perform 1 from public.projects where id=v_note.project_id and deleted_at is null and status<>'archived' for update;
  if not found then raise exception 'orchestr:project_archived:This project is read-only.'; end if;
  update public.project_notes set title=regexp_replace(p_title,'^[[:space:]]+|[[:space:]]+$','','g'),
    body=regexp_replace(p_body,'^[[:space:]]+|[[:space:]]+$','','g') where id=p_note and deleted_at is null;
  if not found then raise exception 'orchestr:not_found:This note is no longer available.'; end if;
  return p_note;
end $$;

create function public.soft_delete_project_note(p_note uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_note public.project_notes%rowtype;
begin
  select * into v_note from public.project_notes where id=p_note and deleted_at is null;
  if not found or not coalesce((app.has_role(v_note.project_id,array['organizer','member']::public.member_role[])
    and (app.is_organizer(v_note.project_id) or v_note.created_by=app.current_member_id(v_note.project_id))),false) then
    raise exception 'orchestr:not_authorized:Not found or you cannot delete this note.' using errcode='42501'; end if;
  perform 1 from public.projects where id=v_note.project_id and deleted_at is null and status<>'archived' for update;
  if not found then raise exception 'orchestr:project_archived:This project is read-only.'; end if;
  update public.project_notes set deleted_at=now() where id=p_note and deleted_at is null;
  if not found then raise exception 'orchestr:not_found:This note is no longer available.'; end if;
  return p_note;
end $$;
revoke all on function public.create_project_note(uuid,text,text),public.update_project_note(uuid,text,text),public.soft_delete_project_note(uuid) from public,anon;
grant execute on function public.create_project_note(uuid,text,text),public.update_project_note(uuid,text,text),public.soft_delete_project_note(uuid) to authenticated;
