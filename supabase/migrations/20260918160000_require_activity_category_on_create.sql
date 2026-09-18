-- New Activities must be created through a valid project Category. Legacy
-- uncategorised records remain readable and editable for compatibility.
create function public.create_activity_in_category(p_project uuid,p_category uuid,p_fields jsonb,p_split jsonb)
returns public.commitments language plpgsql security invoker set search_path='' as $$
declare v_fields jsonb;
 v_commitment public.commitments%rowtype;
begin
 if p_category is null or not exists(
   select 1 from public.project_areas
   where id=p_category and project_id=p_project
 ) then
   raise exception 'orchestr:category_required:Choose a valid Category for this activity.' using errcode='22023';
 end if;
 v_fields:=coalesce(p_fields,'{}'::jsonb)||jsonb_build_object('area_id',p_category);
 select * into v_commitment from public.save_activity_with_split(p_project,null,v_fields,p_split);
 return v_commitment;
end $$;
revoke all on function public.create_activity_in_category(uuid,uuid,jsonb,jsonb) from public,anon;
grant execute on function public.create_activity_in_category(uuid,uuid,jsonb,jsonb) to authenticated;
