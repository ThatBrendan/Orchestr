-- ============================================================================
-- 20260904120300_domain_triggers
-- Business-rule enforcement that a plain FK / single-row CHECK cannot express.
--
-- Source of truth: docs/DATABASE_SCHEMA.md §7 ; docs/BUSINESS_RULES.md §1-9
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Actor stamping (created_by / added_by / actor_member_id)  — §7 GC, DATABASE_SCHEMA §8.1
-- ---------------------------------------------------------------------------
create or replace function app.tg_set_created_by()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.created_by is null then
    new.created_by := app.current_member_id(new.project_id);
  end if;
  return new;
end;
$$;
revoke execute on function app.tg_set_created_by() from public;

create trigger set_created_by before insert on public.commitments
  for each row execute function app.tg_set_created_by();
create trigger set_created_by before insert on public.payments
  for each row execute function app.tg_set_created_by();
create trigger set_created_by before insert on public.tasks
  for each row execute function app.tg_set_created_by();
create trigger set_created_by before insert on public.milestones
  for each row execute function app.tg_set_created_by();

create or replace function app.tg_set_participant_added_by()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.added_by is null then
    new.added_by := app.current_member_id(new.project_id);
  end if;
  return new;
end;
$$;
revoke execute on function app.tg_set_participant_added_by() from public;
create trigger set_added_by before insert on public.commitment_participants
  for each row execute function app.tg_set_participant_added_by();

create or replace function app.tg_set_dismissal_actor()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.actor_member_id is null then
    new.actor_member_id := app.current_member_id(new.project_id);
  end if;
  return new;
end;
$$;
revoke execute on function app.tg_set_dismissal_actor() from public;
create trigger set_actor before insert or update on public.finding_dismissals
  for each row execute function app.tg_set_dismissal_actor();

-- ---------------------------------------------------------------------------
-- §7.2  projects <-> project_members circular dependency:
-- create the founding organizer in an AFTER INSERT trigger (no FK cycle).
-- Skips when there is no user context (seed / service_role).
-- ---------------------------------------------------------------------------
create or replace function app.tg_after_project_insert_create_member()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_member uuid;
  v_name   text;
begin
  if auth.uid() is null then
    return new;   -- seed / service_role: caller creates membership explicitly
  end if;

  select coalesce(nullif(btrim(display_name),''), split_part(email,'@',1))
    into v_name from public.users where id = auth.uid();
  v_name := left(coalesce(v_name, 'Organizer'), 80);

  insert into public.project_members (project_id, user_id, display_name, email, role, status, joined_at)
  values (new.id, auth.uid(), v_name,
          (select email from public.users where id = auth.uid()),
          'organizer', 'active', now())
  returning id into v_member;

  update public.projects set created_by = v_member where id = new.id;
  return new;
end;
$$;
revoke execute on function app.tg_after_project_insert_create_member() from public;

create trigger after_insert_create_member
  after insert on public.projects
  for each row execute function app.tg_after_project_insert_create_member();

-- ---------------------------------------------------------------------------
-- §7.7  Status-transition state machines
-- ---------------------------------------------------------------------------
create or replace function app.tg_project_status_transition()
returns trigger language plpgsql as $$
begin
  if new.status = old.status then
    return new;
  end if;
  if not (
       (old.status = 'draft'     and new.status in ('active','archived'))
    or (old.status = 'active'    and new.status in ('completed','archived'))
    or (old.status = 'completed' and new.status in ('active','archived'))
    or (old.status = 'archived'  and new.status in ('active','completed'))
  ) then
    raise exception 'orchestr:bad_status_transition:project % -> %', old.status, new.status using errcode = 'P0001';
  end if;
  new.archived_at := case when new.status = 'archived' then coalesce(old.archived_at, now()) else null end;
  return new;
end;
$$;
create trigger status_transition before update of status on public.projects
  for each row execute function app.tg_project_status_transition();

create or replace function app.tg_commitment_status_transition()
returns trigger language plpgsql as $$
begin
  if new.status = old.status then
    return new;
  end if;
  if not (
       (old.status = 'idea'       and new.status in ('researching','cancelled'))
    or (old.status = 'researching' and new.status in ('idea','confirmed','cancelled'))
    or (old.status = 'confirmed'  and new.status in ('researching','booked','cancelled'))
    or (old.status = 'booked'     and new.status in ('confirmed','completed','cancelled'))
    or (old.status = 'completed'  and new.status in ('booked'))
    or (old.status = 'cancelled'  and new.status in ('researching'))
  ) then
    raise exception 'orchestr:bad_status_transition:commitment % -> %', old.status, new.status using errcode = 'P0001';
  end if;
  return new;
