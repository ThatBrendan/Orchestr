# Backend Implementation

**Status:** Implemented as migrations — **not yet applied/verified** (no Docker / local Postgres in this environment; you chose "write only, you run it").
**Date:** 2026-09-04
**Implements:** [`DOMAIN_MODEL`](./DOMAIN_MODEL.md) · [`BUSINESS_RULES`](./BUSINESS_RULES.md) · [`TECHNICAL_ARCHITECTURE`](./TECHNICAL_ARCHITECTURE.md) · [`DATABASE_SCHEMA`](./DATABASE_SCHEMA.md) · [`SECURITY_RLS`](./SECURITY_RLS.md)

---

## 1. What was built

```
supabase/
├─ config.toml                         # api.schemas = ["public"] (app schema NOT exposed)
├─ migrations/
│  ├─ 20260904120000_core_schema_enums_helpers.sql   # schemas, extensions, enums, currencies, generic trigger fns
│  ├─ 20260904120100_tables.sql                       # 15 tables + generic trigger attachments
│  ├─ 20260904120150_security_helpers.sql             # SECURITY DEFINER membership helpers + tg_enforce_project_writable (need the tables)
│  ├─ 20260904120200_audit_and_auth.sql
│  ├─ 20260904120300_domain_triggers.sql
│  ├─ 20260904120400_views.sql
│  ├─ 20260904120500_functions_rpcs.sql
│  ├─ 20260904120600_rls_policies.sql
│  └─ 20260904120700_storage.sql
├─ seed.sql                            # Barcelona + Wedding fixtures (prototype port)
├─ functions/
│  ├─ _shared/cors.ts
│  └─ invitations-send/index.ts        # the one MVP Edge Function
└─ tests/
   ├─ 01_schema_and_rls_enabled.sql
   ├─ 02_isolation_and_roles.sql
   ├─ 03_financials.sql
   └─ 04_fk_constraints_deletion_invitations_audit.sql
```

### 1.1 Enums (15) — `20260904120000`
`project_status, member_role, member_status, invitation_status, commitment_kind, commitment_status, payment_type, payment_direction, payment_status, task_status, cost_share_basis, rsvp_status, finding_dismissal_state, audit_action, audit_source` — exactly as [DATABASE_SCHEMA §2]. `project_profile` is added later by `20260909100000_project_profiles.sql` as an additive presentation preset.

### 1.2 Tables (15) — `20260904120100` (+ `currencies` in `…120000`)
`currencies, users, projects, project_members, invitations, commitments, commitment_participants, cost_shares, payments, tasks, milestones, budgets, budget_category_targets, finding_dismissals, audit_log`.
Every column, PK, FK, unique constraint, CHECK, and index from [DATABASE_SCHEMA §4] is present, including:
- **Composite FKs on denormalised `project_id`** for cross-project integrity (`fk_commitment_owner`, `fk_participant_member`, `fk_payment_commitment`, `fk_task_commitment`, …) targeting `project_members(project_id, id)` / `commitments(project_id, id)` (both carry the required `UNIQUE (project_id, id)`).
- **Partial unique indexes** for soft-delete-aware uniqueness: `uq_member_user`, `uq_member_email_active`, `uq_invitation_pending`, `uq_finding_dismissal` (`NULLS NOT DISTINCT`).
- **Money** as `bigint` minor units, `CHECK (>= 0)` / `> 0`; currency is `projects.currency` for the whole project.

