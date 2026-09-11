-- Null preserves legacy participant/equal/weight rules, including legacy API inserts.
-- The new Activity save RPC explicitly creates No split.
alter table public.commitments add column cost_split_mode text check(cost_split_mode in ('none','even','custom'));

create function app.validate_activity_split(p_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare c public.commitments%rowtype; n int; total numeric;
begin
 select * into c from public.commitments where id=p_id;
 if not found or c.cost_split_mode is null then return; end if;
 select count(*),coalesce(sum(fixed_amount_minor),0) into n,total from public.cost_shares where commitment_id=p_id;
 if c.cost_split_mode='none' then
   if n>0 then raise exception 'orchestr:split_invalid:No split must have no allocations.'; end if;
 elsif coalesce(c.actual_cost_minor,c.confirmed_cost_minor,c.estimated_cost_minor) is null or n=0 or total<>app.effective_commitment_cost(c.actual_cost_minor,c.confirmed_cost_minor,c.estimated_cost_minor)
   or exists(select 1 from public.cost_shares where commitment_id=p_id and basis<>'fixed') then
   raise exception 'orchestr:split_reconcile:Cost changed or allocation is incomplete. Recalculate evenly or edit the cost split before saving.';
 end if;
 if c.cost_split_mode='even' and exists (
  select 1 from (
   select fixed_amount_minor,row_number() over(order by member_id) as rn
   from public.cost_shares where commitment_id=p_id
  ) s where fixed_amount_minor<>(total::bigint/n + case when rn<=total::bigint%n then 1 else 0 end)
 ) then raise exception 'orchestr:split_reconcile:Recalculate evenly or choose Custom split.'; end if;
end $$;
revoke all on function app.validate_activity_split(uuid) from public;

create function app.tg_validate_activity_split() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name='commitments' and tg_op='UPDATE' then
  if old.cost_split_mode is not null and new.cost_split_mode is null then
   raise exception 'orchestr:split_invalid:Choose an explicit cost split mode.';
  end if;
  if old.cost_split_mode is null and
    app.effective_commitment_cost(old.actual_cost_minor,old.confirmed_cost_minor,old.estimated_cost_minor) is distinct from app.effective_commitment_cost(new.actual_cost_minor,new.confirmed_cost_minor,new.estimated_cost_minor)
    and exists(select 1 from public.commitments where id=new.id and cost_split_mode is null)
    and (exists(select 1 from public.cost_shares where commitment_id=new.id) or exists(select 1 from public.commitment_participants where commitment_id=new.id)) then
   raise exception 'orchestr:split_reconcile:Review the existing cost split before changing this cost.';
  end if;
 end if;
 if tg_table_name='commitments' then perform app.validate_activity_split(coalesce(new.id,old.id));
 else
  perform app.validate_activity_split(coalesce(new.commitment_id,old.commitment_id));
  -- Legacy fixed-only overrides may be retained, but new writes must fully allocate.
  if exists(select 1 from public.commitments c where c.id=coalesce(new.commitment_id,old.commitment_id) and c.cost_split_mode is null
    and exists(select 1 from public.cost_shares where commitment_id=c.id)
    and not exists(select 1 from public.cost_shares where commitment_id=c.id and basis<>'fixed')
    and (select sum(fixed_amount_minor) from public.cost_shares where commitment_id=c.id)<>app.effective_commitment_cost(c.actual_cost_minor,c.confirmed_cost_minor,c.estimated_cost_minor)) then
   raise exception 'orchestr:split_reconcile:Allocate the full cost when editing this split.';
  end if;
 end if;
 return coalesce(new,old);
end $$;
revoke all on function app.tg_validate_activity_split() from public;
create constraint trigger activity_split_total after insert or update on public.commitments
 deferrable initially deferred for each row execute function app.tg_validate_activity_split();
create constraint trigger activity_share_total after insert or update or delete on public.cost_shares
 deferrable initially deferred for each row execute function app.tg_validate_activity_split();

-- Serialize share changes with Activity edits and reject removed/unrelated recipients.
create function app.tg_share_member_guard() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if tg_op='UPDATE' and new.commitment_id is distinct from old.commitment_id then
  raise exception 'orchestr:immutable_column:An allocation cannot move to another Activity.';
 end if;
 perform 1 from public.commitments where id=coalesce(new.commitment_id,old.commitment_id) for update;
 if tg_op<>'DELETE' then
  perform 1 from public.project_members where id=new.member_id and project_id=new.project_id and status='active' and deleted_at is null for share;
  if not found then raise exception 'orchestr:invalid_member:Select an active member of this project.' using errcode='42501'; end if;
 end if;
 return coalesce(new,old);
end $$;
revoke all on function app.tg_share_member_guard() from public;
create trigger share_member_guard before insert or update or delete on public.cost_shares
 for each row execute function app.tg_share_member_guard();

create function public.set_activity_cost_split(p_commitment uuid,p_split jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare c public.commitments%rowtype; mode text:=p_split->>'mode'; ids uuid[]; n int; cost bigint; r record;
begin
 select * into c from public.commitments where id=p_commitment and deleted_at is null for update;
 if not found or not app.has_role(c.project_id,array['organizer','member']::public.member_role[]) or not app.is_writable_project(c.project_id) then
  raise exception 'orchestr:not_authorized:You cannot edit this cost split.' using errcode='42501'; end if;
 if mode is null or mode not in ('none','even','custom') then raise exception 'orchestr:invalid_split:Choose a cost split mode.'; end if;
 cost:=app.effective_commitment_cost(c.actual_cost_minor,c.confirmed_cost_minor,c.estimated_cost_minor);
 if mode<>'none' then
  if coalesce(c.actual_cost_minor,c.confirmed_cost_minor,c.estimated_cost_minor) is null then raise exception 'orchestr:invalid_split:Add a cost before splitting it.'; end if;
  select array_agg(value::uuid order by value::uuid) into ids from jsonb_array_elements_text(p_split->'members');
  n:=coalesce(cardinality(ids),0);
  if n=0 or n<>(select count(distinct x) from unnest(ids) x) then raise exception 'orchestr:invalid_split:Select distinct participants.'; end if;
  if (p_split->>'cost')::numeric is distinct from cost::numeric then raise exception 'orchestr:split_reconcile:Cost changed. Refresh and review the split.'; end if;
  perform 1 from public.project_members where id=any(ids) and project_id=c.project_id and status='active' and deleted_at is null order by id for share;
  if (select count(*) from public.project_members where id=any(ids) and project_id=c.project_id and status='active' and deleted_at is null)<>n then
   raise exception 'orchestr:invalid_member:Select active members of this project.' using errcode='42501'; end if;
 end if;
 delete from public.cost_shares where commitment_id=p_commitment;
 update public.commitments set cost_split_mode=mode where id=p_commitment;
 if mode='even' then
  insert into public.cost_shares(project_id,commitment_id,member_id,basis,fixed_amount_minor)
  select c.project_id,c.id,id,'fixed',cost/n+case when ord<=cost%n then 1 else 0 end from unnest(ids) with ordinality t(id,ord);
 elsif mode='custom' then
  if jsonb_typeof(p_split->'amounts') is distinct from 'object' or (select count(*) from jsonb_object_keys(p_split->'amounts'))<>n then raise exception 'orchestr:invalid_split:Enter a share for each selected member.'; end if;
  for r in select id from unnest(ids) id loop
   if not coalesce((p_split->'amounts'->>r.id::text) ~ '^[0-9]+$',false) then raise exception 'orchestr:invalid_split:Shares must be non-negative integer minor units.'; end if;
   insert into public.cost_shares(project_id,commitment_id,member_id,basis,fixed_amount_minor)
   values(c.project_id,c.id,r.id,'fixed',(p_split->'amounts'->>r.id::text)::bigint);
  end loop;
 end if;
 perform app.validate_activity_split(p_commitment);
end $$;
revoke all on function public.set_activity_cost_split(uuid,jsonb) from public;
grant execute on function public.set_activity_cost_split(uuid,jsonb) to authenticated;

-- Invoker wrapper retains table RLS, column guards, status rules and audit.
create function public.save_activity_with_split(p_project uuid,p_commitment uuid,p_fields jsonb,p_split jsonb)
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
  update public.commitments set title=v.title,activity_type=v.activity_type,kind=v.kind,owner_member_id=v.owner_member_id,is_all_day=v.is_all_day,starts_at=v.starts_at,ends_at=v.ends_at,location_label=v.location_label,location_address=v.location_address,supplier_name=v.supplier_name,supplier_contact=v.supplier_contact,booking_reference=v.booking_reference,booking_confirmed=v.booking_confirmed,estimated_cost_minor=v.estimated_cost_minor,recurrence_frequency=v.recurrence_frequency,recurrence_interval=v.recurrence_interval,recurrence_start_date=v.recurrence_start_date,recurrence_end_date=v.recurrence_end_date,recurrence_active=v.recurrence_active,notes=v.notes where id=p_commitment returning * into c;
  if not found then raise exception 'orchestr:not_authorized:Activity cannot be edited.' using errcode='42501'; end if;
 end if;
 if p_split is not null then perform public.set_activity_cost_split(c.id,p_split); end if;
 select * into c from public.commitments where id=c.id;
 return c;
end $$;
revoke all on function public.save_activity_with_split(uuid,uuid,jsonb,jsonb) from public;
grant execute on function public.save_activity_with_split(uuid,uuid,jsonb,jsonb) to authenticated;

create function public.set_actual_cost_with_split(p_commitment uuid,p_amount numeric,p_complete boolean,p_split jsonb)
returns void language plpgsql security invoker set search_path='' as $$
begin
 perform public.set_commitment_actual_cost(p_commitment,p_amount,p_complete);
 if p_split is not null then perform public.set_activity_cost_split(p_commitment,p_split); end if;
end $$;
revoke all on function public.set_actual_cost_with_split(uuid,numeric,boolean,jsonb) from public;
grant execute on function public.set_actual_cost_with_split(uuid,numeric,boolean,jsonb) to authenticated;

create view public.v_activity_cost_shares with (security_invoker=true) as
with
tc as (
  select c.id, c.project_id,
         app.effective_commitment_cost(c.actual_cost_minor,c.confirmed_cost_minor,c.estimated_cost_minor)::bigint as cost
  from public.commitments c
  where c.cost_split_mode is distinct from 'none' and c.deleted_at is null
),
cs as (
  select s.commitment_id, s.member_id, s.basis, s.weight, s.fixed_amount_minor
  from public.cost_shares s
  join tc on tc.id = s.commitment_id
),
cs_commitments as (select distinct commitment_id from cs),
fixed_tot as (
  select commitment_id, coalesce(sum(fixed_amount_minor),0) as ft
  from cs where basis = 'fixed' group by commitment_id
),
w_tot as (
  select commitment_id, sum(weight) as wsum
  from cs where basis = 'weight' group by commitment_id
),
-- weight basis (exclusive): floor then hand remainder to lowest member_ids
share_weight_base as (
  select cs.commitment_id, cs.member_id, tc.cost,
         floor(tc.cost * cs.weight / w_tot.wsum)::bigint as base_share,
         row_number() over (partition by cs.commitment_id order by cs.member_id) as rn
  from cs
  join tc on tc.id = cs.commitment_id
  join w_tot on w_tot.commitment_id = cs.commitment_id
  where cs.basis = 'weight'
),
share_weight as (
  select commitment_id, member_id,
         base_share + case when rn <= (cost - sum(base_share) over (partition by commitment_id))
                           then 1 else 0 end as share
  from share_weight_base
),
share_fixed as (
  select commitment_id, member_id, fixed_amount_minor::bigint as share
  from cs where basis = 'fixed'
),
equal_expl_base as (
  select cs.commitment_id, cs.member_id,
         (tc.cost - coalesce(ft.ft,0))::bigint as pot,
         count(*) over (partition by cs.commitment_id) as n,
         row_number() over (partition by cs.commitment_id order by cs.member_id) as rn
  from cs
  join tc on tc.id = cs.commitment_id
  left join fixed_tot ft on ft.commitment_id = cs.commitment_id
  where cs.basis = 'equal'
),
share_equal_expl as (
  select commitment_id, member_id,
         (pot / n) + case when rn <= (pot - (pot/n)*n) then 1 else 0 end as share
  from equal_expl_base
),
part_base as (
  select cp.commitment_id, cp.member_id, tc.cost::bigint as pot,
         count(*) over (partition by cp.commitment_id) as n,
         row_number() over (partition by cp.commitment_id order by cp.member_id) as rn
  from public.commitment_participants cp
  join tc on tc.id = cp.commitment_id
  where cp.commitment_id not in (select commitment_id from cs_commitments)
),
share_default as (
  select commitment_id, member_id,
         (pot / n) + case when rn <= (pot - (pot/n)*n) then 1 else 0 end as share
  from part_base
),
all_shares as (
  select commitment_id, member_id, share from share_weight
  union all select commitment_id, member_id, share from share_fixed
  union all select commitment_id, member_id, share from share_equal_expl
  union all select commitment_id, member_id, share from share_default
)
select tc.project_id,s.commitment_id,s.member_id,s.share::bigint as amount_minor from all_shares s join tc on tc.id=s.commitment_id;
grant select on public.v_activity_cost_shares to authenticated;

create or replace view public.v_member_balances
with (security_invoker = true) as
with
tc as (
  select c.id, c.project_id,
         app.effective_commitment_cost(c.actual_cost_minor,c.confirmed_cost_minor,c.estimated_cost_minor)::bigint as cost
  from public.commitments c
  where c.cost_split_mode is distinct from 'none' and c.deleted_at is null and c.status in ('confirmed','booked','completed')
),
cs as (
  select s.commitment_id, s.member_id, s.basis, s.weight, s.fixed_amount_minor
  from public.cost_shares s
  join tc on tc.id = s.commitment_id
),
cs_commitments as (select distinct commitment_id from cs),
fixed_tot as (
  select commitment_id, coalesce(sum(fixed_amount_minor),0) as ft
  from cs where basis = 'fixed' group by commitment_id
),
w_tot as (
  select commitment_id, sum(weight) as wsum
  from cs where basis = 'weight' group by commitment_id
),
-- weight basis (exclusive): floor then hand remainder to lowest member_ids
share_weight_base as (
  select cs.commitment_id, cs.member_id, tc.cost,
         floor(tc.cost * cs.weight / w_tot.wsum)::bigint as base_share,
         row_number() over (partition by cs.commitment_id order by cs.member_id) as rn
  from cs
  join tc on tc.id = cs.commitment_id
  join w_tot on w_tot.commitment_id = cs.commitment_id
  where cs.basis = 'weight'
),
share_weight as (
  select commitment_id, member_id,
         base_share + case when rn <= (cost - sum(base_share) over (partition by commitment_id))
                           then 1 else 0 end as share
  from share_weight_base
),
share_fixed as (
  select commitment_id, member_id, fixed_amount_minor::bigint as share
  from cs where basis = 'fixed'
),
equal_expl_base as (
  select cs.commitment_id, cs.member_id,
         (tc.cost - coalesce(ft.ft,0))::bigint as pot,
         count(*) over (partition by cs.commitment_id) as n,
         row_number() over (partition by cs.commitment_id order by cs.member_id) as rn
  from cs
  join tc on tc.id = cs.commitment_id
  left join fixed_tot ft on ft.commitment_id = cs.commitment_id
  where cs.basis = 'equal'
),
share_equal_expl as (
  select commitment_id, member_id,
         (pot / n) + case when rn <= (pot - (pot/n)*n) then 1 else 0 end as share
  from equal_expl_base
),
part_base as (
  select cp.commitment_id, cp.member_id, tc.cost::bigint as pot,
         count(*) over (partition by cp.commitment_id) as n,
         row_number() over (partition by cp.commitment_id order by cp.member_id) as rn
  from public.commitment_participants cp
  join tc on tc.id = cp.commitment_id
  where cp.commitment_id not in (select commitment_id from cs_commitments)
),
share_default as (
  select commitment_id, member_id,
         (pot / n) + case when rn <= (pot - (pot/n)*n) then 1 else 0 end as share
  from part_base
),
all_shares as (
  select commitment_id, member_id, share from share_weight
  union all select commitment_id, member_id, share from share_fixed
  union all select commitment_id, member_id, share from share_equal_expl
  union all select commitment_id, member_id, share from share_default
),
owed as (
  select tc.project_id, s.member_id, sum(s.share)::bigint as owed_minor
  from all_shares s join tc on tc.id = s.commitment_id
  group by tc.project_id, s.member_id
),
contributed as (
  select pay.project_id, pay.paid_by_member_id as member_id,
         sum(case when pay.direction = 'outgoing' then pay.amount_minor else -pay.amount_minor end)::bigint as contributed_minor
  from public.payments pay
  join public.commitments c on c.id = pay.commitment_id and c.deleted_at is null
  where pay.deleted_at is null and pay.status = 'paid' and pay.paid_by_member_id is not null
  group by pay.project_id, pay.paid_by_member_id
),
mem as (
  select id as member_id, project_id, display_name, status
  from public.project_members where deleted_at is null
)
select
  mem.project_id,
  mem.member_id,
  mem.display_name,
  mem.status as member_status,
  coalesce(o.owed_minor, 0)::bigint as owed_minor,
  coalesce(c.contributed_minor, 0)::bigint as contributed_minor,
  (coalesce(c.contributed_minor, 0) - coalesce(o.owed_minor, 0))::bigint as balance_minor
from mem
left join owed o on o.project_id = mem.project_id and o.member_id = mem.member_id
left join contributed c on c.project_id = mem.project_id and c.member_id = mem.member_id;
create or replace function app._health_findings(p_project uuid)
returns table (
  code text, severity text, subject_type text, subject_id uuid, subject_label text,
  params jsonb, message text, resolution text, affects_health boolean, dismissible boolean
)
language plpgsql stable security invoker set search_path = ''
as $$
declare
  v_tz  text;
  cfg   jsonb;
  v_now timestamptz := now();
  v_today date;
  v_ccy text;
  v_profile public.project_profile;
  v_budget_visible boolean;
  inactive_days int; due_soon_days int; tight_min int; near_days int; on_budget_window int;
begin
  select
    timezone,
    health_config,
    currency,
    profile,
    case
      when jsonb_typeof(module_visibility->'budget') = 'boolean' then (module_visibility->>'budget')::boolean
      else profile in ('group_trip','wedding_event','launch','blank')
    end
  into v_tz, cfg, v_ccy, v_profile, v_budget_visible
  from public.projects
  where id = p_project and deleted_at is null;

  if v_tz is null then return; end if;
  v_today := (v_now at time zone v_tz)::date;
  inactive_days    := coalesce((cfg->>'inactive_days')::int, 7);
  due_soon_days    := coalesce((cfg->>'due_soon_days')::int, 7);
  tight_min        := coalesce((cfg->>'tight_connection_minutes')::int, 20);
  near_days        := coalesce((cfg->>'unconfirmed_near_days')::int, 14);
  on_budget_window := coalesce((cfg->>'on_budget_window_days')::int, 30);

  return query
  -- HLT-1 missing_owner: globally relevant to in-progress/committed activity ownership.
  select 'missing_owner','warning','commitment',c.id,c.title,
         jsonb_build_object('status',c.status,'activity_type',c.activity_type),
         c.title || ' has no owner','Assign an owner',true,true
  from public.commitments c
  where c.project_id = p_project and c.deleted_at is null
    and c.status in ('researching','confirmed','booked') and c.owner_member_id is null

  union all
  -- HLT-2 orphaned_owner: globally relevant.
  select 'orphaned_owner','warning','commitment',c.id,c.title,
         jsonb_build_object('owner',m.display_name,'activity_type',c.activity_type),
         c.title || '''s owner (' || m.display_name || ') has left the project',
         'Assign a new owner',true,true
  from public.commitments c
  join public.project_members m on m.id = c.owner_member_id
  where c.project_id = p_project and c.deleted_at is null and c.status <> 'cancelled'
    and m.status = 'removed'

  union all
  -- HLT-3 payment_overdue: globally relevant when payment rows exist; blocker/non-dismissible.
  select 'payment_overdue','blocker','payment',pay.id,c.title,
         jsonb_build_object('amount_minor',pay.amount_minor,'currency',v_ccy,'due_on',pay.due_on),
         app.format_money(pay.amount_minor,v_ccy) || ' for ' || c.title || ' was due on ' || pay.due_on::text,
         'Record it as paid, or reschedule / cancel it',true,false
  from public.payments pay
  join public.commitments c on c.id = pay.commitment_id and c.deleted_at is null
  where pay.project_id = p_project and pay.deleted_at is null
    and c.status <> 'cancelled' and pay.status = 'scheduled'
    and pay.due_on is not null and pay.due_on < v_today

  union all
  -- HLT-4 payment_due_soon: globally relevant when payment rows exist.
  select 'payment_due_soon','warning','payment',pay.id,c.title,
         jsonb_build_object('amount_minor',pay.amount_minor,'currency',v_ccy,'due_on',pay.due_on),
         app.format_money(pay.amount_minor,v_ccy) || ' for ' || c.title || ' is due ' || pay.due_on::text,
         'Pay it, or snooze if on track',true,true
  from public.payments pay
  join public.commitments c on c.id = pay.commitment_id and c.deleted_at is null
  where pay.project_id = p_project and pay.deleted_at is null
    and c.status <> 'cancelled' and pay.status = 'scheduled'
    and pay.due_on is not null and pay.due_on between v_today and v_today + due_soon_days

  union all
  -- HLT-5 missing_booking_reference: booking activities only.
  select 'missing_booking_reference','warning','commitment',c.id,c.title,
         jsonb_build_object('status',c.status,'activity_type',c.activity_type),
         c.title || ' is ' || c.status || ' but has no confirmed booking reference',
         'Add the reference and mark the booking confirmed',true,true
  from public.commitments c
  where c.project_id = p_project and c.deleted_at is null
    and c.activity_type = 'booking'
    and c.status in ('confirmed','booked','completed')
    and (c.booking_reference is null or c.booking_confirmed = false)

  union all
  -- HLT-6 unconfirmed_near_date: globally relevant date readiness signal.
  select 'unconfirmed_near_date','warning','commitment',c.id,c.title,
         jsonb_build_object('status',c.status,'starts_at',c.starts_at,'activity_type',c.activity_type),
         c.title || ' is still ' || c.status || ' but happens soon',
         'Confirm it, complete it, or cancel it',true,true
  from public.commitments c
  where c.project_id = p_project and c.deleted_at is null
    and c.status in ('idea','researching') and c.starts_at is not null
    and c.starts_at <= v_now + (near_days || ' days')::interval

  union all
  -- HLT-7 commitment_inactive: globally relevant for stale planning/execution.
  select 'commitment_inactive','warning','commitment',c.id,c.title,
         jsonb_build_object('updated_at',c.updated_at,'days',inactive_days,'activity_type',c.activity_type),
         c.title || ' hasn''t been updated in ' || inactive_days || ' days',
         'Update it, advance its status, or cancel it',true,true
  from public.commitments c
  where c.project_id = p_project and c.deleted_at is null
    and c.status in ('idea','researching')
    and c.updated_at < v_now - (inactive_days || ' days')::interval

  union all
  -- HLT-8 missing_cost: financially relevant activity types only.
  select 'missing_cost','warning','commitment',c.id,c.title,
         jsonb_build_object('status',c.status,'activity_type',c.activity_type),
         c.title || ' is ' || c.status || ' but has no cost recorded',
         'Add the cost, or note that it''s free',true,true
  from public.commitments c
  where c.project_id = p_project and c.deleted_at is null
    and c.activity_type in ('booking','purchase')
    and c.status in ('confirmed','booked','completed')
    and coalesce(c.actual_cost_minor,c.confirmed_cost_minor,c.estimated_cost_minor) is null

  union all
  -- HLT-9 budget_exceeded: only relevant when the Budget module is visible.
  select 'budget_exceeded','warning','project',p_project,pr.name,
         jsonb_build_object('total_cost_minor',f.total_cost_minor,'target_minor',f.total_target_minor,'currency',v_ccy,'profile',v_profile),
         'Projected spend (' || app.format_money(f.total_cost_minor,v_ccy) || ') is over the '
           || app.format_money(f.total_target_minor,v_ccy) || ' budget',
         'Raise the budget, reduce costs, or cancel activities',true,true
  from public.v_project_financials f
  join public.projects pr on pr.id = f.project_id
  where v_budget_visible
    and f.project_id = p_project and f.total_target_minor is not null
    and f.total_cost_minor > f.total_target_minor

  union all
  -- HLT-10 category_over_target: only relevant when the Budget module is visible.
  select 'category_over_target','info','budget_category',
         md5(p_project::text || a.kind::text)::uuid, a.kind::text,
         jsonb_build_object('kind',a.kind,'actual_minor',a.actual_minor,'target_minor',a.target_minor,'currency',v_ccy,'profile',v_profile),
         a.kind || ' spend (' || app.format_money(a.actual_minor,v_ccy) || ') is over its '
           || app.format_money(a.target_minor,v_ccy) || ' target',
         'Adjust the target or the activities',false,true
  from public.v_budget_category_actuals a
  where v_budget_visible
    and a.project_id = p_project and a.target_minor is not null and a.actual_minor > a.target_minor

  union all
  -- HLT-11 schedule_conflict: globally relevant when activities have explicit time ranges.
  select 'schedule_conflict','warning','commitment_pair',
         md5(least(c1.id::text,c2.id::text) || greatest(c1.id::text,c2.id::text))::uuid,
         c1.title || ' / ' || c2.title,
         jsonb_build_object('a',c1.id,'b',c2.id),
         c1.title || ' overlaps ' || c2.title,
         'Adjust the times, or snooze if intentional',true,true
  from public.commitments c1
  join public.commitments c2
    on c2.project_id = c1.project_id and c1.id < c2.id
   and c1.deleted_at is null and c2.deleted_at is null
   and c1.status <> 'cancelled' and c2.status <> 'cancelled'
   and c1.starts_at is not null and c1.ends_at is not null
   and c2.starts_at is not null and c2.ends_at is not null
   and tstzrange(c1.starts_at,c1.ends_at) && tstzrange(c2.starts_at,c2.ends_at)
  where c1.project_id = p_project

  union all
  -- HLT-12 tight_connection: event/booking sequencing for event-like profiles only.
  select 'tight_connection','info','commitment_pair',
         md5(least(c1.id::text,c2.id::text) || greatest(c1.id::text,c2.id::text))::uuid,
         c1.title || ' -> ' || c2.title,
         jsonb_build_object('gap_minutes', extract(epoch from (c2.starts_at - c1.ends_at))/60,'profile',v_profile),
         'Only ' || round(extract(epoch from (c2.starts_at - c1.ends_at))/60)::text
           || ' min between ' || c1.title || ' and ' || c2.title,
         'Adjust times or acknowledge',false,true
  from public.commitments c1
  join public.commitments c2
    on c2.project_id = c1.project_id and c1.id <> c2.id
   and c1.deleted_at is null and c2.deleted_at is null
   and c1.status <> 'cancelled' and c2.status <> 'cancelled'
   and c1.activity_type in ('booking','event')
   and c2.activity_type in ('booking','event')
   and c1.ends_at is not null and c2.starts_at is not null
   and c2.starts_at >= c1.ends_at
   and c2.starts_at - c1.ends_at < (tight_min || ' minutes')::interval
   and (c1.starts_at at time zone v_tz)::date = (c2.starts_at at time zone v_tz)::date
  where c1.project_id = p_project
    and v_profile in ('group_trip','wedding_event','launch')

  union all
  -- HLT-13 task_overdue: globally relevant task-table signal.
  select 'task_overdue','warning','task',t.id,t.title,
         jsonb_build_object('due_on',t.due_on),
         'Task ''' || t.title || ''' was due ' || t.due_on::text,
         'Complete it, reschedule it, or cancel it',true,true
  from public.tasks t
  where t.project_id = p_project and t.deleted_at is null
    and t.status in ('open','in_progress') and t.due_on is not null and t.due_on < v_today

  union all
  -- HLT-14 task_unassigned_due_soon: globally relevant task-table signal.
  select 'task_unassigned_due_soon','info','task',t.id,t.title,
         jsonb_build_object('due_on',t.due_on),
         'Task ''' || t.title || ''' is due soon with no assignee','Assign it',false,true
  from public.tasks t
  where t.project_id = p_project and t.deleted_at is null
    and t.status in ('open','in_progress') and t.assignee_member_id is null
    and t.due_on is not null and t.due_on <= v_today + 7

  union all
  -- HLT-15 outside_project_dates: globally relevant when project boundaries exist.
  select 'outside_project_dates','info','commitment',c.id,c.title,
         jsonb_build_object('starts_at',c.starts_at,'activity_type',c.activity_type),
         c.title || ' is scheduled outside the project dates',
         'Adjust the activity or project dates',false,true
  from public.commitments c
  join public.projects pr on pr.id = c.project_id
  where c.project_id = p_project and c.deleted_at is null and c.status <> 'cancelled'
    and c.starts_at is not null and pr.starts_on is not null and pr.ends_on is not null
    and ( (c.starts_at at time zone v_tz)::date < pr.starts_on
       or (c.starts_at at time zone v_tz)::date > pr.ends_on )

  union all
  -- HLT-16 unallocated_cost: shared-cost signal only when Budget is visible.
  select 'unallocated_cost','info','commitment',c.id,c.title,
         jsonb_build_object('activity_type',c.activity_type,'profile',v_profile),
         c.title || '''s cost isn''t split between anyone',
         'Add participants or set a cost split',false,true
  from public.commitments c
  where v_budget_visible and c.cost_split_mode is null
    and c.project_id = p_project and c.deleted_at is null and c.status <> 'cancelled'
    and app.effective_commitment_cost(c.actual_cost_minor,c.confirmed_cost_minor,c.estimated_cost_minor) > 0
    and not exists (select 1 from public.commitment_participants p where p.commitment_id = c.id)
    and not exists (select 1 from public.cost_shares s where s.commitment_id = c.id)

  union all
  -- HLT-17 on_budget: only relevant when the Budget module is visible.
  select 'on_budget','ok','project',p_project,pr.name,
         jsonb_build_object('variance_minor', f.total_target_minor - f.total_cost_minor,'currency',v_ccy,'profile',v_profile),
         'Projected spend is ' || app.format_money(f.total_target_minor - f.total_cost_minor, v_ccy)
           || ' under budget - on track','',false,true
  from public.v_project_financials f
  join public.projects pr on pr.id = f.project_id
  where v_budget_visible
    and f.project_id = p_project and f.total_target_minor is not null
    and f.total_cost_minor <= f.total_target_minor
    and ( f.progress_pct >= 50
       or (pr.ends_on is not null and pr.ends_on <= v_today + on_budget_window) )

  union all
  -- HLT-18 activity_overdue: profile/activity-aware execution signal for dated activities.
  select 'activity_overdue','warning','commitment',c.id,c.title,
         jsonb_build_object('starts_at',c.starts_at,'activity_type',c.activity_type,'profile',v_profile),
         c.title || ' is overdue',
         'Complete it, reschedule it, or cancel it',true,true
  from public.commitments c
  where c.project_id = p_project and c.deleted_at is null
    and c.status not in ('completed','cancelled')
    and c.starts_at is not null
    and (c.starts_at at time zone v_tz)::date < v_today
    and (
      v_profile in ('recurring_process','team_project','house_move','launch')
      or c.activity_type in ('task','purchase','event')
    );
end;
$$;