end;
$$;
create trigger status_transition before update of status on public.commitments
  for each row execute function app.tg_commitment_status_transition();

create or replace function app.tg_payment_status_transition()
returns trigger language plpgsql as $$
begin
  if new.status = old.status then
    return new;
  end if;
  if not (
       (old.status = 'scheduled' and new.status in ('paid','waived','cancelled'))
    or (old.status = 'paid'      and new.status in ('scheduled','waived','cancelled'))
    or (old.status = 'waived'    and new.status in ('scheduled'))
    or (old.status = 'cancelled' and new.status in ('scheduled'))
  ) then
    raise exception 'orchestr:bad_status_transition:payment % -> %', old.status, new.status using errcode = 'P0001';
  end if;
  if new.status = 'paid' then
    new.ever_paid := true;   -- latch; never cleared (deviation D1)
  end if;
  return new;
end;
$$;
create trigger status_transition before update of status on public.payments
  for each row execute function app.tg_payment_status_transition();

create or replace function app.tg_task_status_transition()
returns trigger language plpgsql as $$
begin
  if new.status = old.status then
    return new;
  end if;
  if not (
       (old.status = 'open'        and new.status in ('in_progress','done','cancelled'))
    or (old.status = 'in_progress' and new.status in ('open','done','cancelled'))
    or (old.status = 'done'        and new.status in ('open','in_progress'))
    or (old.status = 'cancelled'   and new.status in ('open','in_progress'))
  ) then
    raise exception 'orchestr:bad_status_transition:task % -> %', old.status, new.status using errcode = 'P0001';
  end if;
  new.completed_at := case when new.status = 'done' then coalesce(old.completed_at, now()) else null end;
  return new;
end;
$$;
create trigger status_transition before update of status on public.tasks
  for each row execute function app.tg_task_status_transition();

-- Also latch ever_paid when a payment is INSERTed directly as 'paid'
create or replace function app.tg_payment_insert_latch()
returns trigger language plpgsql as $$
begin
  if new.status = 'paid' then new.ever_paid := true; end if;
  return new;
end;
$$;
create trigger insert_latch before insert on public.payments
  for each row execute function app.tg_payment_insert_latch();

-- ---------------------------------------------------------------------------
-- §7.5  Currency immutability once money exists (incl. soft-deleted)
-- ---------------------------------------------------------------------------
create or replace function app.tg_currency_immutable()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.currency is distinct from old.currency then
    if exists (select 1 from public.commitments where project_id = old.id)
       or exists (select 1 from public.payments where project_id = old.id) then
      raise exception 'orchestr:currency_locked:currency cannot change once commitments or payments exist'
        using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;
revoke execute on function app.tg_currency_immutable() from public;
create trigger currency_immutable before update of currency on public.projects
  for each row execute function app.tg_currency_immutable();

-- ---------------------------------------------------------------------------
-- §7.6  Last-organizer guarantee (demote / remove / leave / soft-delete member)
-- ---------------------------------------------------------------------------
create or replace function app.tg_last_organizer_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_was_active_org boolean;
  v_still_active_org boolean;
  v_others int;
begin
  if pg_trigger_depth() > 1 then
    return coalesce(new, old);   -- nested cascade (e.g. project soft-delete): not a governance change
  end if;
  v_was_active_org := (old.role = 'organizer' and old.status = 'active' and old.deleted_at is null);
  if not v_was_active_org then
    return coalesce(new, old);
  end if;

  if tg_op = 'DELETE' then
    v_still_active_org := false;
  else
    v_still_active_org := (new.role = 'organizer' and new.status = 'active' and new.deleted_at is null);
  end if;

  if v_still_active_org then
    return new;   -- this row is still an active organizer: fine
  end if;

  select count(*) into v_others
  from public.project_members
  where project_id = old.project_id
    and id <> old.id
    and role = 'organizer' and status = 'active' and deleted_at is null;

  if v_others = 0 then
    raise exception 'orchestr:last_organizer:a project must keep at least one active organizer'
      using errcode = 'P0001';
  end if;
  return coalesce(new, old);
end;
$$;
revoke execute on function app.tg_last_organizer_guard() from public;
create trigger last_organizer_guard
  before update or delete on public.project_members
  for each row execute function app.tg_last_organizer_guard();

