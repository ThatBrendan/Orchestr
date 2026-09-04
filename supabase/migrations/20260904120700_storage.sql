-- ============================================================================
-- 20260904120700_storage
-- Buckets + storage.objects policies (docs/SECURITY_RLS.md §8, TECHNICAL_ARCHITECTURE §13)
-- ============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('avatars',       'avatars',       true,   5242880, array['image/png','image/jpeg','image/webp']),
  ('project-media', 'project-media', false, 10485760, array['image/png','image/jpeg','image/webp']),
  ('attachments',   'attachments',   false, 26214400, null)   -- defined for FUTURE use; no client path yet
on conflict (id) do nothing;

-- Safe path -> project uuid (returns null instead of raising on a malformed segment)
create or replace function app.storage_project(p_name text)
returns uuid language sql immutable as $$
  select case
    when split_part(p_name, '/', 1) ~
         '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    then split_part(p_name, '/', 1)::uuid
    else null
  end;
$$;
grant execute on function app.storage_project(text) to authenticated;

-- ---------------------------------------------------------------------------
-- avatars  — path: avatars/<user_id>/<file>   (public read, owner write)
-- ---------------------------------------------------------------------------
create policy "avatars are public" on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'avatars');

create policy "avatars insert own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "avatars update own" on storage.objects
  for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "avatars delete own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- ---------------------------------------------------------------------------
-- project-media  — path: project-media/<project_id>/<file>  (private, membership)
-- ---------------------------------------------------------------------------
create policy "project-media read member" on storage.objects
  for select to authenticated
  using (bucket_id = 'project-media' and app.is_member(app.storage_project(name)));

create policy "project-media insert member" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'project-media'
    and app.has_role(app.storage_project(name), array['organizer','member']::public.member_role[])
    and app.is_writable_project(app.storage_project(name)));

create policy "project-media update member" on storage.objects
  for update to authenticated
  using (bucket_id = 'project-media'
    and app.has_role(app.storage_project(name), array['organizer','member']::public.member_role[]))
  with check (bucket_id = 'project-media'
    and app.has_role(app.storage_project(name), array['organizer','member']::public.member_role[])
    and app.is_writable_project(app.storage_project(name)));

create policy "project-media delete member" on storage.objects
  for delete to authenticated
  using (bucket_id = 'project-media'
    and app.has_role(app.storage_project(name), array['organizer','member']::public.member_role[]));

-- ---------------------------------------------------------------------------
-- attachments  — path: attachments/<project_id>/<commitment_id>/<file>
-- Same membership model. No client feature ships against this in MVP.
-- ---------------------------------------------------------------------------
create policy "attachments read member" on storage.objects
  for select to authenticated
  using (bucket_id = 'attachments' and app.is_member(app.storage_project(name)));

create policy "attachments write member" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'attachments'
    and app.has_role(app.storage_project(name), array['organizer','member']::public.member_role[])
    and app.is_writable_project(app.storage_project(name)));

create policy "attachments update member" on storage.objects
  for update to authenticated
  using (bucket_id = 'attachments'
    and app.has_role(app.storage_project(name), array['organizer','member']::public.member_role[]))
  with check (bucket_id = 'attachments'
    and app.has_role(app.storage_project(name), array['organizer','member']::public.member_role[]));

create policy "attachments delete member" on storage.objects
  for delete to authenticated
  using (bucket_id = 'attachments'
    and app.has_role(app.storage_project(name), array['organizer','member']::public.member_role[]));
