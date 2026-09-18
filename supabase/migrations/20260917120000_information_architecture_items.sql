-- Information architecture adapter: Items remain public.tasks, with a small
-- presentation type instead of a new parallel domain entity.
alter table public.tasks
  add column if not exists item_type text not null default 'task';

alter table public.tasks
  drop constraint if exists tasks_item_type_check;

alter table public.tasks
  add constraint tasks_item_type_check
  check (item_type in ('task', 'event', 'booking', 'purchase', 'other'));

create or replace function public.create_task_with_cost(p_project uuid,p_fields jsonb,p_cost numeric default null)
returns public.tasks language plpgsql security invoker set search_path='' as $$
declare t public.tasks%rowtype; c public.commitments%rowtype; v_link uuid; v_type text;
begin
 if not app.has_role(p_project,array['organizer','member']::public.member_role[]) or not app.is_writable_project(p_project) then
   raise exception 'orchestr:not_authorized:You cannot add tasks to this project.' using errcode='42501'; end if;
 if p_cost is not null and (p_cost<0 or p_cost>9007199254740991 or p_cost<>trunc(p_cost)) then
   raise exception 'orchestr:invalid_amount:Cost must be a non-negative whole minor-unit amount.' using errcode='22023'; end if;
 v_type:=coalesce(nullif(p_fields->>'item_type',''),'task');
 if v_type not in ('task','event','booking','purchase','other') then
   raise exception 'orchestr:invalid_item_type:Choose a supported Item type.' using errcode='22023'; end if;
 v_link:=nullif(p_fields->>'commitment_id','')::uuid;
 if v_link is not null then
   select * into c from public.commitments where id=v_link and project_id=p_project and deleted_at is null for update;
   if not found then raise exception 'orchestr:not_authorized:Linked area unavailable.' using errcode='42501'; end if;
   if p_cost is not null and p_cost is distinct from coalesce(c.actual_cost_minor,c.confirmed_cost_minor,c.estimated_cost_minor)::numeric then
     raise exception 'orchestr:shared_cost:This item uses its linked area cost. Edit the area to change its cost.'; end if;
 elsif p_cost is not null then
   insert into public.commitments(project_id,title,kind,activity_type,status,estimated_cost_minor,cost_split_mode)
   values(p_project,p_fields->>'title','other','task','idea',p_cost::bigint,'none') returning id into v_link;
 end if;
 insert into public.tasks(project_id,title,item_type,assignee_member_id,due_on,commitment_id,recurrence_frequency,recurrence_interval,recurrence_start_date)
 values(p_project,p_fields->>'title',v_type,nullif(p_fields->>'assignee_member_id','')::uuid,
   nullif(p_fields->>'due_on','')::date,v_link,
   nullif(p_fields->>'recurrence_frequency','')::public.recurrence_frequency,
   case when nullif(p_fields->>'recurrence_frequency','') is null then null else coalesce((p_fields->>'recurrence_interval')::int,1) end,nullif(p_fields->>'recurrence_start_date','')::date)
 returning * into t;
 return t;
end $$;
revoke all on function public.create_task_with_cost(uuid,jsonb,numeric) from public,anon;
grant execute on function public.create_task_with_cost(uuid,jsonb,numeric) to authenticated;