-- ---------------------------------------------------------------------------
-- §7  member_status transitions + timestamp maintenance
-- ---------------------------------------------------------------------------
create or replace function app.tg_member_status_transition()
returns trigger language plpgsql as $$
begin
  if new.status = old.status then
    return new;
  end if;
  if not (
       (old.status = 'invited' and new.status in ('active','removed'))
    or (old.status = 'active'  and new.status in ('removed'))
    or (old.status = 'removed' and new.status in ('active'))
  ) then
    raise exception 'orchestr:bad_status_transition:member % -> %', old.status, new.status using errcode = 'P0001';
  end if;
  new.removed_at := case when new.status = 'removed' then coalesce(old.removed_at, now()) else null end;
  if new.status = 'active' and old.status <> 'active' then
    new.joined_at := coalesce(old.joined_at, now());
  end if;
  return new;
end;
$$;
create trigger member_status_transition before update of status on public.project_members
  for each row execute function app.tg_member_status_transition();

-- ---------------------------------------------------------------------------
-- §5.3 SECURITY_RLS  tg_member_update_guard: non-organizer self-service is
-- limited to display_name and leaving (active -> removed).
-- ---------------------------------------------------------------------------
create or replace function app.tg_member_update_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if pg_trigger_depth() > 1 then
    return new;   -- nested trigger effect (cascades)
  end if;
  if coalesce(current_setting('app.bypass_member_guard', true), '') = 'on' then
    return new;   -- privileged RPC (accept_invitation) claiming/linking a membership row
  end if;
  if auth.uid() is null then
    return new;   -- seed / service_role
  end if;
  if app.is_organizer(old.project_id) then
    if new.user_id is distinct from old.user_id then
      raise exception 'orchestr:forbidden_member_change:user linkage is managed by invitations only'
        using errcode = 'P0001';
    end if;
    return new;   -- organizers: otherwise gated by last_organizer_guard + status_transition only
  end if;

  -- self-service path
  if old.user_id is distinct from auth.uid() then
    raise exception 'orchestr:forbidden_member_change:not permitted' using errcode = 'P0001';
  end if;
  if new.role is distinct from old.role
     or new.email is distinct from old.email
     or new.user_id is distinct from old.user_id then
    raise exception 'orchestr:forbidden_member_change:only your display name can be changed'
      using errcode = 'P0001';
  end if;
  if new.status is distinct from old.status and not (old.status = 'active' and new.status = 'removed') then
    raise exception 'orchestr:forbidden_member_change:you may only leave the project' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
revoke execute on function app.tg_member_update_guard() from public;
create trigger member_update_guard before update on public.project_members
  for each row execute function app.tg_member_update_guard();

-- ---------------------------------------------------------------------------
-- §7.1  Residual role/status predicates (FK already guarantees same project)
-- ---------------------------------------------------------------------------
create or replace function app.tg_commitment_owner_role_check()
returns trigger language plpgsql security definer set search_path = '' as $$
declare r record;
begin
  if new.owner_member_id is null then return new; end if;
  select role, status into r from public.project_members where id = new.owner_member_id;
  if r.status <> 'active' or r.role not in ('organizer','member') then
    raise exception 'orchestr:invalid_owner:owner must be an active organizer or member' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
revoke execute on function app.tg_commitment_owner_role_check() from public;
create trigger owner_role_check before insert or update of owner_member_id on public.commitments
  for each row execute function app.tg_commitment_owner_role_check();

create or replace function app.tg_task_assignee_role_check()
returns trigger language plpgsql security definer set search_path = '' as $$
declare r record;
begin
  if new.assignee_member_id is null then return new; end if;
  select role, status into r from public.project_members where id = new.assignee_member_id;
  if r.status <> 'active' or r.role not in ('organizer','member') then
    raise exception 'orchestr:invalid_assignee:assignee must be an active organizer or member' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
revoke execute on function app.tg_task_assignee_role_check() from public;
create trigger assignee_role_check before insert or update of assignee_member_id on public.tasks
  for each row execute function app.tg_task_assignee_role_check();

create or replace function app.tg_participant_member_active_check()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_status public.member_status;
begin
  select status into v_status from public.project_members where id = new.member_id;
  if v_status = 'removed' then
    raise exception 'orchestr:removed_member:cannot add a removed member as a participant' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
revoke execute on function app.tg_participant_member_active_check() from public;
create trigger member_active_check before insert or update of member_id on public.commitment_participants
  for each row execute function app.tg_participant_member_active_check();

