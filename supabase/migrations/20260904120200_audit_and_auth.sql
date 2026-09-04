-- ============================================================================
-- 20260904120200_audit_and_auth
-- Generic append-only audit trigger + immutability guard ; auth.users -> public.users mirror.
--
-- Source of truth: docs/DATABASE_SCHEMA.md §4.14, §7.12, §8.2 ; docs/SECURITY_RLS.md §5.13
-- ============================================================================

-- ---------------------------------------------------------------------------
-- app.tg_audit_row()  — AFTER INSERT/UPDATE/DELETE on every audited table.
-- SECURITY DEFINER: its only elevated need is INSERT INTO public.audit_log.
-- ---------------------------------------------------------------------------
create or replace function app.tg_audit_row()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_project   uuid;
  v_action    public.audit_action;
  v_before    jsonb;
  v_after     jsonb;
  v_old_del   text;
  v_new_del   text;
  v_member    uuid;
begin
  if tg_op = 'INSERT' then
    v_after  := to_jsonb(new);
    v_before := null;
    v_action := 'create';
    v_project := nullif(v_after->>'project_id','')::uuid;
  elsif tg_op = 'DELETE' then
    v_before := to_jsonb(old);
    v_after  := null;
    v_action := 'delete';
    v_project := nullif(v_before->>'project_id','')::uuid;
  else
    v_before := to_jsonb(old);
    v_after  := to_jsonb(new);
    v_project := nullif(v_after->>'project_id','')::uuid;
    v_old_del := v_before->>'deleted_at';
    v_new_del := v_after->>'deleted_at';
    if v_before ? 'deleted_at' and v_old_del is null and v_new_del is not null then
      v_action := 'soft_delete';
    elsif v_before ? 'deleted_at' and v_old_del is not null and v_new_del is null then
      v_action := 'restore';
    else
      v_action := 'update';
    end if;
  end if;

  if v_project is not null then
    begin
      v_member := app.current_member_id(v_project);
    exception when others then
      v_member := null;
    end;
  end if;

  insert into public.audit_log
    (project_id, actor_user_id, actor_member_id, source, action, entity_type, entity_id, before, after)
  values
    (v_project, auth.uid(), v_member, 'app', v_action, tg_table_name,
     coalesce((v_after->>'id'), (v_before->>'id'),
              (v_after->>'project_id'), (v_before->>'project_id'))::uuid,   -- budgets/targets have no `id`
     v_before, v_after);

  return coalesce(new, old);
end;
$$;

revoke execute on function app.tg_audit_row() from public;

-- ---------------------------------------------------------------------------
-- Immutability guard: audit_log rows can never be updated or deleted,
-- even by service_role. (docs/DATABASE_SCHEMA.md §7.12 layer 3)
-- ---------------------------------------------------------------------------
create or replace function app.tg_audit_immutable()
returns trigger language plpgsql as $$
begin
  raise exception 'orchestr:audit_immutable:audit_log is append-only' using errcode = 'P0001';
end;
$$;

create trigger audit_log_immutable
  before update or delete on public.audit_log
  for each row execute function app.tg_audit_immutable();

revoke insert, update, delete on public.audit_log from authenticated, anon;

-- ---------------------------------------------------------------------------
-- Attach the audit trigger to every audited table (docs/DATABASE_SCHEMA.md §8.5)
-- ---------------------------------------------------------------------------
create trigger audit after insert or update or delete on public.users
  for each row execute function app.tg_audit_row();
create trigger audit after insert or update or delete on public.projects
  for each row execute function app.tg_audit_row();
create trigger audit after insert or update or delete on public.project_members
  for each row execute function app.tg_audit_row();
create trigger audit after insert or update or delete on public.invitations
  for each row execute function app.tg_audit_row();
create trigger audit after insert or update or delete on public.commitments
  for each row execute function app.tg_audit_row();
create trigger audit after insert or update or delete on public.commitment_participants
  for each row execute function app.tg_audit_row();
create trigger audit after insert or update or delete on public.cost_shares
  for each row execute function app.tg_audit_row();
create trigger audit after insert or update or delete on public.payments
  for each row execute function app.tg_audit_row();
create trigger audit after insert or update or delete on public.tasks
  for each row execute function app.tg_audit_row();
create trigger audit after insert or update or delete on public.milestones
  for each row execute function app.tg_audit_row();
create trigger audit after insert or update or delete on public.budgets
  for each row execute function app.tg_audit_row();
create trigger audit after insert or update or delete on public.budget_category_targets
  for each row execute function app.tg_audit_row();
create trigger audit after insert or update or delete on public.finding_dismissals
  for each row execute function app.tg_audit_row();

-- ---------------------------------------------------------------------------
-- auth.users -> public.users mirror (docs/DATABASE_SCHEMA.md §4.1 "Populated by")
-- Skips gracefully when called outside a user context (seed / service_role).
-- ---------------------------------------------------------------------------
create or replace function app.tg_handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text;
  v_tz   text;
  v_cur  text;
begin
  v_name := btrim(coalesce(new.raw_user_meta_data->>'display_name', ''));
  if v_name = '' then
    v_name := split_part(new.email, '@', 1);
  end if;
  v_name := left(v_name, 80);

  v_tz  := coalesce(new.raw_user_meta_data->>'timezone', 'UTC');
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = v_tz) then
    v_tz := 'UTC';
  end if;

  v_cur := upper(coalesce(new.raw_user_meta_data->>'default_currency', 'GBP'));
  if not exists (select 1 from public.currencies where code = v_cur) then
    v_cur := 'GBP';
  end if;

  insert into public.users (id, email, display_name, timezone, default_currency)
  values (new.id, lower(new.email), v_name, v_tz, v_cur)
  on conflict (id) do nothing;

  return new;
end;
$$;

revoke execute on function app.tg_handle_new_user() from public;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function app.tg_handle_new_user();

-- Keep email in sync if it changes in auth.users
create or replace function app.tg_sync_user_email()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.email is distinct from old.email then
    update public.users set email = lower(new.email) where id = new.id;
  end if;
  return new;
end;
$$;
revoke execute on function app.tg_sync_user_email() from public;

create trigger on_auth_user_email_updated
  after update of email on auth.users
  for each row execute function app.tg_sync_user_email();