### 1.3 Derived — **no tables** (as required)
Budget actuals, timeline, health findings, per-member balances, progress %, outstanding, per-commitment payment progress are all **views or functions**:
| Object | Kind | Purpose |
|--------|------|---------|
| `public.v_commitment_financials` | view (security_invoker) | effective cost, gross/net paid, outstanding, `payment_progress` |
| `public.v_project_financials` | view | total cost, committed spend, gross paid / refunded / **net actual spend** (history-preserving), outstanding, scheduled outstanding, remaining budget, projected/settled variance, `progress_pct` |
| `public.v_budget_category_actuals` | view | per-`kind` target vs actual vs variance |
| `public.v_member_balances` | view | owed / contributed / balance, default equal split + `cost_shares` overrides, deterministic rounding |
| `public.v_timeline_events` | view | UNION ALL of the 7 sources ([BUSINESS_RULES TML-1]) |
| `public.v_member_directory` | view (**definer**, column-whitelisted) | co-member name + avatar without a broad `users` policy |
| `public.v_my_projects` | view | dashboard/list: project + role + profile/module visibility + financials summary + health status + next event |
| `app._health_findings(uuid)` | function (invoker) | the 17 deterministic rules HLT-1…HLT-17 |
| `public.get_project_health(uuid)` | RPC (invoker) | membership check + dismissal join |
| `public.get_project_health_summary(uuid)` | RPC (invoker) | rollup: `needs_attention` / `at_risk` / `healthy` + counts |

Activity Type phase note: `commitments.activity_type` now suppresses booking-reference health findings for non-booking activities. The remaining commitment health rules still use the original MVP status semantics (`idea`, `researching`, `confirmed`, `booked`, `completed`, `cancelled`) and should be revisited in the later profile-aware Health phase.

Project Notes phase note: `projects.notes` is a nullable plain-text field with a 10,000-character check. It uses the existing organizer-only project update policy, plus a narrow trigger preventing note edits while a project is archived.

Dynamic Overview + profile-aware Health phase note: `public.v_project_overview` is the backend-owned summary for profile-specific Overview cards. `app._health_findings` now gates booking-reference findings to Booking activities, missing-cost findings to Booking/Purchase activities, budget findings to projects where Budget is visible, and tight-connection findings to event-like activities in event-like profiles. HLT-18 adds a deterministic overdue dated-activity warning.

Recurring Activities/Tasks phase note: `20260909140000_recurring_activities_tasks.sql` adds structured recurrence columns to `commitments` and `tasks`, plus `commitment_occurrences` / `task_occurrences` exception tables. `app.recurrence_dates()` generates weekly, fortnightly, and monthly dates inside bounded ranges; monthly recurrence clamps to the target month's last valid day. Project/global timeline services now call bounded RPCs (`get_project_timeline_events`, `get_my_timeline_events`) so recurring occurrences reach Timeline and Calendar without duplicating future Activity rows. `get_project_health` suppresses the series-level overdue finding for recurring commitments and adds per-occurrence overdue findings that resolve when that occurrence is completed or skipped.

### 1.4 Functions & triggers — `…120000`, `…120150`, `…120200`, `…120300`, `…120500`
- **Generic triggers** (`…120000`, table-independent): `tg_set_updated_at`, `tg_block_immutable_columns` (project_id/created_at/created_by), `tg_validate_timezone`, `tg_lowercase_email`, `finding_is_dismissible`.
- **Table-dependent triggers** (`…120150`): `tg_enforce_project_writable` (archived read-only). (`…120300`): `tg_set_created_by` (+ participant/dismissal actor variants), and the domain triggers below. (`…120200`): `tg_audit_row`, `tg_audit_immutable`, `tg_handle_new_user`.
- **`SECURITY DEFINER` helpers** (`app`, `search_path = ''`) — `is_member`, `has_role`, `is_organizer`, `current_member_id`, `is_writable_project` in **`…120150`** (they read `public.project_members` / `public.projects`); `finding_is_dismissible` in `…120000`; `storage_project` in `…120700`.
- **Auth bridge:** `tg_handle_new_user` (+ `tg_sync_user_email`) on `auth.users`.
- **Circular-dependency break:** `tg_after_project_insert_create_member` (AFTER INSERT on `projects`, creates founding organizer, back-fills `created_by`; skips when `auth.uid()` is null).
- **State machines:** `tg_project_status_transition`, `tg_commitment_status_transition`, `tg_payment_status_transition`, `tg_task_status_transition`, `tg_member_status_transition`.
- **Governance:** `tg_last_organizer_guard`, `tg_member_update_guard` (self-service limited to `display_name` + leaving; `user_id` linkage blocked outside `accept_invitation`), `tg_currency_immutable`.
- **Integrity predicates:** `tg_commitment_owner_role_check`, `tg_task_assignee_role_check`, `tg_participant_member_active_check`, `tg_cost_share_basis_consistency` (deferred constraint trigger), `tg_payment_no_create_on_cancelled`, `tg_payment_soft_delete_guard`, `tg_payment_paid_on_not_future`, `tg_dismissal_not_blocker`.
- **Cascades:** `tg_commitment_cancel_cascade` (scheduled payments → cancelled; milestone link nulled; child tasks soft-deleted on delete), `tg_project_soft_delete_cascade` (+ restore branch), `tg_commitment_activates_project`, `tg_member_activates_project`.
- **RPCs (`public`, PostgREST-exposed):** `accept_invitation(text)`, `transfer_and_leave(uuid, uuid)`, `get_invitation(text)`, `get_project_health(uuid)`, `get_project_health_summary(uuid)`.

