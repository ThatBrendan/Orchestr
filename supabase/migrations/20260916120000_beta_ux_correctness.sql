-- Beta UX: additive commands; existing money, history and RLS remain authoritative.
create or replace function public.create_project(
  p_name text,
  p_timezone text,
  p_currency text,
  p_starts_on date default null,
  p_ends_on date default null,
  p_profile public.project_profile default 'blank'
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

  if p_starts_on is null then
    raise exception 'orchestr:start_date_required:Choose a start date.' using errcode='22023';
  end if;

  insert into public.projects (name, timezone, currency, profile, starts_on, ends_on)
  values (btrim(p_name), p_timezone, p_currency, coalesce(p_profile, 'blank'), p_starts_on, p_ends_on)
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

revoke execute on function public.create_project(text, text, text, date, date, public.project_profile) from public;
grant execute on function public.create_project(text, text, text, date, date, public.project_profile) to authenticated;

-- Retain the latest Health wrapper, including its optional-booking suppression.
create or replace function app._health_findings(p_project uuid)
returns table (code text,severity text,subject_type text,subject_id uuid,subject_label text,
 params jsonb,message text,resolution text,affects_health boolean,dismissible boolean)
language sql stable security invoker set search_path='' as $$
 select * from app._health_findings_with_optional_metadata(p_project)
 where code not in ('missing_booking_reference','missing_owner');
$$;

create or replace function public.save_activity_with_split(p_project uuid,p_commitment uuid,p_fields jsonb,p_split jsonb)
returns public.commitments language plpgsql security invoker set search_path='' as $$
declare c public.commitments%rowtype; v public.commitments%rowtype;
begin
 if p_commitment is not null then
  select * into c from public.commitments where id=p_commitment and project_id=p_project and deleted_at is null for update;
  if not found then raise exception 'orchestr:not_authorized:Activity unavailable.' using errcode='42501'; end if;
 end if;
 v:=jsonb_populate_record(c,case when p_commitment is null then
  jsonb_build_object('activity_type','other','kind','other','is_all_day',false,'booking_confirmed',false,'recurrence_active',true)||p_fields
  else p_fields end);
 if p_commitment is null then
  insert into public.commitments(project_id,cost_split_mode,status,title,activity_type,kind,owner_member_id,is_all_day,starts_at,ends_at,location_label,location_address,supplier_name,supplier_contact,booking_reference,booking_confirmed,estimated_cost_minor,recurrence_frequency,recurrence_interval,recurrence_start_date,recurrence_end_date,recurrence_active,notes) values(p_project,'none',coalesce(v.status,'idea'),v.title,v.activity_type,v.kind,v.owner_member_id,v.is_all_day,v.starts_at,v.ends_at,v.location_label,v.location_address,v.supplier_name,v.supplier_contact,v.booking_reference,v.booking_confirmed,v.estimated_cost_minor,v.recurrence_frequency,v.recurrence_interval,v.recurrence_start_date,v.recurrence_end_date,v.recurrence_active,v.notes) returning * into c;
 else
  update public.commitments set title=v.title,activity_type=v.activity_type,kind=v.kind,owner_member_id=v.owner_member_id,is_all_day=v.is_all_day,starts_at=v.starts_at,ends_at=v.ends_at,location_label=v.location_label,location_address=v.location_address,supplier_name=v.supplier_name,supplier_contact=v.supplier_contact,booking_reference=v.booking_reference,booking_confirmed=v.booking_confirmed,estimated_cost_minor=v.estimated_cost_minor,confirmed_cost_minor=v.confirmed_cost_minor,actual_cost_minor=v.actual_cost_minor,recurrence_frequency=v.recurrence_frequency,recurrence_interval=v.recurrence_interval,recurrence_start_date=v.recurrence_start_date,recurrence_end_date=v.recurrence_end_date,recurrence_active=v.recurrence_active,notes=v.notes where id=p_commitment returning * into c;
  if not found then raise exception 'orchestr:not_authorized:Activity cannot be edited.' using errcode='42501'; end if;
 end if;
 if p_split is not null then perform public.set_activity_cost_split(c.id,p_split); end if;
 select * into c from public.commitments where id=c.id;
 return c;
end $$;
revoke all on function public.save_activity_with_split(uuid,uuid,jsonb,jsonb) from public;
grant execute on function public.save_activity_with_split(uuid,uuid,jsonb,jsonb) to authenticated;


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
  if not found or not exists(select 1 from public.commitments where id=p_commitment and deleted_at is not null) then
    raise exception 'orchestr:delete_failed:The activity could not be deleted. Please try again.';
  end if;
  return p_commitment;
end;
$$;
revoke all on function public.soft_delete_commitment(uuid) from public, anon;
grant execute on function public.soft_delete_commitment(uuid) to authenticated;



-- Assignment permits active Viewers. This does not grant table UPDATE access.
create or replace function app.tg_task_assignee_role_check()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.assignee_member_id is not null and not exists(
   select 1 from public.project_members where id=new.assignee_member_id
   and project_id=new.project_id and status='active' and deleted_at is null
 ) then raise exception 'orchestr:invalid_assignee:Select an active project member.' using errcode='42501'; end if;
 return new;
end $$;
revoke all on function app.tg_task_assignee_role_check() from public;

-- No caller-supplied identity or editable payload. Lock membership against removal.
create function public.complete_assigned_task(p_task uuid,p_occurrence_date date default null)
returns void language plpgsql security definer set search_path='' as $$
declare t public.tasks%rowtype; m public.project_members%rowtype;
begin
 if auth.uid() is null then raise exception 'orchestr:auth_required:Sign in to complete this task.' using errcode='42501'; end if;
 select * into t from public.tasks where id=p_task and deleted_at is null for update;
 if not found then raise exception 'orchestr:not_authorized:Task unavailable.' using errcode='42501'; end if;
 select * into m from public.project_members where project_id=t.project_id and user_id=auth.uid()
   and status='active' and deleted_at is null for share;
 if not found or t.assignee_member_id is distinct from m.id then
   raise exception 'orchestr:not_authorized:You can only complete tasks assigned to you.' using errcode='42501'; end if;
 perform 1 from public.projects where id=t.project_id and deleted_at is null and status<>'archived' for share;
 if not found then raise exception 'orchestr:project_archived:This project is read-only.' using errcode='42501'; end if;
 if t.status not in ('open','in_progress') then raise exception 'orchestr:invalid_status:This task is no longer open.'; end if;
 if t.recurrence_frequency is null then
   if p_occurrence_date is not null then raise exception 'orchestr:invalid_occurrence:This task does not repeat.'; end if;
   update public.tasks set status='done' where id=t.id;
 else
   if p_occurrence_date is null or not t.recurrence_active or not exists(
     select 1 from app.recurrence_dates(t.recurrence_frequency,t.recurrence_interval,t.recurrence_start_date,t.recurrence_end_date,p_occurrence_date,p_occurrence_date)
   ) then raise exception 'orchestr:invalid_occurrence:Choose an active task occurrence.'; end if;
   if exists(select 1 from public.task_occurrences where task_id=t.id and occurrence_date=p_occurrence_date) then
     raise exception 'orchestr:invalid_status:This occurrence has already been handled.'; end if;
   insert into public.task_occurrences(project_id,task_id,occurrence_date,status,completed_at,created_by)
   values(t.project_id,t.id,p_occurrence_date,'completed',now(),m.id);
 end if;
end $$;
revoke all on function public.complete_assigned_task(uuid,date) from public,anon;
grant execute on function public.complete_assigned_task(uuid,date) to authenticated;

-- Task costs use the Activity ledger. Linked tasks reference the SAME cost;
-- independent cost-bearing tasks atomically create one financial Activity.
create function public.create_task_with_cost(p_project uuid,p_fields jsonb,p_cost numeric default null)
returns public.tasks language plpgsql security invoker set search_path='' as $$
declare t public.tasks%rowtype; c public.commitments%rowtype; v_link uuid;
begin
 if not app.has_role(p_project,array['organizer','member']::public.member_role[]) or not app.is_writable_project(p_project) then
   raise exception 'orchestr:not_authorized:You cannot add tasks to this project.' using errcode='42501'; end if;
 if p_cost is not null and (p_cost<0 or p_cost>9007199254740991 or p_cost<>trunc(p_cost)) then
   raise exception 'orchestr:invalid_amount:Cost must be a non-negative whole minor-unit amount.' using errcode='22023'; end if;
 v_link:=nullif(p_fields->>'commitment_id','')::uuid;
 if v_link is not null then
   select * into c from public.commitments where id=v_link and project_id=p_project and deleted_at is null for update;
   if not found then raise exception 'orchestr:not_authorized:Linked activity unavailable.' using errcode='42501'; end if;
   if p_cost is not null and p_cost is distinct from coalesce(c.actual_cost_minor,c.confirmed_cost_minor,c.estimated_cost_minor)::numeric then
     raise exception 'orchestr:shared_cost:This task uses its linked activity’s cost. Edit the activity to change it.'; end if;
 elsif p_cost is not null then
   insert into public.commitments(project_id,title,kind,activity_type,status,estimated_cost_minor,cost_split_mode)
   values(p_project,p_fields->>'title','other','task','idea',p_cost::bigint,'none') returning id into v_link;
 end if;
 insert into public.tasks(project_id,title,assignee_member_id,due_on,commitment_id,recurrence_frequency,recurrence_interval,recurrence_start_date)
 values(p_project,p_fields->>'title',nullif(p_fields->>'assignee_member_id','')::uuid,
   nullif(p_fields->>'due_on','')::date,v_link,
   nullif(p_fields->>'recurrence_frequency','')::public.recurrence_frequency,
   case when nullif(p_fields->>'recurrence_frequency','') is null then null else coalesce((p_fields->>'recurrence_interval')::int,1) end,nullif(p_fields->>'recurrence_start_date','')::date)
 returning * into t;
 return t;
end $$;
revoke all on function public.create_task_with_cost(uuid,jsonb,numeric) from public,anon;
grant execute on function public.create_task_with_cost(uuid,jsonb,numeric) to authenticated;

-- Paid rows are frozen until the existing explicit reopen/correction transition.
-- Keep the ever-paid latch irreversible even after reopening a payment.
create function app.guard_paid_payment_fields() returns trigger
language plpgsql set search_path='' as $$
begin
 if old.ever_paid then new.ever_paid:=true; end if;
 if old.status='paid' and (
   new.amount_minor is distinct from old.amount_minor or new.type is distinct from old.type
   or new.direction is distinct from old.direction or new.paid_by_member_id is distinct from old.paid_by_member_id
   or new.method is distinct from old.method or new.reference is distinct from old.reference
   or (new.status='paid' and new.paid_on is distinct from old.paid_on)
 ) then raise exception 'orchestr:paid_payment_immutable:Reopen this payment before correcting its details.'; end if;
 return new;
end $$;
revoke all on function app.guard_paid_payment_fields() from public;
create trigger paid_fields_guard before update on public.payments
for each row execute function app.guard_paid_payment_fields();