-- ---------------------------------------------------------------------------
-- §7.11  cost_shares basis consistency (deferred: validate once at commit)
-- Allowed: all 'equal'  |  all 'weight'  |  mix of 'fixed' + 'equal'
-- fixed amounts must not exceed the commitment's effective cost.
-- ---------------------------------------------------------------------------
create or replace function app.tg_cost_share_basis_consistency()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_commitment uuid := coalesce(new.commitment_id, old.commitment_id);
  v_bases text[];
  v_fixed_total bigint;
  v_cost bigint;
begin
  select array_agg(distinct basis::text) into v_bases
  from public.cost_shares where commitment_id = v_commitment;

  if v_bases is null then
    return coalesce(new, old);   -- all removed
  end if;

  if not (
       v_bases <@ array['equal']
    or v_bases <@ array['weight']
    or v_bases <@ array['fixed','equal']
  ) then
    raise exception 'orchestr:cost_share_mix:a commitment''s cost shares must be all equal, all weight, or a mix of fixed and equal'
      using errcode = 'P0001';
  end if;

  if 'fixed' = any (v_bases) then
    select coalesce(sum(fixed_amount_minor),0) into v_fixed_total
    from public.cost_shares where commitment_id = v_commitment and basis = 'fixed';
    select coalesce(confirmed_cost_minor, estimated_cost_minor, 0) into v_cost
    from public.commitments where id = v_commitment;
    if v_fixed_total > v_cost then
      raise exception 'orchestr:cost_share_overflow:fixed shares (%) exceed the commitment cost (%)',
        v_fixed_total, v_cost
        using errcode = 'P0001';
    end if;
  end if;
  return coalesce(new, old);
end;
$$;
revoke execute on function app.tg_cost_share_basis_consistency() from public;
create constraint trigger cost_share_basis_consistency
  after insert or update or delete on public.cost_shares
  deferrable initially deferred
  for each row execute function app.tg_cost_share_basis_consistency();

-- ---------------------------------------------------------------------------
-- §7.8b  Payment guards
-- ---------------------------------------------------------------------------
create or replace function app.tg_payment_no_create_on_cancelled()
returns trigger language plpgsql security definer set search_path = '' as $$
declare c record;
begin
  select status, deleted_at into c from public.commitments where id = new.commitment_id;
  if c.deleted_at is not null or c.status = 'cancelled' then
    raise exception 'orchestr:commitment_not_active:cannot add a payment to a cancelled or deleted commitment'
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;
revoke execute on function app.tg_payment_no_create_on_cancelled() from public;
create trigger no_create_on_cancelled before insert on public.payments
  for each row execute function app.tg_payment_no_create_on_cancelled();

create or replace function app.tg_payment_soft_delete_guard()
returns trigger language plpgsql as $$
begin
  if pg_trigger_depth() > 1 then
    return new;   -- project soft-delete cascade: everything is marked deleted (restorable)
  end if;
  if old.deleted_at is null and new.deleted_at is not null then
    if new.ever_paid or old.ever_paid or new.status = 'paid' or old.status = 'paid' then
      raise exception 'orchestr:paid_payment_immutable:a payment that has been paid cannot be deleted — cancel or waive it instead'
        using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;
create trigger soft_delete_guard before update on public.payments
  for each row execute function app.tg_payment_soft_delete_guard();

create or replace function app.tg_payment_paid_on_not_future()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_today date;
begin
  if new.paid_on is null then return new; end if;
  select (now() at time zone p.timezone)::date into v_today
  from public.projects p where p.id = new.project_id;
  if new.paid_on > v_today then
    raise exception 'orchestr:future_paid_on:paid_on cannot be in the future' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
revoke execute on function app.tg_payment_paid_on_not_future() from public;
create trigger paid_on_not_future before insert or update of paid_on on public.payments
  for each row execute function app.tg_payment_paid_on_not_future();

-- ---------------------------------------------------------------------------
-- §7.8  draft -> active auto-transition
-- ---------------------------------------------------------------------------
create or replace function app.tg_commitment_activates_project()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.projects set status = 'active'
  where id = new.project_id and status = 'draft';
  return new;
end;
$$;
revoke execute on function app.tg_commitment_activates_project() from public;
create trigger activates_project after insert on public.commitments
  for each row execute function app.tg_commitment_activates_project();

create or replace function app.tg_member_activates_project()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.project_members
      where project_id = new.project_id and status = 'active' and deleted_at is null) >= 2 then
    update public.projects set status = 'active'
    where id = new.project_id and status = 'draft';
  end if;
  return new;
end;
$$;
revoke execute on function app.tg_member_activates_project() from public;
create trigger activates_project after insert or update of status on public.project_members
  for each row execute function app.tg_member_activates_project();

