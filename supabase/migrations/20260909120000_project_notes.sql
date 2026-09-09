-- ============================================================================
-- Project notes
-- A single lightweight plain-text note per project.
-- ============================================================================

alter table public.projects
  add column notes text,
  add constraint projects_notes_length check (notes is null or char_length(notes) <= 10000);

create or replace function app.tg_project_notes_writable()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status = 'archived' and new.notes is distinct from old.notes then
    raise exception 'orchestr:project_archived:archived projects are read-only'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger notes_writable
  before update of notes on public.projects
  for each row execute function app.tg_project_notes_writable();
