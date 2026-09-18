-- Forward correction of the applied IA prototype. No historical records rewritten.
create table public.project_areas (
 id uuid primary key default gen_random_uuid(),
 project_id uuid not null references public.projects(id),
 title text not null check (length(btrim(title)) between 1 and 120),
 notes text,
 created_at timestamptz not null default now(),
 unique(id,project_id)
);
alter table public.project_areas enable row level security;
grant select,insert,update on public.project_areas to authenticated;
create policy areas_read on public.project_areas for select to authenticated using(app.has_role(project_id,array['organizer','member','viewer']::public.member_role[]) and exists(select 1 from public.projects where id=project_id and deleted_at is null));
create policy areas_insert on public.project_areas for insert to authenticated with check(app.has_role(project_id,array['organizer','member']::public.member_role[]) and app.is_writable_project(project_id));
create policy areas_update on public.project_areas for update to authenticated using(app.has_role(project_id,array['organizer','member']::public.member_role[]) and app.is_writable_project(project_id)) with check(app.has_role(project_id,array['organizer','member']::public.member_role[]) and app.is_writable_project(project_id));
create trigger enforce_writable before insert or update on public.project_areas for each row execute function app.tg_enforce_project_writable();
create trigger audit_row after insert or update on public.project_areas for each row execute function app.tg_audit_row();
alter table public.commitments add column area_id uuid;
alter table public.tasks add column area_id uuid;
alter table public.commitments add constraint commitments_area_project_fk foreign key(area_id,project_id) references public.project_areas(id,project_id);
alter table public.tasks add constraint tasks_area_project_fk foreign key(area_id,project_id) references public.project_areas(id,project_id);
create index commitments_area_idx on public.commitments(area_id);
create index tasks_area_idx on public.tasks(area_id);

create or replace function app.tg_commitment_owner_role_check()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.owner_member_id is not null and not exists(select 1 from public.project_members where id=new.owner_member_id and project_id=new.project_id and status='active' and deleted_at is null) then
 raise exception 'orchestr:invalid_owner:Select an active project member.'; end if;
 return new;
end $$;

-- Identity is server-derived; no general Viewer UPDATE permission is granted.
create function public.complete_assigned_item(p_item uuid,p_occurrence_date date default null)
returns void language plpgsql security definer set search_path='' as $$
declare c public.commitments%rowtype; m public.project_members%rowtype;
begin
 if auth.uid() is null then raise exception 'orchestr:not_authorized:Sign in to complete this item.' using errcode='42501'; end if;
 select * into c from public.commitments where id=p_item and deleted_at is null for update;
 if not found then raise exception 'orchestr:not_authorized:Item unavailable.' using errcode='42501'; end if;
 select * into m from public.project_members where project_id=c.project_id and user_id=auth.uid() and status='active' and deleted_at is null for share;
 if not found or c.owner_member_id is distinct from m.id then raise exception 'orchestr:not_authorized:You can only complete items assigned to you.' using errcode='42501'; end if;
 perform 1 from public.projects where id=c.project_id and deleted_at is null and status<>'archived' for share;
 if not found then raise exception 'orchestr:project_archived:This project is read-only.'; end if;
 if c.status in ('completed','cancelled') then raise exception 'orchestr:invalid_status:This item is no longer open.'; end if;
 if not app.commitment_financially_settled(c.id) then raise exception 'orchestr:financial_unsettled:This item still has payments to settle.'; end if;
 if c.recurrence_frequency is null then
  if p_occurrence_date is not null then raise exception 'orchestr:invalid_occurrence:This item does not repeat.'; end if;
  update public.commitments set status='completed' where id=c.id;
 else
  if p_occurrence_date is null or not c.recurrence_active or not exists(select 1 from app.recurrence_dates(c.recurrence_frequency,c.recurrence_interval,c.recurrence_start_date,c.recurrence_end_date,p_occurrence_date,p_occurrence_date)) then raise exception 'orchestr:invalid_occurrence:Choose an active occurrence.'; end if;
  if exists(select 1 from public.commitment_occurrences where commitment_id=c.id and occurrence_date=p_occurrence_date) then raise exception 'orchestr:invalid_status:This occurrence has already been handled.'; end if;
  insert into public.commitment_occurrences(project_id,commitment_id,occurrence_date,status,completed_at,created_by) values(c.project_id,c.id,p_occurrence_date,'completed',now(),m.id);
 end if;
