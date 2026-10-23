-- Phase 6: payment schedules are timing allocations of an Activity cost.
-- They are not additional costs and do not replace the payments ledger.

create table public.activity_payment_schedules (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  commitment_id uuid not null,
  title text not null check (char_length(btrim(title)) between 1 and 120),
  amount_minor bigint not null check (amount_minor > 0),
  due_on date not null,
  sort_order integer not null default 0 check (sort_order >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint uq_activity_payment_schedule_project_id unique (project_id, id),
  constraint fk_activity_payment_schedule_commitment
    foreign key (project_id, commitment_id) references public.commitments(project_id, id) on delete cascade
);
create index activity_payment_schedules_activity_idx
  on public.activity_payment_schedules (commitment_id, sort_order, due_on)
  where deleted_at is null;
create index activity_payment_schedules_due_idx
  on public.activity_payment_schedules (project_id, due_on)
  where deleted_at is null;
create trigger activity_payment_schedules_set_updated_at
  before update on public.activity_payment_schedules
  for each row execute function app.tg_set_updated_at();
create trigger activity_payment_schedules_audit
  after insert or update on public.activity_payment_schedules
  for each row execute function app.tg_audit_row();

alter table public.payments add column payment_schedule_id uuid;
alter table public.payments add constraint fk_payment_schedule_project
  foreign key (project_id, payment_schedule_id)
  references public.activity_payment_schedules(project_id, id) on delete restrict;
create index payments_schedule_idx on public.payments (payment_schedule_id)
  where payment_schedule_id is not null and deleted_at is null;

create function app.guard_activity_payment_schedule()
returns trigger language plpgsql security definer set search_path='' as $$
declare
  c public.commitments%rowtype;
  scheduled_total bigint;
  net_paid bigint;
begin
  select * into c
  from public.commitments
  where id = coalesce(new.commitment_id, old.commitment_id)
  for update;
  if not found or c.deleted_at is not null then
    raise exception 'orchestr:not_authorized:Activity unavailable.' using errcode='42501';
  end if;
  if not app.is_writable_project(c.project_id) then
    raise exception 'orchestr:project_archived:This project is read-only.' using errcode='P0001';
  end if;
  if tg_op = 'UPDATE' and (new.commitment_id is distinct from old.commitment_id or new.project_id is distinct from old.project_id or new.id is distinct from old.id or new.created_at is distinct from old.created_at) then
    raise exception 'orchestr:immutable_column:A payment schedule cannot move to another Activity.' using errcode='P0001';
  end if;
  if tg_op = 'UPDATE' and old.deleted_at is null and old.amount_minor is distinct from new.amount_minor then
    select coalesce(sum(case when p.direction='outgoing' then p.amount_minor else -p.amount_minor end),0)::bigint
      into net_paid
      from public.payments p
     where p.payment_schedule_id = old.id and p.status='paid' and p.deleted_at is null;
    if new.amount_minor < greatest(net_paid, 0) then
      raise exception 'orchestr:invalid_payment_schedule:The amount cannot be less than the net paid amount.';
    end if;
  end if;
  if tg_op <> 'DELETE' and new.deleted_at is null then
    select coalesce(sum(s.amount_minor),0)::bigint into scheduled_total
      from public.activity_payment_schedules s
     where s.commitment_id = new.commitment_id and s.deleted_at is null and s.id <> new.id;
    if scheduled_total + new.amount_minor > app.effective_commitment_cost(c.actual_cost_minor,c.confirmed_cost_minor,c.estimated_cost_minor) then
      raise exception 'orchestr:invalid_payment_schedule:Payments cannot exceed the Activity cost.';
    end if;
  end if;
  if tg_op = 'UPDATE' and old.deleted_at is null and new.deleted_at is not null and exists (
    select 1 from public.payments p where p.payment_schedule_id=old.id and p.deleted_at is null
  ) then
    raise exception 'orchestr:invalid_payment_schedule:This payment cannot be deleted because it has payment history.';
  end if;
  return coalesce(new, old);
end $$;
revoke all on function app.guard_activity_payment_schedule() from public, anon, authenticated;
create trigger activity_payment_schedule_guard
  before insert or update on public.activity_payment_schedules
  for each row execute function app.guard_activity_payment_schedule();

create function app.guard_commitment_schedule_total()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.actual_cost_minor is distinct from old.actual_cost_minor
     or new.confirmed_cost_minor is distinct from old.confirmed_cost_minor
     or new.estimated_cost_minor is distinct from old.estimated_cost_minor then
    if (select coalesce(sum(s.amount_minor),0) from public.activity_payment_schedules s
        where s.commitment_id=new.id and s.deleted_at is null)
       > app.effective_commitment_cost(new.actual_cost_minor,new.confirmed_cost_minor,new.estimated_cost_minor) then
      raise exception 'orchestr:invalid_payment_schedule:The Activity cost cannot be less than its payment schedule.';
    end if;
  end if;
  return new;
end $$;
revoke all on function app.guard_commitment_schedule_total() from public, anon, authenticated;
create trigger commitment_schedule_total_guard
  before update of estimated_cost_minor, confirmed_cost_minor, actual_cost_minor on public.commitments
  for each row execute function app.guard_commitment_schedule_total();

create function app.guard_payment_schedule_allocation()
returns trigger language plpgsql security definer set search_path='' as $$
declare
  s public.activity_payment_schedules%rowtype;
  allocated bigint;
begin
  if tg_op='UPDATE' and old.ever_paid and new.payment_schedule_id is distinct from old.payment_schedule_id then
    raise exception 'orchestr:immutable_column:A paid payment cannot move between payment schedules.' using errcode='P0001';
  end if;
  if new.payment_schedule_id is null then return new; end if;
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
revoke all on function app.guard_payment_schedule_allocation() from public, anon, authenticated;
create trigger payment_schedule_allocation_guard
  before insert or update on public.payments
  for each row execute function app.guard_payment_schedule_allocation();

create view public.v_activity_payment_schedule_financials
with (security_invoker=true) as
select
  s.id as payment_schedule_id,
  s.project_id,
  s.commitment_id,
  s.title,
  s.amount_minor as scheduled_amount_minor,
  s.due_on,
  s.sort_order,
  coalesce(sum(p.amount_minor) filter (where p.direction='outgoing' and p.status='paid'),0)::bigint as gross_paid_minor,
  coalesce(sum(p.amount_minor) filter (where p.direction='incoming' and p.status='paid'),0)::bigint as refunded_minor,
  greatest(coalesce(sum(case when p.status='paid' and p.direction='outgoing' then p.amount_minor when p.status='paid' and p.direction='incoming' then -p.amount_minor else 0 end),0),0)::bigint as net_paid_minor,
  greatest(s.amount_minor - coalesce(sum(case when p.status='paid' and p.direction='outgoing' then p.amount_minor when p.status='paid' and p.direction='incoming' then -p.amount_minor else 0 end),0),0)::bigint as outstanding_minor
from public.activity_payment_schedules s
left join public.payments p on p.payment_schedule_id=s.id and p.deleted_at is null
where s.deleted_at is null
group by s.id, s.project_id, s.commitment_id, s.title, s.amount_minor, s.due_on, s.sort_order;

alter table public.activity_payment_schedules enable row level security;
alter table public.activity_payment_schedules force row level security;
revoke all on public.activity_payment_schedules from public, anon, authenticated;
grant select, insert, update on public.activity_payment_schedules to authenticated;
create policy activity_payment_schedules_select on public.activity_payment_schedules
  for select to authenticated using (app.is_member(project_id) and deleted_at is null and exists (
    select 1 from public.commitments c join public.projects p on p.id=c.project_id
    where c.id=commitment_id and c.project_id=activity_payment_schedules.project_id
      and c.deleted_at is null and p.deleted_at is null));
create policy activity_payment_schedules_insert on public.activity_payment_schedules
  for insert to authenticated
  with check (app.has_role(project_id,array['organizer','member']::public.member_role[])
              and app.is_writable_project(project_id) and deleted_at is null);
create policy activity_payment_schedules_update on public.activity_payment_schedules
  for update to authenticated
  using (app.has_role(project_id,array['organizer','member']::public.member_role[]) and deleted_at is null)
  with check (app.has_role(project_id,array['organizer','member']::public.member_role[])
              and (deleted_at is null or app.is_writable_project(project_id)));
grant select on public.v_activity_payment_schedule_financials to authenticated;
