-- Archived projects retain readable history, but every Storage mutation must
-- require a writable project on both the old and replacement object path.
alter policy "project-media update member" on storage.objects
 using (bucket_id='project-media'
  and app.has_role(app.storage_project(name),array['organizer','member']::public.member_role[])
  and app.is_writable_project(app.storage_project(name)));
alter policy "project-media delete member" on storage.objects
 using (bucket_id='project-media'
  and app.has_role(app.storage_project(name),array['organizer','member']::public.member_role[])
  and app.is_writable_project(app.storage_project(name)));
alter policy "attachments update member" on storage.objects
 using (bucket_id='attachments'
  and app.has_role(app.storage_project(name),array['organizer','member']::public.member_role[])
  and app.is_writable_project(app.storage_project(name)))
 with check (bucket_id='attachments'
  and app.has_role(app.storage_project(name),array['organizer','member']::public.member_role[])
  and app.is_writable_project(app.storage_project(name)));
alter policy "attachments delete member" on storage.objects
 using (bucket_id='attachments'
  and app.has_role(app.storage_project(name),array['organizer','member']::public.member_role[])
  and app.is_writable_project(app.storage_project(name)));