end $$;
revoke all on function public.complete_assigned_item(uuid,date) from public,anon;
grant execute on function public.complete_assigned_item(uuid,date) to authenticated;

-- Internal transfers remain in the same auditable ledger but are not supplier expenses.
alter table public.payments add column settlement_group_id uuid;
create index payments_settlement_group_idx on public.payments(settlement_group_id) where settlement_group_id is not null;
create function app.guard_settlement_pair() returns trigger language plpgsql security definer set search_path='' as $$
declare g uuid; n integer; valid boolean;
begin
 g:=case when tg_op='DELETE' then old.settlement_group_id else new.settlement_group_id end;
 if g is null then return null; end if;
 select count(*),count(distinct project_id)=1 and count(distinct commitment_id)=1 and count(distinct amount_minor)=1 and count(distinct status)=1 and count(distinct paid_by_member_id)=2 and count(distinct direction)=2 and count(distinct coalesce(paid_on::text,''))=1 and bool_and(deleted_at is null and paid_by_member_id is not null and status in ('paid','cancelled') and amount_minor>0)
 into n,valid from public.payments where settlement_group_id=g;
 if n<>2 or not coalesce(valid,false) then raise exception 'orchestr:invalid_settlement:A settlement must contain a matching payment and receipt.'; end if;
 return null;
end $$;
create constraint trigger settlement_pair after insert or update or delete on public.payments deferrable initially deferred for each row execute function app.guard_settlement_pair();
create function app.guard_settlement_identity() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='UPDATE' and old.settlement_group_id is distinct from new.settlement_group_id then raise exception 'orchestr:immutable_column:Settlement identity cannot change.'; end if;
 if new.settlement_group_id is not null then
  if not app.is_organizer(new.project_id) then raise exception 'orchestr:not_authorized:Only an organizer can record settlements.' using errcode='42501'; end if;
  if tg_op='UPDATE' and (new.amount_minor,new.direction,new.paid_by_member_id,new.commitment_id,new.type,new.paid_on) is distinct from (old.amount_minor,old.direction,old.paid_by_member_id,old.commitment_id,old.type,old.paid_on) and not (new.status='cancelled' and new.paid_on is null and (new.amount_minor,new.direction,new.paid_by_member_id,new.commitment_id,new.type) is not distinct from (old.amount_minor,old.direction,old.paid_by_member_id,old.commitment_id,old.type)) then raise exception 'orchestr:immutable_column:Cancel the settlement before recording a correction.'; end if;
 end if;
 return new;
end $$;
create trigger settlement_identity before insert or update on public.payments for each row execute function app.guard_settlement_identity();
revoke all on function app.guard_settlement_identity(),app.guard_settlement_pair() from public;

create function public.record_item_settlement(p_item uuid,p_from uuid,p_to uuid,p_amount bigint,p_date date)
returns uuid language plpgsql security invoker set search_path='' as $$
declare c public.commitments%rowtype; g uuid:=gen_random_uuid(); owed bigint; credit bigint;
begin
 select * into c from public.commitments where id=p_item and deleted_at is null for update;
 if not found or not app.is_organizer(c.project_id) or not app.is_writable_project(c.project_id) then raise exception 'orchestr:not_authorized:Only an organizer can record settlements.' using errcode='42501'; end if;
 select remaining_minor into owed from public.v_activity_member_settlements where commitment_id=p_item and member_id=p_from;
 select -remaining_minor into credit from public.v_activity_member_settlements where commitment_id=p_item and member_id=p_to;
 if p_from=p_to or p_date is null or p_amount is null or p_amount<=0 or p_amount>coalesce(owed,0) or p_amount>coalesce(credit,0) then raise exception 'orchestr:invalid_settlement:Choose an outstanding share and a person owed this amount.'; end if;
 insert into public.payments(project_id,commitment_id,type,direction,status,amount_minor,paid_on,paid_by_member_id,settlement_group_id)
 values(c.project_id,c.id,'full','outgoing','paid',p_amount,p_date,p_from,g),(c.project_id,c.id,'refund','incoming','paid',p_amount,p_date,p_to,g);
 return g;