### 1.5 RLS — `20260904120600`
- `ENABLE` + `FORCE ROW LEVEL SECURITY` on all 15 tables.
- `REVOKE ALL … FROM anon, authenticated`, then minimal `GRANT`s, then the concrete policies from [SECURITY_RLS §5]. `anon` gets `SELECT` on `currencies` only.
- Every policy is the recommended body from [SECURITY_RLS §5], verbatim where possible.

### 1.6 Storage — `20260904120700`
Buckets `avatars` (public), `project-media` (private), `attachments` (private, FUTURE). `storage.objects` policies keyed by `app.storage_project(name)` (fails **closed** to `NULL` on a malformed path segment).

### 1.7 Edge Function — `functions/invitations-send`
The only MVP function. Authorizes the caller as an organizer with a **caller-scoped** client, then creates the (service-role-only) invitation row + best-effort email + audit row. Invitation **acceptance** is the DB RPC, not this function.

### 1.8 Seed
`seed.sql` recreates the prototype: `james@example.com` (organizer) + Mike/Sarah/Chris (members) + Tom/Ed (name-only) on **Barcelona Stag Weekend** with 5 commitments, participants, payments (deposits paid, balances scheduled), a £5,000 budget with category targets, 2 tasks, 1 milestone; plus **Sarah & John's Wedding** (Sarah also organizes) with a £12,000 budget and one researching commitment; plus one pending invitation. Password for all seeded users: `password123`.

---

## 2. Deviations from the specification

| # | Deviation | Why | Impact |
|---|-----------|-----|--------|
| **D1** | Added column **`payments.ever_paid boolean not null default false`**, latched `true` by the payment status trigger (and insert latch), never cleared. `tg_payment_soft_delete_guard` keys off `ever_paid`. | [DATABASE_SCHEMA §4.8] states "a payment that has **ever** been `paid` cannot be soft-deleted … tracked by `paid_on IS NOT NULL`". But `paid → scheduled` (allowed by [PAY-20]) clears `paid_on`, re-opening the soft-delete loophole. A latched flag is the minimal reliable mechanism to deliver the guarantee the spec already states. | One extra boolean column. No domain-model or product change. Financial-history preservation ([BUSINESS_RULES §8] amendment, [SECURITY_RLS R2]) is now actually enforced. |
| **D2** | RLS helper functions in schema **`app`** check *membership only* — they do **not** test `projects.deleted_at`. Deleted-project invisibility is delivered by (a) `deleted_at is null` in every policy and (b) the soft-delete cascade also soft-deleting `project_members`. | With the helper checking `projects.deleted_at`, an organizer's own `UPDATE projects SET deleted_at = now()` fails its own `WITH CHECK` (which re-evaluates `is_organizer` against the row it just marked deleted). | Behaviour identical to spec: a soft-deleted project and all its children are invisible to every non-service role ([BUSINESS_RULES PRJ-23]). Verified by test 04. |
| **D3** | Added `subject_type = 'budget_category'` to the `finding_dismissals` CHECK; `category_over_target` findings use a synthesised `subject_id = md5(project||kind)`. | [BUSINESS_RULES HLT-10] is per-category; the original subject-type list ([DATABASE_SCHEMA §4.13]) had no value that let each category be dismissed independently. | Larger CHECK list. `subject_id` was already documented as *not* an FK. |
| **D4** | `tg_member_update_guard` / `tg_last_organizer_guard` / cascade triggers short-circuit when `pg_trigger_depth() > 1`; `accept_invitation` sets a transaction-local GUC `app.bypass_member_guard` that `tg_member_update_guard` honours. | Nested trigger effects (project soft-delete cascading to members; `accept_invitation` claiming a name-only row) would otherwise trip governance guards meant for direct user edits. | Documented mechanism ([DATABASE_SCHEMA §7.10] already uses `pg_trigger_depth`). Direct user writes are unaffected. |
| **D5** | Edge Function `invitations-send` authorizes via a **caller-scoped `project_members` read** rather than calling `app.is_organizer` (which is not PostgREST-exposed). | `app` schema is deliberately unexposed ([SECURITY_RLS §4]); the Edge Function can't `rpc()` into it. | None — same check, RLS still applies to the read. |
| **D6** | `budgets`/`budget_category_targets` / `milestones` / `commitment_participants` / `cost_shares` / `finding_dismissals` use a single `FOR ALL` write policy + a separate `FOR SELECT` read policy (rather than four policies each). | Concise; PostgreSQL ORs permissive policies, so SELECT resolves to the broader `is_member` predicate and writes to the narrower one. | Identical effective access to the [SECURITY_RLS §9] matrix. |
| **D7** | `currencies` seeded with ~25 common ISO-4217 codes, not all ~180. | MVP; the table is additive. | Add rows in a later migration as needed. |
| **D8** | The audit trigger stores **full** `before`/`after` row images (minus nothing). | [DATABASE_SCHEMA §10 item 4] left column-trimming as an open item. | Larger `audit_log` rows. Trim later if needed; no behavioural impact. |

