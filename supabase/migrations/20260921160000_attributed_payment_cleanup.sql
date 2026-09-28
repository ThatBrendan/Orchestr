-- Normal project deletion must preserve and hide attributed payment history.
create or replace function app.guard_payment_settlement_member() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 -- Serialize financial edits with future completion checks.
 if tg_op='UPDATE' and new.commitment_id is distinct from old.commitment_id then
  raise exception 'orchestr:immutable_column:A Payment cannot move to another Activity.';
 end if;
 perform 1 from public.commitments where id=coalesce(new.commitment_id,old.commitment_id) for update;
 if tg_op='DELETE' then return old; end if;
 -- The existing project cascade hides memberships before updating payments.
 -- Permit only its lifecycle-only changes; attribution and monetary fields
 -- remain immutable here and all direct member checks below remain intact.
 if tg_op='UPDATE' and pg_trigger_depth()>1
  and (to_jsonb(new)-array['status','deleted_at','updated_at'])=(to_jsonb(old)-array['status','deleted_at','updated_at'])
  and (new.status=old.status or (old.status='scheduled' and new.status='cancelled'))
  and exists(select 1 from public.projects p where p.id=new.project_id
    and (p.deleted_at is not null or (old.deleted_at is not null and new.deleted_at is null))) then
  return new;
 end if;
 if auth.uid() is not null and not app.is_organizer(new.project_id) then
  if (new.paid_by_member_id is not null and new.paid_by_member_id is distinct from app.current_member_id(new.project_id))
    or (tg_op='UPDATE' and old.paid_by_member_id is not null and old.paid_by_member_id is distinct from app.current_member_id(new.project_id)) then
   raise exception 'orchestr:not_authorized:Only an organizer can record or change another member''s payment.' using errcode='42501';
  end if;
 end if;
 if new.paid_by_member_id is not null and (tg_op='INSERT' or new.paid_by_member_id is distinct from old.paid_by_member_id or (new.status='paid' and old.status is distinct from 'paid')) then
  perform 1 from public.project_members where id=new.paid_by_member_id and project_id=new.project_id and status='active' and deleted_at is null for share;
  if not found then raise exception 'orchestr:invalid_member:Select an active member of this project.' using errcode='42501'; end if;
 end if;
 return new;
end $$;