end $$;
create function public.cancel_item_settlement(p_group uuid) returns void language plpgsql security invoker set search_path='' as $$
declare c public.commitments%rowtype;
begin
 select c0.* into c from public.commitments c0 join public.payments p on p.commitment_id=c0.id where p.settlement_group_id=p_group limit 1 for update of c0;
 if not found or not app.is_organizer(c.project_id) or not app.is_writable_project(c.project_id) then raise exception 'orchestr:not_authorized:Only an organizer can correct settlements.' using errcode='42501'; end if;
 update public.payments set status='cancelled',paid_on=null where settlement_group_id=p_group and status='paid';
end $$;
revoke all on function public.record_item_settlement(uuid,uuid,uuid,bigint,date),public.cancel_item_settlement(uuid) from public,anon;
grant execute on function public.record_item_settlement(uuid,uuid,uuid,bigint,date),public.cancel_item_settlement(uuid) to authenticated;

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
  insert into public.commitments(project_id,cost_split_mode,status,title,area_id,activity_type,kind,owner_member_id,is_all_day,starts_at,ends_at,location_label,location_address,supplier_name,supplier_contact,booking_reference,booking_confirmed,estimated_cost_minor,recurrence_frequency,recurrence_interval,recurrence_start_date,recurrence_end_date,recurrence_active,notes) values(p_project,'none',coalesce(v.status,'idea'),v.title,v.area_id,v.activity_type,v.kind,v.owner_member_id,v.is_all_day,v.starts_at,v.ends_at,v.location_label,v.location_address,v.supplier_name,v.supplier_contact,v.booking_reference,v.booking_confirmed,v.estimated_cost_minor,v.recurrence_frequency,v.recurrence_interval,v.recurrence_start_date,v.recurrence_end_date,v.recurrence_active,v.notes) returning * into c;
 else
  update public.commitments set title=v.title,area_id=v.area_id,activity_type=v.activity_type,kind=v.kind,owner_member_id=v.owner_member_id,is_all_day=v.is_all_day,starts_at=v.starts_at,ends_at=v.ends_at,location_label=v.location_label,location_address=v.location_address,supplier_name=v.supplier_name,supplier_contact=v.supplier_contact,booking_reference=v.booking_reference,booking_confirmed=v.booking_confirmed,estimated_cost_minor=v.estimated_cost_minor,confirmed_cost_minor=v.confirmed_cost_minor,actual_cost_minor=v.actual_cost_minor,recurrence_frequency=v.recurrence_frequency,recurrence_interval=v.recurrence_interval,recurrence_start_date=v.recurrence_start_date,recurrence_end_date=v.recurrence_end_date,recurrence_active=v.recurrence_active,notes=v.notes where id=p_commitment returning * into c;
  if not found then raise exception 'orchestr:not_authorized:Activity cannot be edited.' using errcode='42501'; end if;
 end if;
 if p_split is not null then perform public.set_activity_cost_split(c.id,p_split); end if;
 select * into c from public.commitments where id=c.id;
 return c;
end $$;
revoke all on function public.save_activity_with_split(uuid,uuid,jsonb,jsonb) from public;
grant execute on function public.save_activity_with_split(uuid,uuid,jsonb,jsonb) to authenticated;



