-- The category-delete RPC performs its own project/member/empty checks, then
-- deletes through a tightly scoped SECURITY DEFINER operation.
create or replace function public.delete_project_category(p_category uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_project uuid;
begin
 select project_id into v_project from public.project_areas where id=p_category;
 if v_project is null or not app.has_role(v_project,array['organizer','member']::public.member_role[]) or not app.is_writable_project(v_project) then
   raise exception 'orchestr:not_authorized:You cannot delete this category.' using errcode='42501';
 end if;
 if exists(select 1 from public.commitments where area_id=p_category and deleted_at is null)
    or exists(select 1 from public.tasks where area_id=p_category and deleted_at is null) then
   raise exception 'orchestr:category_not_empty:Move its activities before deleting this category.' using errcode='P0001';
 end if;
 delete from public.project_areas where id=p_category;
 return p_category;
end $$;
revoke all on function public.delete_project_category(uuid) from public,anon;
grant execute on function public.delete_project_category(uuid) to authenticated;
