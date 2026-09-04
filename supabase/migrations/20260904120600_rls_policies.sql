-- ============================================================================
-- 20260904120600_rls_policies
-- Row Level Security: enable + FORCE on every table, minimal GRANTs, and the
-- concrete policies from docs/SECURITY_RLS.md §5.
--
-- Principals: anon (nothing), authenticated (+ a project_members fact),
-- organizer / member / viewer resolved per-row via app.* helpers.
-- service_role bypasses all of this and must self-authorise (Edge Functions).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Enable + FORCE RLS everywhere
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'currencies','users','projects','project_members','invitations','commitments',
    'commitment_participants','cost_shares','payments','tasks','milestones','budgets',
    'budget_category_targets','finding_dismissals','audit_log'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force  row level security', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Table privileges (policies constrain further)
-- ---------------------------------------------------------------------------
revoke all on all tables in schema public from anon, authenticated;

grant select on public.currencies to anon, authenticated;
grant select, update on public.users to authenticated;
grant select, insert, update on public.projects to authenticated;
grant select, insert, update on public.project_members to authenticated;
grant select, update, delete on public.invitations to authenticated;   -- INSERT: Edge Function only
grant select, insert, update on public.commitments to authenticated;
grant select, insert, update, delete on public.commitment_participants to authenticated;
grant select, insert, update, delete on public.cost_shares to authenticated;
grant select, insert, update on public.payments to authenticated;
grant select, insert, update on public.tasks to authenticated;
grant select, insert, update, delete on public.milestones to authenticated;
grant select, insert, update, delete on public.budgets to authenticated;
grant select, insert, update, delete on public.budget_category_targets to authenticated;
grant select, insert, update, delete on public.finding_dismissals to authenticated;
grant select on public.audit_log to authenticated;

-- ===========================================================================
-- currencies  (§5.14)
-- ===========================================================================
create policy currencies_read on public.currencies for select to anon, authenticated using (true);

-- ===========================================================================
-- users  (§5.1)
-- ===========================================================================
create policy users_select_self on public.users
  for select to authenticated using (id = (select auth.uid()));
create policy users_update_self on public.users
  for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));
-- INSERT: none (app.tg_handle_new_user only).  DELETE: none.

-- ===========================================================================
-- projects  (§5.2)
-- ===========================================================================
create policy projects_select_member on public.projects
  for select to authenticated using (app.is_member(id) and deleted_at is null);
create policy projects_insert_authed on public.projects
  for insert to authenticated
  with check ((select auth.uid()) is not null and status = 'draft'
              and deleted_at is null and archived_at is null);
-- USING checks the pre-image (not yet deleted); WITH CHECK does NOT re-check
-- deleted_at so an organizer can set it. Restore is service_role only.
create policy projects_update_organizer on public.projects
  for update to authenticated
  using (app.is_organizer(id) and deleted_at is null)
  with check (app.is_organizer(id));
-- DELETE: none (purge = service_role).

-- ===========================================================================
-- project_members  (§5.3)
-- ===========================================================================
create policy members_select on public.project_members
  for select to authenticated
  using (user_id = (select auth.uid()) or app.is_member(project_id));

create policy members_insert_organizer on public.project_members
  for insert to authenticated
  with check (
    app.is_organizer(project_id)
    and user_id is null
    and role in ('member','viewer')
    and status = 'active'
    and app.is_writable_project(project_id)
  );

create policy members_update on public.project_members
  for update to authenticated
  using (app.is_organizer(project_id) or user_id = (select auth.uid()))
  with check (app.is_organizer(project_id) or user_id = (select auth.uid()));
-- Column-level intent (self may change only display_name / leave) is enforced by
-- app.tg_member_update_guard. Last-organizer + transitions by their own triggers.

-- DELETE: none (removal = status='removed').

-- ===========================================================================
-- invitations  (§5.4)
-- ===========================================================================
create policy invitations_select_organizer on public.invitations
  for select to authenticated using (app.is_organizer(project_id));
create policy invitations_update_organizer on public.invitations
  for update to authenticated using (app.is_organizer(project_id)) with check (app.is_organizer(project_id));
create policy invitations_delete_organizer on public.invitations
  for delete to authenticated using (app.is_organizer(project_id));
-- INSERT: none for authenticated. Created by the `invitations-send` Edge Function (service_role),
--         which verifies the caller is an organizer first. Acceptance = public.accept_invitation().

-- ===========================================================================
-- commitments  (§5.5)  — Locations are the embedded location_* columns.
-- ===========================================================================
create policy commitments_select on public.commitments
  for select to authenticated using (app.is_member(project_id) and deleted_at is null);

create policy commitments_insert on public.commitments
  for insert to authenticated
  with check (
    app.has_role(project_id, array['organizer','member']::public.member_role[])
    and app.is_writable_project(project_id)
    and status in ('idea','researching')
    and deleted_at is null
  );

create policy commitments_update on public.commitments
  for update to authenticated
  using (
    app.has_role(project_id, array['organizer','member']::public.member_role[])
    and deleted_at is null
  )
  with check (
    app.has_role(project_id, array['organizer','member']::public.member_role[])
    and (
      deleted_at is null                                   -- ordinary edit: any member
      or app.is_organizer(project_id)                      -- soft-delete: organizer / creator / owner (MEM-15a)
      or created_by = app.current_member_id(project_id)
      or owner_member_id = app.current_member_id(project_id)
    )
  );
-- DELETE: none (hard delete = purge).

