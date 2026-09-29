-- Preserve paired settlement history during normal project soft deletion. No balance calculation changes.
create or replace function app.guard_settlement_identity() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='UPDATE' and old.settlement_group_id is distinct from new.settlement_group_id then raise exception 'orchestr:immutable_column:Settlement identity cannot change.'; end if;
 -- Only the existing project cascade may change deletion lifecycle after hiding memberships.
 if tg_op='UPDATE' and pg_trigger_depth()>1
 and (to_jsonb(new)-array['deleted_at','updated_at'])=(to_jsonb(old)-array['deleted_at','updated_at'])
 and exists(select 1 from public.projects p where p.id=new.project_id
   and (p.deleted_at is not null or (old.deleted_at is not null and new.deleted_at is null))) then return new; end if;
 if new.settlement_group_id is not null then
  if not app.is_organizer(new.project_id) then raise exception 'orchestr:not_authorized:Only an organizer can record settlements.' using errcode='42501'; end if;
  if tg_op='UPDATE' and (new.amount_minor,new.direction,new.paid_by_member_id,new.commitment_id,new.type,new.paid_on) is distinct from (old.amount_minor,old.direction,old.paid_by_member_id,old.commitment_id,old.type,old.paid_on) and not (new.status='cancelled' and new.paid_on is null and (new.amount_minor,new.direction,new.paid_by_member_id,new.commitment_id,new.type) is not distinct from (old.amount_minor,old.direction,old.paid_by_member_id,old.commitment_id,old.type)) then raise exception 'orchestr:immutable_column:Cancel the settlement before recording a correction.'; end if;
 end if;
 return new;
end $$;

create or replace function app.guard_settlement_pair() returns trigger language plpgsql security definer set search_path='' as $$
declare g uuid; n integer; valid boolean;
begin
 g:=case when tg_op='DELETE' then old.settlement_group_id else new.settlement_group_id end;
 if g is null then return null; end if;
 select count(*),count(distinct project_id)=1 and count(distinct commitment_id)=1 and count(distinct amount_minor)=1 and count(distinct status)=1 and count(distinct paid_by_member_id)=2 and count(distinct direction)=2 and count(distinct coalesce(paid_on::text,''))=1 and count(distinct coalesce(deleted_at::text,''))=1 and bool_and((deleted_at is null or exists(select 1 from public.projects p where p.id=payments.project_id and p.deleted_at is not null)) and paid_by_member_id is not null and status in ('paid','cancelled') and amount_minor>0)
 into n,valid from public.payments where settlement_group_id=g;
 if n<>2 or not coalesce(valid,false) then raise exception 'orchestr:invalid_settlement:A settlement must contain a matching payment and receipt.'; end if;
 return null;
end $$;