-- ---------------------------------------------------------------------------
-- §7.4  Soft-delete + cancel cascades
-- ---------------------------------------------------------------------------
create or replace function app.tg_commitment_cancel_cascade()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_cancelled boolean := (new.status = 'cancelled' and old.status <> 'cancelled');
  v_deleted   boolean := (old.deleted_at is null and new.deleted_at is not null);
begin
  if not (v_cancelled or v_deleted) then
    return new;
  end if;

  -- scheduled payments -> cancelled  (paid / waived untouched: financial history)
  update public.payments
     set status = 'cancelled'
   where commitment_id = new.id and status = 'scheduled' and deleted_at is null;

  -- milestone link cleared; milestone survives (COM-44)
  update public.milestones
     set commitment_id = null
   where commitment_id = new.id;

  -- on soft delete only: child tasks soft-deleted too (TSK-13)
  if v_deleted then
    update public.tasks
       set deleted_at = now()
     where commitment_id = new.id and deleted_at is null;
  end if;
  return new;
end;
$$;
revoke execute on function app.tg_commitment_cancel_cascade() from public;
create trigger cancel_cascade after update of status, deleted_at on public.commitments
  for each row execute function app.tg_commitment_cancel_cascade();

create or replace function app.tg_project_soft_delete_cascade()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.deleted_at is null and new.deleted_at is not null then
    update public.project_members set deleted_at = now() where project_id = new.id and deleted_at is null;
    update public.commitments     set deleted_at = now() where project_id = new.id and deleted_at is null;
    update public.payments        set deleted_at = now() where project_id = new.id and deleted_at is null;
    update public.tasks           set deleted_at = now() where project_id = new.id and deleted_at is null;
  elsif old.deleted_at is not null and new.deleted_at is null then
    -- restore (service_role / support path)
    update public.project_members set deleted_at = null where project_id = new.id and deleted_at = old.deleted_at;
    update public.commitments     set deleted_at = null where project_id = new.id and deleted_at = old.deleted_at;
    update public.payments        set deleted_at = null where project_id = new.id and deleted_at = old.deleted_at;
    update public.tasks           set deleted_at = null where project_id = new.id and deleted_at = old.deleted_at;
  end if;
  return new;
end;
$$;
revoke execute on function app.tg_project_soft_delete_cascade() from public;
create trigger soft_delete_cascade after update of deleted_at on public.projects
  for each row execute function app.tg_project_soft_delete_cascade();

-- ---------------------------------------------------------------------------
-- §9 HLT-F  finding_dismissals: blockers cannot be dismissed/snoozed
-- ---------------------------------------------------------------------------
create or replace function app.tg_dismissal_not_blocker()
returns trigger language plpgsql as $$
begin
  if not app.finding_is_dismissible(new.code) then
    raise exception 'orchestr:blocker_not_dismissible:blocker findings cannot be dismissed or snoozed'
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;
create trigger not_blocker before insert or update on public.finding_dismissals
  for each row execute function app.tg_dismissal_not_blocker();

-- ---------------------------------------------------------------------------
-- §7.10  Archived project => child tables read-only
-- ---------------------------------------------------------------------------
create trigger enforce_writable before insert or update or delete on public.project_members
  for each row execute function app.tg_enforce_project_writable();
create trigger enforce_writable before insert or update or delete on public.invitations
  for each row execute function app.tg_enforce_project_writable();
create trigger enforce_writable before insert or update or delete on public.commitments
  for each row execute function app.tg_enforce_project_writable();
create trigger enforce_writable before insert or update or delete on public.commitment_participants
  for each row execute function app.tg_enforce_project_writable();
create trigger enforce_writable before insert or update or delete on public.cost_shares
  for each row execute function app.tg_enforce_project_writable();
create trigger enforce_writable before insert or update or delete on public.payments
  for each row execute function app.tg_enforce_project_writable();
create trigger enforce_writable before insert or update or delete on public.tasks
  for each row execute function app.tg_enforce_project_writable();
create trigger enforce_writable before insert or update or delete on public.milestones
  for each row execute function app.tg_enforce_project_writable();
create trigger enforce_writable before insert or update or delete on public.budgets
  for each row execute function app.tg_enforce_project_writable();
create trigger enforce_writable before insert or update or delete on public.budget_category_targets
  for each row execute function app.tg_enforce_project_writable();
create trigger enforce_writable before insert or update or delete on public.finding_dismissals
  for each row execute function app.tg_enforce_project_writable();