**No deviation touches the domain model, business rules, or any product decision.** D1 and D2 are the two that materially change SQL from the letter of `DATABASE_SCHEMA.md`; both are the *smallest* change that makes a stated guarantee actually hold, and both are called out here per the "STOP and document" instruction. Neither warranted halting the whole implementation.

> The migration **dependency-ordering fix** (moving six functions into `20260904120150_security_helpers.sql`) is **not** a deviation — no object definition changed, only the file it lives in. See [§7](#7-implementation-order-fix--migration-dependency-ordering-2026-09-04).

---

## 3. Architectural problems found → resolved

Two issues surfaced during implementation that would have made a documented guarantee fail. Per instruction, the problem and the minimal fix:

### 3.1 Financial-history loophole (→ D1)
**Problem:** `DATABASE_SCHEMA §4.8` says a payment that was ever paid can't be soft-deleted, *tracked by `paid_on IS NOT NULL`*. `PAY-20` allows `paid → scheduled`, which the `chk_payment_paid_on` constraint forces to clear `paid_on`. So: pay → un-pay → soft-delete = paid money erased from history, defeating `§8`'s amended financial-history rule.
**Smallest fix:** a latched `ever_paid` flag (D1). No transition rules changed; no product decision reopened.

### 3.2 Self-soft-delete vs. `WITH CHECK` re-evaluation (→ D2)
**Problem:** if `app.is_organizer()` checks `projects.deleted_at IS NULL`, then `UPDATE projects SET deleted_at = now()` by an organizer passes `USING` (old row) but fails `WITH CHECK` (new row is now "deleted", so `is_organizer` returns false). Organizers could never delete their own projects.
**Smallest fix:** helpers check membership only; the soft-delete cascade also soft-deletes membership rows, so `is_member` naturally returns false afterwards and `deleted_at IS NULL` in policies covers the project row itself (D2). PRJ-23 still fully holds.

---

## 4. How to apply

Requires Docker (for `supabase start`) or a linked Supabase project.

```bash
# local
supabase start                     # boots Postgres + Auth + Storage + Studio
supabase db reset                  # applies every migration in order, then seed.sql
supabase functions serve invitations-send   # optional: run the Edge Function locally

# staging / prod (per TECHNICAL_ARCHITECTURE §22)
supabase link --project-ref <ref>
supabase db push                   # applies pending migrations
supabase functions deploy invitations-send
supabase secrets set EMAIL_PROVIDER_API_KEY=... EMAIL_FROM=... APP_URL=...
```

Migrations are **ordered and idempotent-safe to apply once**; they are plain forward migrations (no down-migrations, per [TECHNICAL_ARCHITECTURE §22.2]).

---

## 5. How to verify

```bash
supabase test db          # runs supabase/tests/*.sql via pgTAP
```

The suite maps to the requested verification points:

| Verification requirement | Covered by | What it asserts |
|--------------------------|-----------|-----------------|
| **Migrations apply cleanly** | `supabase db reset` exit 0 | all 8 migrations + seed apply without error |
| **RLS works** | `01` (RLS enabled+forced on all tables), `02` | deny-by-default; policies enforce |
| **Users cannot access other projects** | `02` (D: P2-only; E: no memberships; anon) | cross-project SELECT → 0 rows; cross-project INSERT → `42501`; cross-project `owner_member_id` → `23503` (test `04`) |
| **Project owners have correct access** | `02` (A organizer) | rename project ✓, set budget ✓, cannot demote last organizer (`P0001`) |
| **Project members have correct access** | `02` (B member, C viewer) | member: create/edit commitments ✓, budget ✗, self-promote ✗; viewer: read ✓, write ✗ |
| **Foreign keys work** | `04` | cross-project owner/payment FK violations (`23503` / FK error) |
| **Constraints work** | `04` | `ends_at >= starts_at` (`23514`), `amount_minor > 0` (`23514`), non-blank name (`23514`), bad timezone (`P0001`), currency lock (`P0001`) |
| **Financial calculations are correct** | `03` | `v_project_financials` (total/committed/gross-paid/outstanding/scheduled/remaining/settled/progress), `v_commitment_financials.payment_progress`, `v_member_balances` — all vs hand-computed values, **including a paid payment on a cancelled commitment surviving in `gross_paid`** |
| **Deletion behaviour is correct** | `04` | paid payment cannot be soft-deleted (`P0001`); commitment soft-delete → scheduled payments cancelled, paid preserved, child tasks soft-deleted, milestone link nulled; project soft-delete → invisible even to its organizer |
| **Invitations** | `04` | no client INSERT (`42501`); wrong-email accept (`P0001`); valid accept returns project_id; idempotent; joins at invited role |
| **Audit integrity** | `04` | `audit_log` UPDATE/DELETE rejected (`P0001`) even as `postgres` |

> Test files build their own fixtures inside a rolled-back transaction (`supabase test db` does not load `seed.sql`), and impersonate users by setting `role` + `request.jwt.claims` so `auth.uid()` / `auth.email()` resolve.

---

## 6. Known limitations / assumptions (verify on first run)

1. **`postgres` has `BYPASSRLS`.** The SECURITY DEFINER helper pattern + `FORCE RLS` relies on this (true on Supabase). If a helper errors with "infinite recursion detected in policy", this assumption failed for your instance.
2. **Trigger on `auth.users`.** `on_auth_user_created` uses the standard Supabase pattern; requires the migration role to be permitted to `CREATE TRIGGER` on `auth.users` (true on Supabase).
3. **`auth.identities` seed shape.** `provider_id` + `identity_data` columns are for current GoTrue; adjust if your local Supabase image is older.
4. **`security_invoker` views** require PostgreSQL 15+ (config pins `major_version = 17`).
5. **`v_my_projects` calls the health summary per project** — fine at realistic per-user counts; [DATABASE_SCHEMA §8.3] describes the cache mitigation if needed.
6. **pgTAP** must be installable (`create extension pgtap`) — the test files do this; `supabase test db` provides it.
7. **The Edge Function's email provider** call is a Resend-style placeholder — swap for your ESP. Without `EMAIL_PROVIDER_API_KEY` it returns the invite link in the response for local testing.
8. **Not yet built (correctly out of scope):** every FUTURE item in the five source docs — notifications, AI, geocoding, iCal, attachments table, supplier/place entities, settlement, RSVP UI, real-time, multi-currency, self-serve project restore, scheduled health evaluation.

---

## 7. Implementation-order fix — migration dependency ordering (2026-09-04)

**Not an architectural deviation.** No table, column, constraint, RLS policy, helper behaviour, domain rule, or security property changed. Only *which migration file* six functions are created in.

### 7.1 The failure
`supabase db push` failed on the first migration:

```
ERROR: relation "public.project_members" does not exist (SQLSTATE 42P01)
```

`20260904120000_core_schema_enums_helpers.sql` defined five **`language sql`** membership helpers (`app.is_member`, `has_role`, `is_organizer`, `current_member_id`, `is_writable_project`). SQL functions have their body **parsed and name-resolved at `CREATE` time**, so referencing `public.project_members` / `public.projects` — created only in `20260904120100_tables.sql` — aborts the migration. (`plpgsql` functions defer name resolution, which is why the `plpgsql` trigger functions in the same file did not fault.)

### 7.2 The fix
1. **New migration `20260904120150_security_helpers.sql`** (runs after `…120100_tables.sql`, before `…120200`).
2. Six functions **moved verbatim** from `…120000` into `…120150`:
   | Function | Language | References | Why it had to move |
   |----------|----------|-----------|--------------------|
   | `app.is_member(uuid)` | sql | `public.project_members` | SQL body validated at CREATE → the actual `42P01` |
   | `app.has_role(uuid, member_role[])` | sql | `public.project_members` | same |
   | `app.is_organizer(uuid)` | sql | `app.has_role` | same (transitive) |
   | `app.current_member_id(uuid)` | sql | `public.project_members` | same |
   | `app.is_writable_project(uuid)` | sql | `public.projects` | same |
   | `app.tg_enforce_project_writable()` | plpgsql | `public.projects` | would not fail at CREATE, but references an application table (instruction #3) — moved for correctness and colocated with the helpers |
3. Their `REVOKE EXECUTE … FROM public` / `GRANT EXECUTE … TO authenticated, service_role` block moved with them, unchanged.
4. `…120000` keeps: schemas, `pgcrypto`, the 15 enums, `currencies` + its seed rows + grant, the four table-independent generic trigger functions (`tg_set_updated_at`, `tg_block_immutable_columns`, `tg_validate_timezone`, `tg_lowercase_email`), `app.finding_is_dismissible` (no table reference) + its grant, and `GRANT USAGE ON SCHEMA app`.
5. **Approved security properties preserved exactly** on every moved helper: `SECURITY DEFINER`, `STABLE`, `SET search_path = ''`, fully-qualified relation names, no dynamic SQL, `REVOKE EXECUTE FROM PUBLIC`, `EXECUTE` granted only to `authenticated` + `service_role`. `app.tg_enforce_project_writable` also kept its `SECURITY DEFINER` + `search_path = ''` + `pg_trigger_depth()` guard.

### 7.3 Full forward-reference scan (all 9 migrations)
Every `create function` / `view` / `trigger` / `policy` / FK / RPC was checked against the object it references and the migration that creates that object. Rule applied: **SQL functions, views, triggers, policies, and FK constraints resolve their dependencies at `CREATE` time; `plpgsql` function *bodies* do not** (only their argument/return *types* must pre-exist).

| Migration | Depends on | Provided by | OK? |
|-----------|-----------|-------------|-----|
| `…120100` tables — FKs, enum columns, generic trigger attachments | enums, `currencies`, `auth.users`, `tg_set_updated_at` / `tg_block_immutable_columns` / `tg_validate_timezone` / `tg_lowercase_email` | `…120000` | ✅ (no reference to the moved helpers) |
| `…120150` helpers — `is_member` etc., `tg_enforce_project_writable` | `public.project_members`, `public.projects`, `public.member_role`, `public.project_status` | `…120000` (types), `…120100` (tables) | ✅ (this migration is the fix) |
| `…120200` audit + auth — `tg_audit_row` (plpgsql) calls `app.current_member_id`; triggers attach to 13 tables + `auth.users` | tables, `app.current_member_id` | `…120100`, `…120150` | ✅ (plpgsql-deferred **and** `120150 < 120200`) |
| `…120300` domain triggers — 11 `enforce_writable` **`create trigger`** statements | `app.tg_enforce_project_writable()` **(must exist at CREATE)** | `…120150` | ✅ (`120150 < 120300`) |
| `…120300` — every other `create trigger` | its trigger function defined earlier **in the same file** | `…120300` | ✅ |
| `…120300` — `not_blocker` trigger → `tg_dismissal_not_blocker` → `app.finding_is_dismissible` | `app.finding_is_dismissible` | `…120000` | ✅ |
| `…120400` views — `v_member_directory` references `app.is_member` **(view validated at CREATE)** | `app.is_member` | `…120150` | ✅ (`120150 < 120400`) |
| `…120400` — other views reference only tables + earlier views in the same file | `…120100`, same file | — | ✅ |
| `…120500` — `format_money` (sql) → `public.currencies`; `get_invitation` (sql) → 4 tables; `get_project_health_summary` (sql) → `public.get_project_health` (same file, defined above); `v_my_projects` (view) → `get_project_health_summary` + `v_project_financials` + `v_timeline_events` | `…120000`, `…120100`, `…120400`, same file (ordered) | — | ✅ |
| `…120500` — `_health_findings` / `get_project_health` / `accept_invitation` / `transfer_and_leave` (all plpgsql) | tables, views, `app.is_member` / `is_organizer` | `…120100`, `…120150`, `…120400` | ✅ (deferred + ordered) |
| `…120600` RLS — `do $$ alter table … enable rls` on 15 tables; every policy expression references `app.is_member` / `has_role` / `is_organizer` / `current_member_id` / `is_writable_project` / `finding_is_dismissible` **(policy expressions validated at CREATE)** | 15 tables; the 6 helper functions | `…120100`; `…120150` + `…120000` | ✅ (`120150 < 120600`) |
| `…120600` — trailing view `GRANT`s | `v_*` views | `…120400`, `…120500` | ✅ |
| `…120700` storage — `app.storage_project` (sql, no table ref); policies reference `app.is_member` / `has_role` / `is_writable_project` / `storage_project` | helpers; own function (defined above in file) | `…120150`; same file | ✅ |

**Result: no forward-reference problem exists anywhere except the one fixed here.** Within-file ordering was also verified (e.g. `has_role` before `is_organizer` in `…120150`; `get_project_health` before `get_project_health_summary` and `v_my_projects` in `…120500`; every trigger function before its `create trigger`).

### 7.4 Final migration execution order
```
20260904120000_core_schema_enums_helpers.sql   schemas · pgcrypto · 15 enums · currencies(+seed) · 4 generic trigger fns · finding_is_dismissible · grants
20260904120100_tables.sql                       15 tables · PK/FK/unique/CHECK/indexes · generic trigger attachments
20260904120150_security_helpers.sql             tg_enforce_project_writable · is_member · has_role · is_organizer · current_member_id · is_writable_project (+ grants)   ← NEW
20260904120200_audit_and_auth.sql               tg_audit_row · tg_audit_immutable · audit triggers · auth.users → public.users bridge
20260904120300_domain_triggers.sql              ~30 domain trigger fns + attachments (incl. 11 enforce_writable triggers)
20260904120400_views.sql                        v_commitment_financials · v_project_financials · v_budget_category_actuals · v_member_balances · v_timeline_events · v_member_directory
20260904120500_functions_rpcs.sql               format_money · _health_findings · get_project_health(_summary) · get_invitation · accept_invitation · transfer_and_leave · v_my_projects
20260904120600_rls_policies.sql                 ENABLE + FORCE RLS · GRANTs · all policies · view GRANTs
20260904120700_storage.sql                      buckets · storage_project · storage.objects policies
```

### 7.5 Migration history / re-run
Migration `20260904120000` aborted **before** creating any object it uniquely owned that a re-run would collide on — it uses `create schema if not exists`, `create extension if not exists`, and `create or replace function`; only the `create type` / `create table currencies` statements are non-idempotent, and those run *before* the line that failed, inside the same transaction, so they rolled back. Supabase records a migration as applied only on success, so `20260904120000` should **not** appear in `supabase_migrations.schema_migrations`.

**Before the next `db push`, confirm:**
```bash
supabase migration list          # 20260904120000 must NOT show as applied on remote
```
- If it is **absent** (expected): just `supabase db push` — all nine migrations apply in order.
- If it somehow shows as **applied** (e.g. a partial-commit edge case): `supabase migration repair --status reverted 20260904120000`, then `supabase db push`.

No corrective/compensating production migration is included, per instruction #8 — the fix is a normal edit to not-yet-applied migrations.

### 7.6 Does this change the approved architecture?
**No.** Same tables, columns, constraints, indexes, enums, triggers, views, RPCs, RLS policies, helper bodies, and helper security properties. The only change is that six functions are defined one migration file later so that the tables they read already exist.

---

## 8. RAISE-formatting fix in `20260904120300_domain_triggers.sql` (2026-09-04)

**Not an architecture/behaviour change.** One invalid PL/pgSQL `RAISE` format string.

### 8.1 The failure
```
ERROR: too many parameters specified for RAISE (SQLSTATE 42601)
```
`app.tg_cost_share_basis_consistency()` had `(%%)` (two escaped literal percent signs → **zero** substitution placeholders) but supplied **two** arguments:
```sql
raise exception 'orchestr:cost_share_overflow:fixed shares (%%) exceed the commitment cost (%%)', v_fixed_total, v_cost
```

### 8.2 The fix
`%%` → `%` so each supplied argument has one placeholder (message meaning unchanged — the parentheses now wrap the interpolated value instead of a literal `%`):
```sql
raise exception 'orchestr:cost_share_overflow:fixed shares (%) exceed the commitment cost (%)',
  v_fixed_total, v_cost
  using errcode = 'P0001';
```
Error code (`P0001`), the `orchestr:cost_share_overflow:` code prefix, the trigger's validation logic, and the deferred constraint-trigger definition are untouched.

### 8.3 Full static scan of every `RAISE` in all 9 migrations
34 `RAISE EXCEPTION` statements (no `RAISE WARNING/NOTICE/INFO/LOG/DEBUG` anywhere). Audited each: message-string placeholder count vs. supplied-argument count.

| Pattern | Count | Placeholders / args | Verdict |
|---------|-------|---------------------|---------|
| Literal message, no args (`… using errcode = 'P0001'`) | 27 | 0 / 0 | ✅ |
| `'…:project % -> %', old.status, new.status` (project/commitment/payment/task/member status transitions) | 5 | 2 / 2 | ✅ |
| `'…:bad_timezone:% …', coalesce(new.timezone,'<null>')` | 1 | 1 / 1 | ✅ |
| `'…:cost_share_overflow:… (%) … (%)', v_fixed_total, v_cost` | 1 | 2 / 2 | ✅ (fixed here) |

- **No other `%%`** exists in any migration. The only other `%` sequences are `format('… public.%I …', t)` in `20260904120600` (a valid `%I` spec with its one argument) and `~ '^[A-Z]{3}$'` / regex/`::` casts (not format strings).
- **No too-few-parameter** RAISE (no message has an unmatched `%`).
- The word "Raise" also appears inside a *data string* — the HLT-9 resolution text `'Raise the budget, cut costs, or cancel commitments'` in `_health_findings` — which is not a `RAISE` statement and needs no placeholder.

### 8.4 Other syntax inspection of `20260904120300`
- `$$` delimiters balanced (25 pairs); every `create trigger` follows its function definition; `create constraint trigger … deferrable initially deferred … for each row` is valid; `after update of status, deleted_at` multi-column trigger spec is valid; DECLARE-block initializers referencing `NEW`/`OLD` are valid in trigger functions; `tg_op`, `pg_trigger_depth()`, and the 2-arg `current_setting(…, true)` calls are all correct.
- One cosmetic note (**not changed**, no functional impact, and outside the "no message changes" boundary): line ~456 `tg_payment_soft_delete_guard` has a UTF-8 em-dash (`—`) inside its RAISE message string. Valid in a PostgreSQL UTF-8 string literal; left as-is.

### 8.5 Does this change the approved architecture?
**No.** One format string corrected (`%%` → `%`). No schema, no trigger behaviour, no validation logic, no error code, no message wording changed.
