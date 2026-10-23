-- Preserve authoritative project/Activity lifecycle cascades with allocated payments.
create or replace function app.guard_payment_schedule_allocation()
returns trigger language plpgsql security definer set search_path='' as $$
declare
  s public.activity_payment_schedules%rowtype;
  allocated bigint;
begin
  if tg_op='UPDATE' and old.ever_paid and new.payment_schedule_id is distinct from old.payment_schedule_id then
    raise exception 'orchestr:immutable_column:A paid payment cannot move between payment schedules.' using errcode='P0001';
  end if;
  if new.payment_schedule_id is null then return new; end if;
  -- Preserve existing trusted cancel/soft-delete/restore cascades, without a
  -- blanket nested-trigger bypass for allocation or monetary changes.
  if tg_op='UPDATE' and pg_trigger_depth()>1
     and (to_jsonb(new)-array['status','deleted_at','updated_at']) = (to_jsonb(old)-array['status','deleted_at','updated_at'])
     and (new.status=old.status or (old.status='scheduled' and new.status='cancelled'))
     and exists(select 1 from public.commitments c join public.projects p on p.id=c.project_id
       where c.id=new.commitment_id and c.project_id=new.project_id
       and (c.deleted_at is not null or c.status='cancelled' or p.deleted_at is not null
         or (old.deleted_at is not null and new.deleted_at is null))) then
    return new;
  end if;
  -- Match Activity mutation serialization before reading allocation totals.
  perform 1 from public.commitments where id=new.commitment_id and project_id=new.project_id and deleted_at is null for update;
  if not found or not app.is_writable_project(new.project_id) then
    raise exception 'orchestr:not_authorized:Activity unavailable.' using errcode='42501';
  end if;
  if new.settlement_group_id is not null or (new.direction='incoming' and new.type<>'refund') then
    raise exception 'orchestr:invalid_payment_schedule:Only Activity payments and refunds can be allocated.';
  end if;
  select * into s from public.activity_payment_schedules
   where id=new.payment_schedule_id and project_id=new.project_id and deleted_at is null for update;
  if not found or s.commitment_id is distinct from new.commitment_id then
    raise exception 'orchestr:invalid_payment_schedule:Payment and schedule must belong to the same Activity.';
  end if;
  if new.direction not in ('outgoing','incoming') or new.type = 'refund' and new.direction <> 'incoming' then
    raise exception 'orchestr:invalid_payment_schedule:Invalid payment allocation.';
  end if;

  if new.status in ('scheduled','paid') and new.deleted_at is null then
    select coalesce(sum(case when p.direction='outgoing' then p.amount_minor else -p.amount_minor end),0)::bigint
      into allocated
      from public.payments p
     where p.payment_schedule_id=new.payment_schedule_id and p.status='paid' and p.deleted_at is null
       and (tg_op <> 'UPDATE' or p.id <> new.id);
    if new.direction='outgoing' and greatest(allocated,0) + new.amount_minor > s.amount_minor then
      raise exception 'orchestr:invalid_payment_schedule:Payment exceeds the schedule amount.';
    end if;
    if new.direction='incoming' and new.amount_minor>allocated then
      raise exception 'orchestr:invalid_payment_schedule:Refund exceeds the schedule net paid amount.';
    end if;
  end if;
  return new;
end $$;