create or replace view public.v_commitment_financials
with (security_invoker = true) as
select
  c.id            as commitment_id,
  c.project_id,
  c.status,
  app.effective_commitment_cost(c.actual_cost_minor,c.confirmed_cost_minor,c.estimated_cost_minor)::bigint as effective_cost_minor,
  coalesce(p.gross_paid, 0)::bigint     as gross_paid_minor,
  coalesce(p.refunded, 0)::bigint       as refunded_minor,
  (coalesce(p.gross_paid,0) - coalesce(p.refunded,0))::bigint as net_paid_minor,
  greatest(
    app.effective_commitment_cost(c.actual_cost_minor,c.confirmed_cost_minor,c.estimated_cost_minor)
      - (coalesce(p.gross_paid,0) - coalesce(p.refunded,0)),
    0
  )::bigint as outstanding_minor,
  case
    when app.effective_commitment_cost(c.actual_cost_minor,c.confirmed_cost_minor,c.estimated_cost_minor) = 0
         and coalesce(p.gross_paid,0) - coalesce(p.refunded,0) > 0 then 'paid_in_full'
    when coalesce(p.gross_paid,0) - coalesce(p.refunded,0) <= 0 then 'unpaid'
    when coalesce(p.gross_paid,0) - coalesce(p.refunded,0)
         >= app.effective_commitment_cost(c.actual_cost_minor,c.confirmed_cost_minor,c.estimated_cost_minor) then 'paid_in_full'
    when coalesce(p.paid_out_count,0) > 0 and coalesce(p.only_deposits, false) then 'deposit_paid'
    else 'part_paid'
  end as payment_progress
from public.commitments c
left join lateral (
  select
    sum(pay.amount_minor) filter (where pay.status='paid' and pay.direction='outgoing') as gross_paid,
    sum(pay.amount_minor) filter (where pay.status='paid' and pay.direction='incoming') as refunded,
    count(*)              filter (where pay.status='paid' and pay.direction='outgoing') as paid_out_count,
    bool_and(pay.type='deposit') filter (where pay.status='paid' and pay.direction='outgoing') as only_deposits
  from public.payments pay
  where pay.commitment_id = c.id and pay.deleted_at is null and pay.settlement_group_id is null
) p on true
where c.deleted_at is null;

create or replace view public.v_project_financials
with (security_invoker = true) as
select
  pr.id as project_id,
  -- BUD-4 total cost: all non-cancelled commitments
  coalesce(sum(cf.effective_cost_minor) filter (where cf.status <> 'cancelled'), 0)::bigint as total_cost_minor,
  -- BUD-5 committed spend
  coalesce(sum(cf.effective_cost_minor) filter (where cf.status in ('confirmed','booked','completed')), 0)::bigint as committed_spend_minor,
  -- BUD-6 financial history (NOT filtered by commitment status - see §8 amendment)
  coalesce(pf.gross_paid, 0)::bigint as gross_paid_minor,
  coalesce(pf.refunded, 0)::bigint   as refunded_minor,
  (coalesce(pf.gross_paid,0) - coalesce(pf.refunded,0))::bigint as net_actual_spend_minor,
  -- BUD-7 outstanding: per-committed-commitment floor, then sum
  coalesce(sum(cf.outstanding_minor) filter (where cf.status in ('confirmed','booked','completed')), 0)::bigint as outstanding_minor,
  -- PAY-14 scheduled outstanding
  coalesce(pf.scheduled_out, 0)::bigint as scheduled_outstanding_minor,
  -- BUD-8 / BUD-9 (null when no budget row / null target)
  b.total_target_minor,
  case when b.total_target_minor is null then null
       else b.total_target_minor
            - coalesce(sum(cf.effective_cost_minor) filter (where cf.status <> 'cancelled'), 0)
  end::bigint as remaining_budget_minor,
  case when b.total_target_minor is null then null
       else b.total_target_minor
            - coalesce(sum(cf.effective_cost_minor) filter (where cf.status <> 'cancelled'), 0)
  end::bigint as projected_variance_minor,
  case when b.total_target_minor is null then null
       else b.total_target_minor - (coalesce(pf.gross_paid,0) - coalesce(pf.refunded,0))
  end::bigint as settled_variance_minor,
  -- VAL-49 progress %
  coalesce(round(
    100.0 * count(*) filter (where cf.status in ('confirmed','booked','completed'))
    / nullif(count(*) filter (where cf.status <> 'cancelled'), 0)
  ), 0)::int as progress_pct,
  count(*) filter (where cf.status <> 'cancelled')                        as commitment_count,
  count(*) filter (where cf.status not in ('cancelled','completed'))      as open_commitment_count,
  case when b.total_target_minor > 0 then round(100.0 * coalesce(sum(cf.effective_cost_minor) filter(where cf.status<>'cancelled'),0) / b.total_target_minor,1) else null end as budget_used_pct