-- ===========================================================================
-- commitment_participants  (§5.6)
-- ===========================================================================
create policy participants_select on public.commitment_participants
  for select to authenticated using (app.is_member(project_id));
create policy participants_write on public.commitment_participants
  for all to authenticated
  using (app.has_role(project_id, array['organizer','member']::public.member_role[]))
  with check (app.has_role(project_id, array['organizer','member']::public.member_role[])
             and app.is_writable_project(project_id));

-- ===========================================================================
-- cost_shares  (§5.7)
-- ===========================================================================
create policy cost_shares_select on public.cost_shares
  for select to authenticated using (app.is_member(project_id));
create policy cost_shares_write on public.cost_shares
  for all to authenticated
  using (app.has_role(project_id, array['organizer','member']::public.member_role[]))
  with check (app.has_role(project_id, array['organizer','member']::public.member_role[])
             and app.is_writable_project(project_id));

-- ===========================================================================
-- payments  (§5.8)
-- ===========================================================================
create policy payments_select on public.payments
  for select to authenticated using (app.is_member(project_id) and deleted_at is null);

create policy payments_insert on public.payments
  for insert to authenticated
  with check (
    app.has_role(project_id, array['organizer','member']::public.member_role[])
    and app.is_writable_project(project_id)
    and amount_minor > 0
    and deleted_at is null
  );

create policy payments_update on public.payments
  for update to authenticated
  using (app.has_role(project_id, array['organizer','member']::public.member_role[]) and deleted_at is null)
  with check (
    app.has_role(project_id, array['organizer','member']::public.member_role[])
    and (
      deleted_at is null
      or app.is_organizer(project_id)
      or created_by = app.current_member_id(project_id)
      or paid_by_member_id = app.current_member_id(project_id)
    )
  );
-- DELETE: none. Paid payments cannot be soft-deleted (app.tg_payment_soft_delete_guard).

-- ===========================================================================
-- tasks  (§5.9)
-- ===========================================================================
create policy tasks_select on public.tasks
  for select to authenticated using (app.is_member(project_id) and deleted_at is null);

create policy tasks_insert on public.tasks
  for insert to authenticated
  with check (
    app.has_role(project_id, array['organizer','member']::public.member_role[])
    and app.is_writable_project(project_id)
    and deleted_at is null
  );

create policy tasks_update on public.tasks
  for update to authenticated
  using (app.has_role(project_id, array['organizer','member']::public.member_role[]) and deleted_at is null)
  with check (
    app.has_role(project_id, array['organizer','member']::public.member_role[])
    and (
      deleted_at is null
      or app.is_organizer(project_id)
      or created_by = app.current_member_id(project_id)
      or assignee_member_id = app.current_member_id(project_id)
    )
  );
-- DELETE: none.

-- ===========================================================================
-- milestones  (§5.10)  — MVP ships the SHOULD (members may create)
-- ===========================================================================
create policy milestones_select on public.milestones
  for select to authenticated using (app.is_member(project_id));
create policy milestones_write on public.milestones
  for all to authenticated
  using (app.has_role(project_id, array['organizer','member']::public.member_role[]))
  with check (app.has_role(project_id, array['organizer','member']::public.member_role[])
             and app.is_writable_project(project_id));

-- ===========================================================================
-- budgets / budget_category_targets  (§5.11)  — organizer only
-- ===========================================================================
create policy budgets_select on public.budgets
  for select to authenticated using (app.is_member(project_id));
create policy budgets_write on public.budgets
  for all to authenticated
  using (app.is_organizer(project_id))
  with check (app.is_organizer(project_id) and app.is_writable_project(project_id));

create policy budget_targets_select on public.budget_category_targets
  for select to authenticated using (app.is_member(project_id));
create policy budget_targets_write on public.budget_category_targets
  for all to authenticated
  using (app.is_organizer(project_id))
  with check (app.is_organizer(project_id) and app.is_writable_project(project_id));

-- ===========================================================================
-- finding_dismissals  (§5.12)
-- ===========================================================================
create policy dismissals_select on public.finding_dismissals
  for select to authenticated using (app.is_member(project_id));
create policy dismissals_insert on public.finding_dismissals
  for insert to authenticated
  with check (
    app.has_role(project_id, array['organizer','member']::public.member_role[])
    and app.is_writable_project(project_id)
    and app.finding_is_dismissible(code)
  );
create policy dismissals_update on public.finding_dismissals
  for update to authenticated
  using (app.has_role(project_id, array['organizer','member']::public.member_role[]))
  with check (app.has_role(project_id, array['organizer','member']::public.member_role[])
             and app.finding_is_dismissible(code));
create policy dismissals_delete on public.finding_dismissals
  for delete to authenticated
  using (app.has_role(project_id, array['organizer','member']::public.member_role[]));

-- ===========================================================================
-- audit_log  (§5.13)  — organizer read; no client writes (also REVOKE + trigger)
-- ===========================================================================
create policy audit_select_organizer on public.audit_log
  for select to authenticated
  using (project_id is not null and app.is_organizer(project_id));

-- ---------------------------------------------------------------------------
-- Re-affirm view SELECT grants (the blanket REVOKE above also hit views).
-- Views are security_invoker, so base-table RLS still constrains every row.
-- ---------------------------------------------------------------------------
grant select on
  public.v_commitment_financials, public.v_project_financials, public.v_budget_category_actuals,
  public.v_member_balances, public.v_timeline_events, public.v_member_directory, public.v_my_projects
to authenticated;