from public.projects pr
left join public.v_commitment_financials cf on cf.project_id = pr.id
left join public.budgets b on b.project_id = pr.id
left join lateral (
  select
    coalesce(sum(pay.amount_minor) filter (where pay.status='paid' and pay.direction='outgoing'),0) as gross_paid,
    coalesce(sum(pay.amount_minor) filter (where pay.status='paid' and pay.direction='incoming'),0) as refunded,
    coalesce(sum(pay.amount_minor) filter (where pay.status='scheduled'),0) as scheduled_out
  from public.payments pay
  join public.commitments cc on cc.id = pay.commitment_id and cc.deleted_at is null
  where pay.project_id = pr.id and pay.deleted_at is null and pay.settlement_group_id is null
) pf on true
where pr.deleted_at is null
group by pr.id, pf.gross_paid, pf.refunded, pf.scheduled_out, b.total_target_minor;

-- Only atomic beta-created one-to-one task ledgers are folded into their Task.
-- Ordinary linked work stays a separate cost-free Item; the expense appears once.
create view public.v_beta_task_ledgers with(security_invoker=true) as
select c.id as commitment_id,t.id as task_id
from public.commitments c join public.tasks t on t.commitment_id=c.id
where c.deleted_at is null and t.deleted_at is null and c.activity_type='task'
 and c.title=t.title and c.created_at=t.created_at
 and not exists(select 1 from public.tasks other where other.commitment_id=c.id and other.id<>t.id and other.deleted_at is null);
create view public.v_project_items with(security_invoker=true) as
select c.id,c.project_id,c.area_id,'commitment'::text as source,c.id as financial_id,
 c.title,c.activity_type::text as item_type,c.status::text as status,c.owner_member_id as assignee_member_id,
 c.starts_at as item_date,c.notes,c.recurrence_frequency::text as recurrence_frequency,
 coalesce(c.actual_cost_minor,c.confirmed_cost_minor,c.estimated_cost_minor) as cost_minor,
 f.net_paid_minor as paid_minor,f.outstanding_minor,c.created_at
from public.commitments c join public.v_commitment_financials f on f.commitment_id=c.id
where c.deleted_at is null and not exists(select 1 from public.v_beta_task_ledgers b where b.commitment_id=c.id)
union all
select t.id,t.project_id,coalesce(t.area_id,c.area_id),'task',b.commitment_id,
 t.title,t.item_type,t.status::text,t.assignee_member_id,
 (t.due_on::timestamp at time zone p.timezone),t.notes,t.recurrence_frequency::text,
 case when b.commitment_id is not null then coalesce(c.actual_cost_minor,c.confirmed_cost_minor,c.estimated_cost_minor) end,
 coalesce(f.net_paid_minor,0),coalesce(f.outstanding_minor,0),t.created_at
from public.tasks t join public.projects p on p.id=t.project_id
left join public.commitments c on c.id=t.commitment_id and c.deleted_at is null
left join public.v_beta_task_ledgers b on b.task_id=t.id
left join public.v_commitment_financials f on f.commitment_id=b.commitment_id
where t.deleted_at is null and p.deleted_at is null;
create view public.v_area_totals with(security_invoker=true) as
select project_id,area_id,count(*)::int as item_count,
 coalesce(sum(cost_minor) filter(where status<>'cancelled'),0)::bigint as cost_minor,
 coalesce(sum(paid_minor),0)::bigint as spent_minor
from public.v_project_items group by project_id,area_id;
create view public.v_item_member_balances with(security_invoker=true) as
select s.project_id,s.commitment_id,s.member_id,s.display_name,s.member_status,
 case when i.status='cancelled' then 0 else s.allocated_minor end::bigint as allocated_minor,
 s.paid_minor,(case when i.status='cancelled' then 0 else s.allocated_minor end-s.paid_minor)::bigint as remaining_minor,
 i.id as item_id,i.title as item_title,i.area_id,a.title as area_title
from public.v_activity_member_settlements s join public.v_project_items i on i.financial_id=s.commitment_id
left join public.project_areas a on a.id=i.area_id;
grant select on public.v_beta_task_ledgers,public.v_project_items,public.v_area_totals,public.v_item_member_balances to authenticated;
