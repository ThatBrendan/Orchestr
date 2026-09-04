# Production Database Schema — Specification

**Status:** Draft for review
**Date:** 2026-09-04
**Target:** Supabase (PostgreSQL 15+)
**Source material:** [`docs/DOMAIN_MODEL.md`](./DOMAIN_MODEL.md), [`docs/BUSINESS_RULES.md`](./BUSINESS_RULES.md), [`docs/TECHNICAL_ARCHITECTURE.md`](./TECHNICAL_ARCHITECTURE.md)
**Non-goals:** no migration files, no DDL beyond illustrative fragments, no RLS policy bodies (defined in [`TECHNICAL_ARCHITECTURE §12`](./TECHNICAL_ARCHITECTURE.md#12-rls-strategy)).

This is the schema specification. Migrations are derived from it next.

---

## 1. Conventions

| Topic | Decision |
|-------|----------|
| **Schemas** | Application tables in `public`. Helper/security functions and RPCs in `app`. Generated types read `public` + `app`. |
| **Primary keys** | `id uuid PRIMARY KEY DEFAULT gen_random_uuid()` on every table except `currencies` (natural key), `budgets` (`project_id` is PK), and composite-PK join tables. |
| **Timestamps** | `created_at timestamptz NOT NULL DEFAULT now()` and `updated_at timestamptz NOT NULL DEFAULT now()` on every mutable table. `updated_at` maintained by trigger `app.tg_set_updated_at()` ([§8.1](#81-generic-triggers)). |
| **Actor stamping** | `created_by uuid` (→ `project_members.id`) on user-authored rows, set by trigger `app.tg_set_created_by()` from `auth.uid()` if not supplied. |
| **Soft delete** | `deleted_at timestamptz` on `projects`, `project_members`, `commitments`, `payments`, `tasks` ([BUSINESS_RULES GC‑2]). All other tables hard-delete. Every read path filters `deleted_at IS NULL`; every RLS SELECT policy and every view enforces it. |
| **Money** | `bigint` minor units, always `CHECK (>= 0)`. Currency is **not** stored per money column — it is `projects.currency` for the whole project ([BUSINESS_RULES PRJ‑16], removes VAL‑22 as a runtime concern). |
| **Text** | `text` (never `varchar(n)`); length limits enforced by `CHECK (char_length(btrim(x)) BETWEEN a AND b)`. |
| **Enums** | Native PostgreSQL `enum` where the value set is small, closed, and integrity-bearing ([§2](#2-enumerated-types)). Open/large sets (currency, timezone, kind-of-finding) are `text` + reference table or trigger validation. |
| **`project_id` denormalisation** | Every project-scoped child table carries `project_id uuid NOT NULL`, even when reachable through a parent. This is deliberate — it powers composite foreign keys for cross-project integrity ([§7.1](#71-cross-project-referential-integrity)) and lets RLS policies test membership without a join. Consistency is **guaranteed by composite FKs**, not left to the application. |
| **`ON UPDATE`** | All PKs are immutable UUIDs; every FK is `ON UPDATE NO ACTION` (the default). `project_id` on children is made immutable by trigger `app.tg_block_project_id_change()`. |
| **`ON DELETE`** | Hard `DELETE` occurs **only** during project purge ([BUSINESS_RULES PRJ‑22], post‑recovery‑window, [FUTURE]). Therefore every child FK is `ON DELETE CASCADE` and a purge is a single `DELETE FROM projects`. Day‑to‑day "deletion" is soft and handled by triggers. Exceptions noted per table. |
| **NULLS in unique constraints** | `UNIQUE NULLS NOT DISTINCT` (PG15) used where a nullable component must still be deduplicated (`finding_dismissals`). |

---

## 2. Enumerated types

Native enums — chosen because each set is closed, referenced in `CHECK`/transition logic, and benefits from type safety in generated TypeScript.

| Enum | Values | Used by |
|------|--------|---------|
| `project_status` | `draft`, `active`, `completed`, `archived` | `projects.status` |
| `member_role` | `organizer`, `member`, `viewer` | `project_members.role`, `invitations.role` |
| `member_status` | `invited`, `active`, `removed` | `project_members.status` |
| `invitation_status` | `pending`, `accepted`, `expired`, `revoked` | `invitations.status` |
| `commitment_kind` | `accommodation`, `transport`, `food`, `experience`, `services`, `other` | `commitments.kind`, `budget_category_targets.kind` |
| `commitment_status` | `idea`, `researching`, `confirmed`, `booked`, `completed`, `cancelled` | `commitments.status` |
| `payment_type` | `deposit`, `balance`, `installment`, `full`, `refund` | `payments.type` |
| `payment_direction` | `outgoing`, `incoming` | `payments.direction` |
| `payment_status` | `scheduled`, `paid`, `waived`, `cancelled` | `payments.status` — the **stored payment lifecycle**. Not to be confused with the *derived, unstored* per-commitment payment progress (`unpaid`/`deposit_paid`/`part_paid`/`paid_in_full`) computed in `app.v_commitment_financials` ([§5.4](#54-payment-status)). |
| `task_status` | `open`, `in_progress`, `done`, `cancelled` | `tasks.status` |
| `cost_share_basis` | `equal`, `weight`, `fixed` | `cost_shares.basis` |
| `rsvp_status` | `going`, `maybe`, `not_going`, `unknown` | `commitment_participants.rsvp` |
| `finding_dismissal_state` | `dismissed`, `snoozed` | `finding_dismissals.state` |
| `audit_action` | `create`, `update`, `soft_delete`, `restore`, `delete` | `audit_log.action` |
| `audit_source` | `app`, `rpc`, `edge`, `system` | `audit_log.source` |

**Not enums (deliberately):**
- **Currency** → `currencies` reference table ([§3](#3-reference-data)). ~180 rows, needs `minor_unit` metadata, membership changes over time.
- **Timezone** → `text` validated by trigger against `pg_timezone_names` ([§7.9](#79-timezone-validity)). Cannot be a `CHECK` because `pg_timezone_names` is not `IMMUTABLE`.
- **Health finding `code`** → plain `text` produced by `app.get_project_health()` ([§5.3](#53-health)). Findings are not stored, so no integrity need; new rules must not require a migration.

---

## 3. Reference data

### 3.1 `currencies`

- **Purpose:** ISO‑4217 currency metadata for correct minor-unit arithmetic, rounding ([BUSINESS_RULES BUD‑16]) and formatting.
- **Persistence:** static reference; seeded, rarely changed.

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| `code` | `text` | no | — | ISO‑4217 alpha‑3, uppercase. **PK.** `CHECK (code ~ '^[A-Z]{3}$')` |
| `name` | `text` | no | — | "Pound Sterling" |
| `minor_unit` | `smallint` | no | — | decimal digits (GBP=2, JPY=0, KWD=3). `CHECK (minor_unit BETWEEN 0 AND 4)` |
| `symbol` | `text` | yes | — | "£" (display hint only) |

- **PK:** `code`
- **FK in:** `projects.currency`, `users.default_currency`
- **Indexes:** PK only.
- **Delete behaviour:** `ON DELETE RESTRICT` from referencing tables (cannot remove a currency in use).
- **RLS:** readable by all `authenticated`; no writes from the app (seed/migration only).

---

## 4. Tables

### 4.1 `users`

- **Purpose:** application-side profile mirror of `auth.users`. The app never reads `auth.users` directly ([TECHNICAL_ARCHITECTURE §10]).
- **Represents:** an authenticated account ([DOMAIN_MODEL §5.1]).

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| `id` | `uuid` | no | — | **PK**, `REFERENCES auth.users(id) ON DELETE CASCADE` |
| `email` | `text` | no | — | mirrored from `auth.users`; kept in sync by trigger. `CHECK (position('@' in email) > 1)` |
| `display_name` | `text` | no | `''` then set | `CHECK (char_length(btrim(display_name)) BETWEEN 1 AND 80)` |
| `avatar_url` | `text` | yes | — | Storage path or external URL |
| `timezone` | `text` | no | `'UTC'` | IANA; validated by trigger ([§7.9](#79-timezone-validity)) |
| `default_currency` | `text` | no | `'GBP'` | `REFERENCES currencies(code) ON DELETE RESTRICT` |
| `notification_prefs` | `jsonb` | no | `'{"email":true,"push":false}'::jsonb` | shape validated by `CHECK (jsonb_typeof(notification_prefs) = 'object')`; detailed schema is app-side |
| `created_at` | `timestamptz` | no | `now()` | |
| `updated_at` | `timestamptz` | no | `now()` | trigger-maintained |

- **PK:** `id`
- **FKs:** `id → auth.users(id)` `ON DELETE CASCADE`; `default_currency → currencies(code)` `ON DELETE RESTRICT`
- **Unique:** `email` is unique in `auth.users`; a `UNIQUE (email)` here too for the invitation-claim lookup ([MEM‑3]).
- **Check:** as above.
- **Indexes:** PK; `UNIQUE (lower(email))`.
- **Triggers:** `tg_set_updated_at`, `tg_validate_timezone`, `tg_audit_row` (project_id NULL — global audit).
- **Populated by:** `app.tg_handle_new_user()` — `AFTER INSERT ON auth.users`, `SECURITY DEFINER` ([§8.2](#82-security-definer-helpers--rpcs)).
- **Delete behaviour:** deleting the `auth.users` row cascades here; `project_members.user_id` is then `SET NULL` (member row survives as name-only history). Account deletion is blocked upstream if the user is a project's last organizer ([VAL‑39], enforced by [§7.6](#76-last-organizer-guarantee)).
- **RLS:** self read/update; a restricted column subset (`id, display_name, avatar_url`) is exposed to co-members via `app.v_member_directory`.

---

### 4.2 `projects`

- **Purpose:** top-level container, unit of collaboration, permissions, currency, and billing.
- **Represents:** [DOMAIN_MODEL §5.2].

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| `id` | `uuid` | no | `gen_random_uuid()` | **PK** |
| `name` | `text` | no | — | `CHECK (char_length(btrim(name)) BETWEEN 1 AND 120)` (VAL‑2) |
| `description` | `text` | yes | — | |
| `status` | `project_status` | no | `'draft'` | (PRJ‑5) |
| `starts_on` | `date` | yes | — | (PRJ‑15) |
| `ends_on` | `date` | yes | — | |
| `timezone` | `text` | no | — | IANA; trigger-validated. Defaults from creator app-side (PRJ‑4) |
| `currency` | `text` | no | — | `REFERENCES currencies(code) ON DELETE RESTRICT`. Immutable once money exists ([§7.5](#75-currency-immutability)) |
| `cover_theme` | `text` | yes | — | cosmetic (prototype `cover`) |
| `health_config` | `jsonb` | no | `'{}'::jsonb` | per-project threshold overrides ([HLT‑I]); keys: `inactive_days`, `due_soon_days`, `tight_connection_minutes`, `unconfirmed_near_days`, `on_budget_window_days`. Missing keys fall back to defaults in `app.get_project_health()`. `CHECK (jsonb_typeof(health_config) = 'object')` |
| `created_by` | `uuid` | yes | — | → `project_members.id` (the founding organizer); nullable because the member row is created *after* the project in the same transaction |
| `created_at` | `timestamptz` | no | `now()` | |
| `updated_at` | `timestamptz` | no | `now()` | |
| `archived_at` | `timestamptz` | yes | — | set with `status='archived'` (PRJ‑16) |
| `deleted_at` | `timestamptz` | yes | — | soft delete (PRJ‑20) |

- **PK:** `id`
- **FKs:** `currency → currencies(code)` `ON DELETE RESTRICT`. (`created_by` is **not** a DB FK — see [§7.2](#72-circular-dependency-projects--project_members).)
- **Unique:** none beyond PK.
- **Check:** `name` length; `chk_project_dates` `CHECK (starts_on IS NULL OR ends_on IS NULL OR starts_on <= ends_on)` (VAL‑1); `chk_archived_consistency` `CHECK ((status = 'archived') = (archived_at IS NOT NULL))`.
- **Indexes:** PK; `(status) WHERE deleted_at IS NULL`; `(created_by)`.
- **Triggers:** `tg_set_updated_at`, `tg_validate_timezone`, `tg_currency_immutable`, `tg_project_status_transition` ([§7.7](#77-status-transition-legality)), `tg_after_project_insert_create_member` ([§7.2](#72-circular-dependency-projects--project_members)), `tg_project_soft_delete_cascade` ([§7.4](#74-soft-delete-cascade)), `tg_audit_row`.
- **Delete behaviour:** soft by default (cascade in [§7.4](#74-soft-delete-cascade)). Hard `DELETE` (purge) cascades to all child tables.

---

### 4.3 `project_members`

- **Purpose:** the project-scoped identity. Owners, participants, payers, assignees, `created_by` all reference this table — never `users`, never free text ([DOMAIN_MODEL §5.3], [BUSINESS_RULES §2]).

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| `id` | `uuid` | no | `gen_random_uuid()` | **PK** |
| `project_id` | `uuid` | no | — | `REFERENCES projects(id) ON DELETE CASCADE` |
| `user_id` | `uuid` | yes | — | `REFERENCES users(id) ON DELETE SET NULL`. **NULL = name-only member** who cannot log in (MEM‑1) |
| `display_name` | `text` | no | — | `CHECK (char_length(btrim(display_name)) BETWEEN 1 AND 80)` (VAL‑5, MEM‑4) |
| `email` | `text` | yes | — | `CHECK (email IS NULL OR position('@' in email) > 1)` (VAL‑6). Used for invitation-claim matching; frozen at invite time |
| `role` | `member_role` | no | `'member'` | (MEM‑13) |
| `status` | `member_status` | no | `'active'` | (MEM‑1) |
| `invited_at` | `timestamptz` | yes | — | |
| `joined_at` | `timestamptz` | yes | `now()` | set when `status → active` |
| `removed_at` | `timestamptz` | yes | — | set when `status → removed` |
| `created_at` | `timestamptz` | no | `now()` | |
| `updated_at` | `timestamptz` | no | `now()` | |
| `deleted_at` | `timestamptz` | yes | — | soft delete (only via project purge/cascade; day-to-day removal uses `status='removed'`) |

- **PK:** `id`
- **FKs:** `project_id → projects(id)` `ON DELETE CASCADE`; `user_id → users(id)` `ON DELETE SET NULL`
- **Unique constraints (soft-delete-aware — [§7.3](#73-soft-delete-aware-uniqueness)):**
  - `uq_member_project_id` — `UNIQUE (project_id, id)` — **the composite-FK target** that makes every cross-project member reference declarative.
  - `uq_member_user` — `UNIQUE (project_id, user_id)` partial `WHERE user_id IS NOT NULL` — one membership per user per project, *including* `removed` rows so re-invite reactivates (MEM‑19, MEM‑2).
  - `uq_member_email_active` — `UNIQUE (project_id, lower(email))` partial `WHERE email IS NOT NULL AND status <> 'removed' AND deleted_at IS NULL` (VAL‑7).
- **Check:** name/email as above; `chk_member_status_dates` `CHECK ((status='removed') = (removed_at IS NOT NULL))`.
- **Indexes:** PK; the unique indexes above; `(user_id) WHERE user_id IS NOT NULL`; `(project_id, role) WHERE status='active' AND deleted_at IS NULL` (last-organizer check, permission checks).
- **Triggers:** `tg_set_updated_at`, `tg_block_project_id_change`, `tg_member_status_transition`, `tg_last_organizer_guard` (`BEFORE UPDATE OR DELETE` — [§7.6](#76-last-organizer-guarantee)), `tg_member_activates_project` ([§7.8](#78-draftactive-auto-transition)), `tg_enforce_project_writable` (blocks changes when project archived, except role/status paths that are part of un-archive — [§7.10](#710-archived-project-read-only)), `tg_audit_row`.
- **Delete behaviour:** never hard-deleted except by project purge. Removal = `status='removed'` (soft), which preserves every downstream reference (MEM‑17): commitment ownership stays (→ `orphaned_owner` finding), payments stay attributed, participant/cost-share rows stay.

---

### 4.4 `invitations`

- **Purpose:** a pending request to join a project ([DOMAIN_MODEL §5.4], [BUSINESS_RULES §2.2]).

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| `id` | `uuid` | no | `gen_random_uuid()` | **PK** |
| `project_id` | `uuid` | no | — | `REFERENCES projects(id) ON DELETE CASCADE` |
| `email` | `text` | no | — | `CHECK (position('@' in email) > 1)`; stored lowercased by trigger |
| `role` | `member_role` | no | `'member'` | `CHECK (role <> 'organizer')` (MEM‑6) |
| `status` | `invitation_status` | no | `'pending'` | |
| `token` | `text` | no | `encode(gen_random_bytes(24),'base64url')` (via trigger/default fn) | opaque; **`UNIQUE`** |
| `invited_by` | `uuid` | no | — | composite FK → `project_members` |
| `expires_at` | `timestamptz` | no | `now() + interval '14 days'` | (MEM‑9) |
| `created_at` | `timestamptz` | no | `now()` | |
| `updated_at` | `timestamptz` | no | `now()` | |
| `accepted_at` | `timestamptz` | yes | — | |
| `accepted_member_id` | `uuid` | yes | — | composite FK → `project_members`; set by `app.accept_invitation()` |

- **PK:** `id`
- **FKs:** `project_id → projects(id)` `ON DELETE CASCADE`; `(project_id, invited_by) → project_members(project_id, id)` `ON DELETE CASCADE`; `(project_id, accepted_member_id) → project_members(project_id, id)` `ON DELETE SET NULL` (MATCH SIMPLE — skipped while NULL).
- **Unique:**
  - `UNIQUE (token)`
  - `uq_invitation_pending` — `UNIQUE (project_id, lower(email))` partial `WHERE status = 'pending'` (MEM‑7).
- **Check:** `chk_invitation_accept` `CHECK ((status='accepted') = (accepted_at IS NOT NULL))`.
- **Indexes:** PK; `UNIQUE (token)`; `uq_invitation_pending`; `(project_id) WHERE status='pending'`.
- **Triggers:** `tg_set_updated_at`, `tg_lowercase_email`, `tg_enforce_project_writable`, `tg_audit_row`.
- **Delete behaviour:** hard-deletable by organizers (revoke can also just set `status='revoked'`; both allowed). Cascades on project purge.
- **Note:** the acceptance flow (validate token, claim/create member, set `user_id`, mark accepted, audit) is `app.accept_invitation()` — a `SECURITY DEFINER` RPC, because the invitee is not yet a member and RLS would block the writes ([TECHNICAL_ARCHITECTURE §9.2](./TECHNICAL_ARCHITECTURE.md#92-writes)).

---

### 4.5 `commitments`

- **Purpose:** the core unit of planning and execution — one owned, accountable line item ([DOMAIN_MODEL §5.5]). UI label "Activity".
- **Source of truth for:** a commitment's planned/agreed cost (used by every financial calculation — [§6](#6-financial-source-of-truth)).

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| `id` | `uuid` | no | `gen_random_uuid()` | **PK** |
| `project_id` | `uuid` | no | — | `REFERENCES projects(id) ON DELETE CASCADE` |
| `title` | `text` | no | — | `CHECK (char_length(btrim(title)) BETWEEN 1 AND 120)` (VAL‑9) |
| `kind` | `commitment_kind` | no | — | doubles as budget category (COM‑6) |
| `status` | `commitment_status` | no | `'researching'` | user-set lifecycle (COM‑3, COM‑15) |
| `owner_member_id` | `uuid` | yes | — | **the single ownership link** (COM‑22). NULL = "Unassigned" |
| `estimated_cost_minor` | `bigint` | yes | — | `CHECK (estimated_cost_minor IS NULL OR estimated_cost_minor >= 0)` (VAL‑11) |
| `confirmed_cost_minor` | `bigint` | yes | — | `CHECK (... >= 0)` |
| `starts_at` | `timestamptz` | yes | — | absolute instant (COM‑32) |
| `ends_at` | `timestamptz` | yes | — | |
| `is_all_day` | `boolean` | no | `false` | |
| `schedule_note` | `text` | yes | — | free text, never computed on (COM‑34) |
| `location_label` | `text` | yes | — | embedded value object (COM‑36) |
| `location_address` | `text` | yes | — | |
| `location_lat` | `numeric(9,6)` | yes | — | `CHECK (location_lat BETWEEN -90 AND 90)` |
| `location_lng` | `numeric(9,6)` | yes | — | `CHECK (location_lng BETWEEN -180 AND 180)` |
| `location_place_id` | `text` | yes | — | external ref, unused in MVP |
| `supplier_name` | `text` | yes | — | embedded booking value object (COM‑39) |
| `supplier_contact` | `text` | yes | — | |
| `booking_reference` | `text` | yes | — | |
| `booking_confirmed` | `boolean` | no | `false` | drives `missing_booking_reference` finding (COM‑41) |
| `notes` | `text` | yes | — | |
| `created_by` | `uuid` | yes | — | composite FK → `project_members` |
| `created_at` | `timestamptz` | no | `now()` | |
| `updated_at` | `timestamptz` | no | `now()` | **feeds HLT‑7 "inactive"** — modelling requirement |
| `deleted_at` | `timestamptz` | yes | — | soft delete (COM‑43) |

- **PK:** `id`
- **Unique:** `uq_commitment_project_id` — `UNIQUE (project_id, id)` — composite-FK target for `payments`, `commitment_participants`, `cost_shares`, `tasks`, `milestones`.
- **FKs:**
  - `project_id → projects(id)` `ON DELETE CASCADE`
  - `(project_id, owner_member_id) → project_members(project_id, id)` `ON DELETE CASCADE` (MATCH SIMPLE; not enforced while `owner_member_id` NULL) — guarantees the owner is a member **of the same project** ([§7.1](#71-cross-project-referential-integrity))
  - `(project_id, created_by) → project_members(project_id, id)` `ON DELETE SET NULL`
- **Check:** title length; cost non-negativity; `chk_commitment_time` `CHECK (starts_at IS NULL OR ends_at IS NULL OR ends_at >= starts_at)` (VAL‑10); lat/lng ranges.
- **Indexes:** PK; `uq_commitment_project_id`; `(project_id, status) WHERE deleted_at IS NULL`; `(owner_member_id) WHERE deleted_at IS NULL`; `(project_id, starts_at) WHERE deleted_at IS NULL AND status <> 'cancelled'` (timeline, conflict detection); `(project_id, kind) WHERE deleted_at IS NULL` (category actuals); `(project_id, updated_at) WHERE status IN ('idea','researching')` (inactivity rule).
- **Triggers:** `tg_set_updated_at`, `tg_set_created_by`, `tg_block_project_id_change`, `tg_commitment_status_transition` ([§7.7](#77-status-transition-legality)), `tg_commitment_owner_role_check` (owner role ∈ {organizer,member}, active — VAL‑12; the FK guarantees same-project, this adds the role/status predicate — [§7.1](#71-cross-project-referential-integrity)), `tg_commitment_activates_project` (PRJ‑10 — [§7.8](#78-draftactive-auto-transition)), `tg_commitment_cancel_cascade` (on `status→cancelled` or soft delete: cancel **scheduled** payments only; null linked milestones' `commitment_id`; soft-delete child tasks — [§7.4](#74-soft-delete-cascade)), `tg_enforce_project_writable`, `tg_audit_row`.
- **Delete behaviour:** soft. Cancelling (`status='cancelled'`) excludes it from operational calculations but **retains all payment rows for financial history** ([§7.8b](#78b-financial-history-preservation)).

---

### 4.6 `commitment_participants`

- **Purpose:** the explicit set of members involved in a commitment ([DOMAIN_MODEL §5.6]). Replaces the prototype's magic `participants: 12`.

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| `id` | `uuid` | no | `gen_random_uuid()` | **PK** |
| `project_id` | `uuid` | no | — | for composite FKs |
| `commitment_id` | `uuid` | no | — | |
| `member_id` | `uuid` | no | — | |
| `rsvp` | `rsvp_status` | no | `'unknown'` | column present from MVP; RSVP UI is [FUTURE] (COM‑29) |
| `added_by` | `uuid` | yes | — | composite FK → `project_members` |
| `created_at` | `timestamptz` | no | `now()` | |
| `updated_at` | `timestamptz` | no | `now()` | |

- **PK:** `id`
- **FKs:**
  - `(project_id, commitment_id) → commitments(project_id, id)` `ON DELETE CASCADE`
  - `(project_id, member_id) → project_members(project_id, id)` `ON DELETE CASCADE`
  - `(project_id, added_by) → project_members(project_id, id)` `ON DELETE SET NULL`
  - `project_id → projects(id)` `ON DELETE CASCADE`
- **Unique:** `uq_participant` — `UNIQUE (commitment_id, member_id)` (VAL‑13). No soft-delete concern (hard-delete on removal).
- **Check:** none beyond FKs/enum.
- **Indexes:** PK; `uq_participant`; `(member_id)`; `(commitment_id)`.
- **Triggers:** `tg_set_updated_at`, `tg_block_project_id_change`, `tg_participant_member_active_check` (member `status <> 'removed'` at insert — VAL‑13), `tg_enforce_project_writable`, `tg_audit_row`.
- **Delete behaviour:** hard-delete on removal. Cascades on commitment/member/project purge. **No cost-share recompute trigger needed** — equal splits are derived from the *current* participant set at read time ([§5.5](#55-per-member-balances)), so removing a participant automatically re-balances.

---

### 4.7 `cost_shares`

- **Purpose:** store **explicit, non-default** cost allocation overrides for a commitment ([DOMAIN_MODEL §5.7], [BUSINESS_RULES BUD‑11]). **Absence of rows for a commitment ⇒ equal split among current participants** (computed in `app.v_member_balances`).

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| `id` | `uuid` | no | `gen_random_uuid()` | **PK** |
| `project_id` | `uuid` | no | — | for composite FKs |
| `commitment_id` | `uuid` | no | — | |
| `member_id` | `uuid` | no | — | |
| `basis` | `cost_share_basis` | no | — | `equal` \| `weight` \| `fixed` |
| `weight` | `numeric(12,4)` | yes | — | required iff `basis='weight'` |
| `fixed_amount_minor` | `bigint` | yes | — | required iff `basis='fixed'` |
| `created_at` | `timestamptz` | no | `now()` | |
| `updated_at` | `timestamptz` | no | `now()` | |

- **PK:** `id`
- **FKs:** `(project_id, commitment_id) → commitments(project_id, id)` `ON DELETE CASCADE`; `(project_id, member_id) → project_members(project_id, id)` `ON DELETE CASCADE`; `project_id → projects(id)` `ON DELETE CASCADE`
- **Unique:** `uq_cost_share` — `UNIQUE (commitment_id, member_id)` (VAL‑14).
- **Check:** `chk_cost_share_basis` — `CHECK ((basis='weight' AND weight IS NOT NULL AND weight > 0 AND fixed_amount_minor IS NULL) OR (basis='fixed' AND fixed_amount_minor IS NOT NULL AND fixed_amount_minor >= 0 AND weight IS NULL) OR (basis='equal' AND weight IS NULL AND fixed_amount_minor IS NULL))` (VAL‑14).
- **Same-basis rule** (a commitment's shares must all use one `basis`, or a documented mix of `fixed` + one other) — **trigger** `tg_cost_share_basis_consistency` (cannot be a table CHECK; needs sibling rows). Rationale in [§7.11](#711-cost-share-basis-consistency).
- **Indexes:** PK; `uq_cost_share`; `(commitment_id)`; `(member_id)`.
- **Triggers:** `tg_set_updated_at`, `tg_block_project_id_change`, `tg_cost_share_basis_consistency`, `tg_enforce_project_writable`, `tg_audit_row`.
- **Delete behaviour:** hard-delete. Editing the split = `upsert` the set (replace semantics, app-side).

---

### 4.8 `payments`

- **Purpose:** one planned or actual movement of money for a commitment ([DOMAIN_MODEL §5.8]).
- **Source of truth for:** all cash-movement figures — gross paid, refunded, net actual spend, per-member contributions ([§6](#6-financial-source-of-truth)).

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| `id` | `uuid` | no | `gen_random_uuid()` | **PK** |
| `project_id` | `uuid` | no | — | for composite FKs |
| `commitment_id` | `uuid` | no | — | payments always belong to a commitment (PAY‑1) |
| `type` | `payment_type` | no | — | |
| `direction` | `payment_direction` | no | `'outgoing'` | `refund` defaulted to `incoming` app-side; `CHECK (type <> 'refund' OR direction = 'incoming')` |
| `status` | `payment_status` | no | `'scheduled'` | **stored lifecycle** (PAY‑4) |
| `amount_minor` | `bigint` | no | — | `CHECK (amount_minor > 0)` — strictly positive (VAL‑15) |
| `due_on` | `date` | yes | — | may be past (PAY‑5); overdue is derived, not stored (PAY‑17) |
| `paid_on` | `date` | yes | — | required iff `status='paid'` |
| `paid_by_member_id` | `uuid` | yes | — | composite FK → `project_members` |
| `method` | `text` | yes | — | free text in MVP |
| `reference` | `text` | yes | — | |
| `notes` | `text` | yes | — | |
| `created_by` | `uuid` | yes | — | composite FK → `project_members` |
| `created_at` | `timestamptz` | no | `now()` | |
| `updated_at` | `timestamptz` | no | `now()` | |
| `deleted_at` | `timestamptz` | yes | — | soft delete — **restricted** (see below) |

- **PK:** `id`
- **FKs:**
  - `(project_id, commitment_id) → commitments(project_id, id)` `ON DELETE CASCADE`
  - `(project_id, paid_by_member_id) → project_members(project_id, id)` `ON DELETE SET NULL`
  - `(project_id, created_by) → project_members(project_id, id)` `ON DELETE SET NULL`
  - `project_id → projects(id)` `ON DELETE CASCADE`
- **Unique:** none.
- **Check:** `amount_minor > 0`; `chk_payment_paid_on` `CHECK ((status='paid') = (paid_on IS NOT NULL))`; refund/direction check above.
- **Indexes:** PK; `(project_id, status) WHERE deleted_at IS NULL`; `(project_id, status, due_on) WHERE deleted_at IS NULL AND status='scheduled'` (overdue / due-soon findings, timeline); `(commitment_id) WHERE deleted_at IS NULL`; `(paid_by_member_id) WHERE status='paid' AND deleted_at IS NULL` (member contributions).
- **Triggers:** `tg_set_updated_at`, `tg_set_created_by`, `tg_block_project_id_change`, `tg_payment_status_transition` (PAY‑20 — [§7.7](#77-status-transition-legality)), `tg_payment_no_create_on_cancelled` (VAL‑17: reject INSERT when the commitment is `cancelled`/soft-deleted), `tg_payment_soft_delete_guard` (**financial-history preservation** — [§7.8b](#78b-financial-history-preservation)), `tg_payment_paid_on_not_future` (VAL‑16: `paid_on <= (today in project tz)`), `tg_enforce_project_writable`, `tg_audit_row`.
- **Delete behaviour:**
  - A `scheduled` payment may be soft-deleted (a mistaken entry).
  - A payment that **has ever been `paid`** may **not** be soft-deleted — it must be `cancelled` or `waived` (the row is retained). Enforced by `tg_payment_soft_delete_guard`.
  - Hard delete only on project purge (CASCADE).
  - Cancelling the parent *commitment* cancels **only `scheduled`** payments; `paid`/`waived` rows are untouched ([§7.4](#74-soft-delete-cascade), [§7.8b](#78b-financial-history-preservation)).

---

### 4.9 `tasks`

- **Purpose:** a small unit of work; lighter than a commitment; no cost/participants/booking ([DOMAIN_MODEL §5.9]).

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| `id` | `uuid` | no | `gen_random_uuid()` | **PK** |
| `project_id` | `uuid` | no | — | a task always belongs to a project (TSK‑2) |
| `commitment_id` | `uuid` | yes | — | optional parent (TSK‑11) |
| `title` | `text` | no | — | `CHECK (char_length(btrim(title)) BETWEEN 1 AND 120)` (VAL‑19) |
| `status` | `task_status` | no | `'open'` | (TSK‑3) |
| `assignee_member_id` | `uuid` | yes | — | composite FK → `project_members` |
| `due_on` | `date` | yes | — | may be past (TSK‑6) |
| `notes` | `text` | yes | — | |
| `completed_at` | `timestamptz` | yes | — | set on `status='done'`, cleared on reopen (TSK‑9) |
| `created_by` | `uuid` | yes | — | composite FK → `project_members` |
| `created_at` | `timestamptz` | no | `now()` | |
| `updated_at` | `timestamptz` | no | `now()` | |
| `deleted_at` | `timestamptz` | yes | — | soft delete (cascades from commitment — TSK‑13) |

- **PK:** `id`
- **FKs:**
  - `(project_id, commitment_id) → commitments(project_id, id)` `ON DELETE CASCADE` (MATCH SIMPLE; skipped while NULL) — same-project guarantee (VAL‑30, [§7.1](#71-cross-project-referential-integrity))
  - `(project_id, assignee_member_id) → project_members(project_id, id)` `ON DELETE SET NULL`
  - `(project_id, created_by) → project_members(project_id, id)` `ON DELETE SET NULL`
  - `project_id → projects(id)` `ON DELETE CASCADE`
- **Unique:** none.
- **Check:** title length; `chk_task_completed` `CHECK ((status='done') = (completed_at IS NOT NULL))` (TSK‑9).
- **Indexes:** PK; `(project_id, status) WHERE deleted_at IS NULL`; `(project_id, status, due_on) WHERE deleted_at IS NULL AND status IN ('open','in_progress')` (overdue findings, timeline); `(assignee_member_id) WHERE deleted_at IS NULL`; `(commitment_id) WHERE deleted_at IS NULL`.
- **Triggers:** `tg_set_updated_at`, `tg_set_created_by`, `tg_block_project_id_change`, `tg_task_status_transition`, `tg_task_assignee_role_check` (assignee role ∈ {organizer,member}, active — TSK‑4), `tg_enforce_project_writable`, `tg_audit_row`.
- **Delete behaviour:** soft. Cascades (soft) when the parent commitment is soft-deleted ([§7.4](#74-soft-delete-cascade)); restorable if the commitment is restored.

---

### 4.10 `milestones`

- **Purpose:** a thin, manual, user-pinned date marker not implied by any commitment/payment/task ([DOMAIN_MODEL §5.10]).

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| `id` | `uuid` | no | `gen_random_uuid()` | **PK** |
| `project_id` | `uuid` | no | — | (MIL‑2) |
| `commitment_id` | `uuid` | yes | — | optional link; **not** deleted with the commitment — link is nulled (COM‑44, MIL‑9) |
| `title` | `text` | no | — | `CHECK (char_length(btrim(title)) BETWEEN 1 AND 120)` (VAL‑20) |
| `on_date` | `date` | no | — | single date, no time (MIL‑7) |
| `notes` | `text` | yes | — | |
| `created_by` | `uuid` | yes | — | composite FK → `project_members` |
| `created_at` | `timestamptz` | no | `now()` | |
| `updated_at` | `timestamptz` | no | `now()` | |

- **PK:** `id`
- **FKs:**
  - `(project_id, commitment_id) → commitments(project_id, id)` `ON DELETE CASCADE` (purge only; MVP soft-delete nulls the link via `tg_commitment_cancel_cascade`)
  - `(project_id, created_by) → project_members(project_id, id)` `ON DELETE SET NULL`
  - `project_id → projects(id)` `ON DELETE CASCADE`
- **Unique:** none.
- **Check:** title length.
- **Indexes:** PK; `(project_id, on_date)`; `(commitment_id) WHERE commitment_id IS NOT NULL`.
- **Triggers:** `tg_set_updated_at`, `tg_set_created_by`, `tg_block_project_id_change`, `tg_enforce_project_writable`, `tg_audit_row`.
- **Delete behaviour:** hard-delete (no soft delete — MIL is not in the GC‑2 list). Cascades on project purge. When its linked commitment is soft-deleted, `commitment_id` is set NULL (the milestone is project-scoped, not commitment-scoped).
- **No completion state** in MVP (MIL‑4): `upcoming`/`passed` is derived from `on_date` vs today.

---

### 4.11 `budgets`

- **Purpose:** store the project's financial **plan** — the total target only ([DOMAIN_MODEL §5.11]). **No actuals.**

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| `project_id` | `uuid` | no | — | **PK** (1:1 with project) |
| `total_target_minor` | `bigint` | yes | — | `CHECK (total_target_minor IS NULL OR total_target_minor >= 0)` (VAL‑21). NULL = "no total set" |
| `created_at` | `timestamptz` | no | `now()` | |
| `updated_at` | `timestamptz` | no | `now()` | |

- **PK:** `project_id`
- **FKs:** `project_id → projects(id)` `ON DELETE CASCADE`
- **Unique:** PK enforces 1:1.
- **Check:** as above.
- **Indexes:** PK.
- **Triggers:** `tg_set_updated_at`, `tg_enforce_project_writable`, `tg_audit_row`.
- **Delete behaviour:** hard-delete allowed (removing the budget); category targets cascade. "Budget optional" (BUD‑1) — a project with no `budgets` row shows "no budget set".

---

### 4.12 `budget_category_targets`

- **Purpose:** optional per-`kind` budget target ([DOMAIN_MODEL §5.11], BUD‑2).

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| `project_id` | `uuid` | no | — | part of **PK** |
| `kind` | `commitment_kind` | no | — | part of **PK** — one row per kind (VAL‑21) |
| `amount_minor` | `bigint` | no | — | `CHECK (amount_minor >= 0)` |
| `created_at` | `timestamptz` | no | `now()` | |
| `updated_at` | `timestamptz` | no | `now()` | |

- **PK:** `(project_id, kind)`
- **FKs:** `project_id → budgets(project_id)` `ON DELETE CASCADE` (targets require a budget row)
- **Unique:** PK.
- **Check:** as above.
- **Indexes:** PK.
- **Triggers:** `tg_set_updated_at`, `tg_enforce_project_writable`, `tg_audit_row`.
- **Delete behaviour:** hard-delete; cascades from `budgets` and project purge.
- **Note:** sum of category targets need not equal `total_target_minor` (BUD‑3) — no cross-row constraint; the difference is surfaced in a view.

---

### 4.13 `finding_dismissals`

- **Purpose:** the **only** persisted health data — a user's decision to dismiss or snooze a specific finding ([BUSINESS_RULES HLT‑F], [DOMAIN_MODEL §7.3]). This is *user intent*, not derived data.

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| `id` | `uuid` | no | `gen_random_uuid()` | **PK** |
| `project_id` | `uuid` | no | — | `REFERENCES projects(id) ON DELETE CASCADE` |
| `code` | `text` | no | — | the finding rule code (e.g. `missing_owner`) — plain text, deliberately not an enum |
| `subject_type` | `text` | no | — | `CHECK (subject_type IN ('commitment','payment','task','milestone','project','commitment_pair'))` |
| `subject_id` | `uuid` | yes | — | NULL for project-level findings; a stable synthesised UUID for `commitment_pair` (ordered pair hash) |
| `state` | `finding_dismissal_state` | no | — | `dismissed` \| `snoozed` |
| `snoozed_until` | `date` | yes | — | required iff `state='snoozed'` |
| `actor_member_id` | `uuid` | yes | — | composite FK → `project_members` |
| `created_at` | `timestamptz` | no | `now()` | |
| `updated_at` | `timestamptz` | no | `now()` | |

- **PK:** `id`
- **FKs:** `project_id → projects(id)` `ON DELETE CASCADE`; `(project_id, actor_member_id) → project_members(project_id, id)` `ON DELETE SET NULL`. **`subject_id` is intentionally not an FK** — the subject can be any of several tables and findings are computed, not stored; a dangling dismissal is harmless (it simply never matches).
- **Unique:** `uq_finding_dismissal` — `UNIQUE NULLS NOT DISTINCT (project_id, code, subject_type, subject_id)` — enables `upsert` and prevents duplicates when `subject_id` is NULL.
- **Check:** `chk_dismissal_snooze` `CHECK ((state='snoozed') = (snoozed_until IS NOT NULL))`.
- **Indexes:** PK; `uq_finding_dismissal`; `(project_id)`.
- **Triggers:** `tg_set_updated_at`, `tg_dismissal_not_blocker` (**reject dismissal of a `blocker`-severity finding** — HLT‑F; the trigger consults the rule-severity map function `app.finding_is_dismissible(code)`), `tg_enforce_project_writable`, `tg_audit_row`.
- **Delete behaviour:** hard-delete (un-dismiss). Cascades on project purge.
- **Housekeeping:** a `snoozed` row with `snoozed_until < today` is simply ignored by `app.get_project_health()`; no cleanup job required for MVP.

---

### 4.14 `audit_log`

- **Purpose:** immutable, append-only history of every mutation to project data ([TECHNICAL_ARCHITECTURE §20]).

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| `id` | `uuid` | no | `gen_random_uuid()` | **PK** |
| `project_id` | `uuid` | yes | — | NULL for global rows (`users`). No FK — see below |
| `at` | `timestamptz` | no | `now()` | |
| `actor_user_id` | `uuid` | yes | — | `auth.uid()` at time of action; no FK (must survive account deletion) |
| `actor_member_id` | `uuid` | yes | — | resolved member id; no FK (must survive member purge) |
| `source` | `audit_source` | no | `'app'` | `app` \| `rpc` \| `edge` \| `system` |
| `action` | `audit_action` | no | — | `create` \| `update` \| `soft_delete` \| `restore` \| `delete` |
| `entity_type` | `text` | no | — | table name |
| `entity_id` | `uuid` | no | — | row id |
| `before` | `jsonb` | yes | — | row image pre-change (minus volatile/large columns), NULL on `create` |
| `after` | `jsonb` | yes | — | row image post-change, NULL on hard `delete` |
| `request_id` | `text` | yes | — | correlation id from Edge Functions / client |

- **PK:** `id`
- **FKs:** **none, by design.** Audit rows must outlive every entity they describe (deleted projects during the recovery window, purged members, deleted accounts). Integrity of `entity_type`/`entity_id` is not enforced because the referent may legitimately no longer exist.
- **Unique:** none.
- **Check:** `chk_audit_images` `CHECK (action <> 'create' OR before IS NULL)` and `CHECK (action <> 'delete' OR after IS NULL)`.
- **Indexes:** PK; `(project_id, at DESC)`; `(entity_type, entity_id, at DESC)`; `(actor_user_id, at DESC)`.
- **Immutability enforcement (three layers — [§7.12](#712-immutable-audit-history)):**
  1. **RLS:** SELECT policy for organizers of `project_id`; **no** INSERT/UPDATE/DELETE policy for any client role.
  2. **Privilege:** `REVOKE INSERT, UPDATE, DELETE ON audit_log FROM authenticated, anon;` — only the trigger's `SECURITY DEFINER` owner and service-role may write.
  3. **Trigger:** `tg_audit_immutable` `BEFORE UPDATE OR DELETE ON audit_log` → `RAISE EXCEPTION` unconditionally (defends against a compromised service-role path).
- **Written by:** `app.tg_audit_row()` (`AFTER INSERT/UPDATE/DELETE`, `SECURITY DEFINER`) on every audited table; and explicitly by RPCs / Edge Functions for privileged actions.
- **Delete behaviour:** never. Purged only when the project is hard-purged (and even then, retention is a documented [FUTURE] decision — the default is to keep audit rows for hard-deleted projects in a cold table).

---

## 5. What is NOT a table (derived data)

Per the explicit instruction and [BUSINESS_RULES GC‑7], the following are **computed, never stored**. Each has exactly one canonical definition, listed with its home.

### 5.1 Budget (actuals)
- **Not stored:** total cost, committed spend, gross paid, refunded, net actual spend, outstanding, remaining budget, projected/settled/per-category variance.
- **Stored inputs only:** `budgets.total_target_minor`, `budget_category_targets.amount_minor`.
- **Home:** view `app.v_project_financials` (project roll-up) + `app.v_budget_category_actuals` (per kind). Formulas: [BUSINESS_RULES §8], [§6](#6-financial-source-of-truth).
- **Why not a table:** the prototype stored these and they didn't reconcile with the underlying rows. A stored aggregate is a second source of truth by definition.

### 5.2 Timeline
- **Not stored:** any timeline/`upcoming` event list.
- **Home:** view `app.v_timeline_events` — `UNION ALL` of the seven sources in [BUSINESS_RULES TML‑1] (commitments, scheduled payments, paid payments, tasks, milestones, project start, project end).
- **Why not a table:** every event is a projection of a row that already exists; a table would need triggers on five other tables to stay correct.

### 5.3 Health
- **Not stored:** findings, `attentionCount`, project health status, `has_open_issues`.
- **Stored inputs only:** `finding_dismissals` (user intent), `projects.health_config` (thresholds).
- **Home:** set-returning function `app.get_project_health(p_project_id uuid)` + `app.get_project_health_summary(p_project_id uuid)` — [BUSINESS_RULES §9], [§9.2](#92-functions--rpcs).
- **Why a function, not a view:** it takes threshold parameters, evaluates ~17 rules with shared CTEs, and must re-check membership; a parameterised function is the right shape. It is `SECURITY INVOKER`.

### 5.4 Payment status (per commitment)
- **Not stored:** `unpaid` / `deposit_paid` / `part_paid` / `paid_in_full` ([BUSINESS_RULES PAY‑9]).
- **Stored:** the *payment row's own* `payments.status` (`scheduled`/`paid`/`waived`/`cancelled`) — that is user intent about one payment, not a derived roll-up.
- **Home:** column `payment_progress` in view `app.v_commitment_financials`, computed from the commitment's payment rows + `effective_cost`.
- **Why not stored:** it is a pure function of `payments` + cost; storing it means a trigger on `payments` maintaining a column on `commitments` — a redundant source of truth and a race condition.

### 5.5 Per-member balances
- **Not stored:** owed, contributed, balance ("Owes £70").
- **Stored inputs only:** `cost_shares` (explicit overrides), `commitment_participants` (for the default equal split), `payments.paid_by_member_id`.
- **Home:** view `app.v_member_balances` — [BUSINESS_RULES §8.3].
- **Why not a table:** changes whenever a participant, cost, payment, or share changes; only ever read, never edited.

### 5.6 Project progress %
- **Not stored:** the prototype's `projects.progress`.
- **Home:** column `progress_pct` in `app.v_project_financials`: `round(count(status IN ('confirmed','booked','completed')) / nullif(count(status <> 'cancelled'),0) * 100)` ([BUSINESS_RULES VAL‑49]). `0` when no commitments.

### 5.7 Outstanding
- **Not stored** at project or commitment level.
- **Home:** `app.v_project_financials.outstanding_minor` (cost basis, BUD‑7) and `app.v_commitment_financials.outstanding_minor` (per commitment, PAY‑12). Scheduled-outstanding (cash-flow, PAY‑14) is a separate column `scheduled_outstanding_minor`.

### 5.8 Derived "missing / unassigned" flags
- Prototype `missingOwner`, `missingBooking` booleans → **not stored**; they are `owner_member_id IS NULL` and `(booking_reference IS NULL OR NOT booking_confirmed)` evaluated in views / the health function.

---

## 6. Financial source of truth

There is exactly one authoritative input for each financial quantity. Every derived figure ([§5.1](#51-budget-actuals), [§5.5](#55-per-member-balances), [§5.7](#57-outstanding)) is a pure function of these:

| Quantity | Single source of truth |
|----------|------------------------|
| A commitment's planned/agreed price | `commitments.confirmed_cost_minor ?? commitments.estimated_cost_minor ?? 0` ("effective cost") |
| Which commitments count as "committed" | `commitments.status ∈ {confirmed, booked, completed}` and `deleted_at IS NULL` |
| Which commitments count as "total projected" | `commitments.status <> 'cancelled'` and `deleted_at IS NULL` |
| Money actually moved | `payments` rows with `status = 'paid'` and `deleted_at IS NULL` (`direction` distinguishes outgoing vs refund) |
| Money scheduled but not moved | `payments` rows with `status = 'scheduled'` and `deleted_at IS NULL` |
| Who paid | `payments.paid_by_member_id` |
| How a cost is split | `cost_shares` rows for the commitment, **or** (if none) equal split over `commitment_participants` |
| The budget plan | `budgets.total_target_minor`, `budget_category_targets.amount_minor` |
| Project currency & minor unit | `projects.currency` → `currencies.minor_unit` |

**Financial-history rule** ([BUSINESS_RULES GC‑8 amended, §8]): operational figures (committed, outstanding, remaining, progress, per-member *owed*) exclude `cancelled` commitments and their payments. **Financial-history figures** (gross paid, refunded, net actual spend, per-member *contributed*) include `status='paid'` payment rows **regardless of whether their commitment was later cancelled**. Both are computed from the same `payments` table by different `WHERE` clauses — no separate storage. Enforced structurally by [§7.8b](#78b-financial-history-preservation) (paid payments are never removed).

---

## 7. Constraint enforcement mechanisms

For every rule PostgreSQL cannot express as a plain FK or single-row `CHECK`, the mechanism and its justification:

### 7.1 Cross-project referential integrity

**Requirement:** an owner / participant / payer / assignee / parent-commitment referenced by a project-scoped row must belong to the **same project**.

**Mechanism: composite foreign keys on a denormalised `project_id`.**
- Every project-scoped child carries `project_id NOT NULL`.
- `project_members` and `commitments` each have `UNIQUE (project_id, id)`.
- Every member/commitment reference is a **composite FK** `(project_id, <ref_id>) → <parent>(project_id, id)`, `MATCH SIMPLE` (so a NULL `<ref_id>` skips the check).
- Because the child's own `project_id` is fixed (immutable, [§7.13](#713-project_id-immutability)) and the FK forces the referent to share it, a cross-project reference is **structurally impossible** — no trigger required.

**Why not a trigger:** a trigger would be a race-prone runtime check; the composite FK is declarative, index-backed, and enforced under concurrency by the constraint system.

**Residual predicates that still need a trigger** (the FK guarantees *same project*, not *right role/status*):
- Commitment owner must be `role ∈ {organizer,member}` and `status='active'` → `tg_commitment_owner_role_check` (VAL‑12).
- Task assignee, same → `tg_task_assignee_role_check` (TSK‑4).
- Participant member must not be `removed` at insert → `tg_participant_member_active_check` (VAL‑13).
These are `BEFORE INSERT OR UPDATE` row triggers raising `ERRCODE 'P0001'` with an `orchestr:<code>` message.

### 7.2 Circular dependency: `projects` ↔ `project_members`

**Potential cycle:** a project needs a founding organizer; a member needs a project.

**Resolution:** `projects` has **no FK to `project_members`**. `projects.created_by` is a bare `uuid` (documented as "→ project_members.id" but not constrained). The founding membership is created by `tg_after_project_insert_create_member` (`AFTER INSERT ON projects`, `SECURITY DEFINER`): it inserts the `project_members` row (`role='organizer'`, `status='active'`, `user_id = auth.uid()`) and back-fills `projects.created_by`. Both rows exist by commit; there is no FK cycle to break, and no `DEFERRABLE` constraint needed.

This is the schema-level pay-off of [DOMAIN_MODEL PRJ‑6] ("no single project-owner field").

### 7.3 Soft-delete-aware uniqueness

**Requirement:** uniqueness that must ignore or include soft-deleted / status-removed rows depending on the rule.

**Mechanism: partial unique indexes** with a `WHERE` clause encoding the exact scope:
| Constraint | Index predicate | Rule |
|------------|-----------------|------|
| one membership per user per project (incl. removed, for reactivation) | `UNIQUE (project_id, user_id) WHERE user_id IS NOT NULL` | MEM‑2, MEM‑19 |
| one active member per email per project | `UNIQUE (project_id, lower(email)) WHERE email IS NOT NULL AND status <> 'removed' AND deleted_at IS NULL` | VAL‑7 |
| one pending invitation per email per project | `UNIQUE (project_id, lower(email)) WHERE status = 'pending'` | MEM‑7 |
| one finding-dismissal per (code, subject) | `UNIQUE NULLS NOT DISTINCT (project_id, code, subject_type, subject_id)` | HLT‑F |

**Why partial indexes:** a plain `UNIQUE` can't express "only among non-removed rows"; partial indexes are the standard PostgreSQL idiom and remain index-backed and concurrency-safe.

### 7.4 Soft-delete cascade

**Requirement:** soft-deleting a project or commitment must soft-delete the right descendants ([PRJ‑21], [COM‑43]); commitment cancellation has bespoke effects ([COM‑18], [COM‑44]).

**Mechanism: `AFTER UPDATE` triggers** that fire when `deleted_at` transitions `NULL → NOT NULL`, or `status → 'cancelled'`:
- `tg_project_soft_delete_cascade` — sets `deleted_at = now()` on all child rows of the project (members, commitments, payments, tasks) and hard-deletes/soft-marks the non-soft-delete children as appropriate; sets `status='archived'`-like invisibility. (Full project *purge* is the separate hard-`DELETE` CASCADE path.)
- `tg_commitment_cancel_cascade` — on `status → 'cancelled'` **or** `deleted_at` set:
  - `UPDATE payments SET status='cancelled' WHERE commitment_id = OLD.id AND status = 'scheduled'` — **scheduled only** ([§7.8b](#78b-financial-history-preservation));
  - `UPDATE milestones SET commitment_id = NULL WHERE commitment_id = OLD.id` (COM‑44 — milestone survives);
  - `UPDATE tasks SET deleted_at = now() WHERE commitment_id = OLD.id AND deleted_at IS NULL` (TSK‑13, on soft delete; on mere cancel, tasks are left per COM‑18).

**Why triggers, not FK `ON DELETE`:** FK cascade only fires on hard `DELETE`. Soft delete is an `UPDATE`, invisible to FK actions, so the cascade must be a trigger.

### 7.5 Currency immutability

**Requirement:** `projects.currency` cannot change once any commitment or payment exists, including soft-deleted ([PRJ‑16a], VAL‑3).

**Mechanism:** `tg_currency_immutable` `BEFORE UPDATE ON projects` — if `NEW.currency <> OLD.currency` and `EXISTS (SELECT 1 FROM commitments WHERE project_id = OLD.id) OR EXISTS (SELECT 1 FROM payments WHERE project_id = OLD.id)` (no `deleted_at` filter — history counts) → `RAISE EXCEPTION 'orchestr:currency_locked:...'`.

**Why a trigger:** the condition spans other tables; not expressible as a `CHECK`.

### 7.6 Last-organizer guarantee

**Requirement:** a project always has ≥ 1 `active` `organizer`; no demotion/removal/leave/soft-delete may violate this ([PRJ‑7], MEM‑16, MEM‑20, VAL‑39).

**Mechanism:** `tg_last_organizer_guard` `BEFORE UPDATE OR DELETE ON project_members` (and consulted by `tg_project_soft_delete_cascade` for account deletion). After computing the post-image, if the affected row *was* an active organizer and `(SELECT count(*) FROM project_members WHERE project_id = OLD.project_id AND role='organizer' AND status='active' AND deleted_at IS NULL AND id <> OLD.id) = 0` → `RAISE EXCEPTION 'orchestr:last_organizer:...'`.
- Runs `SECURITY DEFINER` (must count rows it might not see under RLS) with `SET search_path=''`.
- The `(project_id, role) WHERE status='active'` partial index makes the count cheap.
- Atomic promote-then-leave is offered as RPC `app.transfer_and_leave()` so the client never has to sequence two writes past this guard.

**Why a trigger + RPC:** a cross-row invariant with a "escape hatch" operation that must be atomic.

### 7.7 Status transition legality

**Requirement:** only defined transitions are allowed for `projects.status`, `commitments.status`, `payments.status`, `tasks.status` ([COM‑11…14], [PAY‑20], [TSK‑8], [PRJ‑9…13]).

**Mechanism:** one `BEFORE UPDATE` trigger per table (`tg_<entity>_status_transition`) checking `(OLD.status, NEW.status)` against a hard-coded allowed-set (a `CASE` or a small `(from,to)` lookup). Illegal pairs → `RAISE EXCEPTION 'orchestr:bad_status_transition:...'`. Same-value (`OLD = NEW`) always allowed. Side-effects (e.g. `completed_at`, `archived_at`, `paid_on`) are set/cleared in the same trigger.

**Why a trigger:** `CHECK` constraints see only the new row, not the transition. A generated column can't gate an update. Enum + trigger is the idiomatic state-machine pattern.

### 7.8 draft→active auto-transition

**Requirement:** `draft → active` when the first commitment is created, or a second member becomes active, or manually ([PRJ‑10]).

**Mechanism:**
- `tg_commitment_activates_project` `AFTER INSERT ON commitments` → `UPDATE projects SET status='active' WHERE id = NEW.project_id AND status='draft'`.
- `tg_member_activates_project` `AFTER INSERT OR UPDATE OF status ON project_members` → same update when the project now has ≥ 2 active members.
- Manual is a normal `projects.status` update (gated by [§7.7](#77-status-transition-legality)).

Both run `SECURITY DEFINER` (the actor may not have UPDATE on `projects` — a `member` creating a commitment isn't an organizer). The function updates *only* the `status` column and *only* `draft → active`, so the elevated scope is minimal and safe.

### 7.8b Financial-history preservation

**Requirement:** real money movements are never lost. Cancelling a commitment must not erase its paid/refunded payments; a paid payment cannot be soft-deleted; audit of money is immutable ([BUSINESS_RULES §8 amendment], GC‑8).

**Mechanisms (layered):**
1. `tg_payment_soft_delete_guard` `BEFORE UPDATE ON payments` — reject setting `deleted_at` when the row `status = 'paid'` **or has ever been paid** (tracked by `paid_on IS NOT NULL`). Message: `orchestr:paid_payment_immutable:cancel or waive instead`.
2. `tg_commitment_cancel_cascade` cancels **only `status='scheduled'`** payments ([§7.4](#74-soft-delete-cascade)) — `paid` / `waived` rows are structurally untouched.
3. `payments` has **no** hard-`DELETE` path except project purge (CASCADE).
4. `v_project_financials` computes `gross_paid_minor` / `refunded_minor` / `net_actual_spend_minor` from `payments WHERE status='paid'` **without** joining `commitments.deleted_at` or `commitments.status` — history survives commitment cancellation by construction.
5. `audit_log` immutability ([§7.12](#712-immutable-audit-history)) preserves the full change record regardless.

### 7.9 Timezone validity

**Requirement:** `projects.timezone`, `users.timezone` are valid IANA names.

**Mechanism:** `tg_validate_timezone` `BEFORE INSERT OR UPDATE` → `IF NOT EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = NEW.timezone) THEN RAISE EXCEPTION 'orchestr:bad_timezone:...'`.

**Why not a `CHECK`:** `CHECK` bodies must be `IMMUTABLE`; `pg_timezone_names` is `STABLE` at best (contents depend on the tz database shipped with the server) — a `CHECK` calling it is rejected / unsafe across dump-restore.

### 7.10 Archived project read-only

**Requirement:** no create/edit/delete of child entities while `projects.status='archived'`, except the un-archive and project-delete paths ([PRJ‑17]).

**Mechanism:** `tg_enforce_project_writable` `BEFORE INSERT OR UPDATE OR DELETE` on **every** project-scoped child table → look up the parent project's `status`; if `archived` → `RAISE EXCEPTION 'orchestr:project_archived:...'`. The un-archive operation is an `UPDATE` on `projects` itself (not a child) and is allowed; the project-purge is a hard `DELETE` on `projects` (CASCADE runs with `session_replication_role` semantics or the trigger explicitly allows cascade context).

**Why a trigger, not RLS:** RLS could encode it, but a trigger yields a clear, catchable error message rather than a silent "0 rows".

### 7.11 Cost-share basis consistency

**Requirement:** a commitment's cost shares form a coherent split — all `equal`, all `weight`, or `fixed` amounts optionally combined with a single fallback basis for the remainder ([BUSINESS_RULES BUD‑11]).

**Mechanism:** `tg_cost_share_basis_consistency` `AFTER INSERT OR UPDATE OR DELETE ON cost_shares` (`CONSTRAINT TRIGGER`, `DEFERRABLE INITIALLY DEFERRED` so a multi-row `upsert` is validated once at commit). It re-reads all rows for the commitment and rejects incoherent mixes.

**Why a deferred constraint trigger:** the rule is about the *set* of sibling rows; it must tolerate transient inconsistency mid-transaction while the app replaces the whole split.

### 7.12 Immutable audit history

Covered in [§4.14](#414-audit_log). Three enforcement layers: RLS (no write policy), privilege (`REVOKE`), and an unconditional `BEFORE UPDATE OR DELETE` trigger. Writes happen only through `app.tg_audit_row()` (`SECURITY DEFINER`, owned by a role whose sole elevated capability is `INSERT ON audit_log`).

### 7.13 `project_id` immutability

**Requirement:** a child row can never be moved to another project (would defeat [§7.1](#71-cross-project-referential-integrity) and RLS).

**Mechanism:** `tg_block_project_id_change` `BEFORE UPDATE` on every project-scoped table → `IF NEW.project_id <> OLD.project_id THEN RAISE EXCEPTION 'orchestr:immutable_column:project_id'`. Also blocks `created_at`, `created_by` changes in the same trigger.

### 7.14 Enforcement summary

| Rule class | Mechanism | Count |
|------------|-----------|-------|
| Field shape, ranges, non-negativity, "X set iff Y" | `CHECK` | ~25 |
| Same-project references | composite FK on denormalised `project_id` | ~14 FKs |
| Existence / cascade on hard delete | FK `ON DELETE CASCADE` / `SET NULL` | all child FKs |
| Scoped uniqueness | partial unique index | 4 |
| Cross-row invariants (currency lock, last organizer, transitions, archived, basis coherence, tz) | row / statement / constraint triggers | ~14 |
| Soft-delete cascade & side-effects | `AFTER UPDATE` triggers | 2 |
| Auto state changes (draft→active, completed_at, etc.) | triggers | ~5 |
| Immutability (audit, project_id) | `REVOKE` + trigger + RLS | 3 tables |
| Privileged writes needing elevation | `SECURITY DEFINER` RPC | 3 |
| Derived data | views + 1 function | 0 tables |

---

## 8. Helpers, functions, triggers, views, RPCs

### 8.1 Generic triggers

| Trigger fn | Fires | On | Purpose |
|------------|-------|-----|---------|
| `app.tg_set_updated_at()` | `BEFORE UPDATE` | all mutable tables | `NEW.updated_at := now()` |
| `app.tg_set_created_by()` | `BEFORE INSERT` | user-authored tables | `NEW.created_by := coalesce(NEW.created_by, app.current_member_id(NEW.project_id))` |
| `app.tg_block_project_id_change()` | `BEFORE UPDATE` | all project-scoped tables | reject `project_id` / `created_at` / `created_by` change ([§7.13](#713-project_id-immutability)) |
| `app.tg_enforce_project_writable()` | `BEFORE INSERT/UPDATE/DELETE` | all project-scoped child tables | block writes when project archived ([§7.10](#710-archived-project-read-only)) |
| `app.tg_audit_row()` | `AFTER INSERT/UPDATE/DELETE` | all audited tables (`SECURITY DEFINER`) | write `audit_log` ([§7.12](#712-immutable-audit-history)) |
| `app.tg_validate_timezone()` | `BEFORE INSERT/UPDATE` | `projects`, `users` | IANA check ([§7.9](#79-timezone-validity)) |
| `app.tg_lowercase_email()` | `BEFORE INSERT/UPDATE` | `invitations` | normalise email |

### 8.2 SECURITY DEFINER helpers & RPCs

All in schema `app`, all with:
- `SET search_path = ''` (every reference fully schema-qualified — prevents search-path hijack),
- `STABLE` (helpers) or `VOLATILE` (RPCs),
- `REVOKE EXECUTE FROM public; GRANT EXECUTE TO authenticated;`,
- narrowest possible body (helpers only ever read membership for `auth.uid()` and return a boolean or the caller's own member row — they cannot be coerced into leaking another user's data),
- no dynamic SQL; inputs are `uuid` / `text` only.

| Object | Kind | Security | Purpose | Why it needs elevation |
|--------|------|----------|---------|------------------------|
| `app.current_member(p_project uuid) → project_members` | helper | DEFINER, STABLE | the caller's active membership row for a project, or NULL | RLS on `project_members` would recurse if policies queried it directly |
| `app.current_member_id(p_project uuid) → uuid` | helper | DEFINER, STABLE | id only (for `created_by`) | ↑ |
| `app.is_member(p_project uuid) → boolean` | helper | DEFINER, STABLE | membership predicate for RLS on all other tables | ↑ |
| `app.has_role(p_project uuid, p_roles member_role[]) → boolean` | helper | DEFINER, STABLE | role predicate for write policies | ↑ |
| `app.is_organizer(p_project uuid) → boolean` | helper | DEFINER, STABLE | shorthand | ↑ |
| `app.finding_is_dismissible(p_code text) → boolean` | helper | INVOKER, IMMUTABLE | severity/dismissibility of a rule code (static map) | none — pure |
| `app.accept_invitation(p_token text) → uuid` | RPC | DEFINER, VOLATILE | validate token (pending, unexpired), claim matching name-only member or create one, set `user_id = auth.uid()`, `status='active'`, mark invitation `accepted`, write audit; returns `project_id` | the invitee is **not yet a member**; RLS would block every write |
| `app.transfer_and_leave(p_project uuid, p_new_organizer_member uuid) → void` | RPC | DEFINER, VOLATILE | atomic: promote target to `organizer`, set caller's membership `status='removed'`; passes the last-organizer guard because both happen in one statement sequence before commit | must bypass the ordering trap in `tg_last_organizer_guard` ([§7.6](#76-last-organizer-guarantee)) |
| `app.get_project_health(p_project uuid) → setof finding` | RPC | INVOKER, STABLE | the health engine ([§9](#92-functions--rpcs)) | none beyond a membership check it performs itself |
| `app.get_project_health_summary(p_project uuid) → record` | RPC | INVOKER, STABLE | rollup counts + status | ↑ |
| `app.tg_handle_new_user()` | trigger fn | DEFINER | create `public.users` row on `auth.users` insert | writes a table the new user has no rights on yet |
| `app.tg_after_project_insert_create_member()` | trigger fn | DEFINER | founding organizer membership + back-fill `created_by` ([§7.2](#72-circular-dependency-projects--project_members)) | the creator has no `project_members` row to satisfy an INSERT policy yet |
| `app.tg_*_activates_project()` | trigger fns | DEFINER | `draft → active` ([§7.8](#78-draftactive-auto-transition)) | a `member` lacks UPDATE on `projects` |
| `app.tg_last_organizer_guard()` | trigger fn | DEFINER | count organizers across RLS ([§7.6](#76-last-organizer-guarantee)) | must see rows the caller might not |
| `app.tg_audit_row()` | trigger fn | DEFINER | append-only audit | only elevated capability: `INSERT ON audit_log` |

### 8.3 Views

All views: `WITH (security_invoker = true)` (base-table RLS applies to the querying user), `WHERE deleted_at IS NULL` on every soft-deletable source, and a `project_id` column for filtering.

| View | Grain | Contents |
|------|-------|----------|
| `app.v_commitment_financials` | commitment | `effective_cost_minor`, `gross_paid_minor`, `refunded_minor`, `net_paid_minor`, `outstanding_minor` (BUD‑7 per-commitment), `payment_progress` (`unpaid`/`deposit_paid`/`part_paid`/`paid_in_full` — [§5.4](#54-payment-status)), `is_paid_in_full` |
| `app.v_project_financials` | project | `total_cost_minor` (BUD‑4), `committed_spend_minor` (BUD‑5), `gross_paid_minor` / `refunded_minor` / `net_actual_spend_minor` (BUD‑6, history-preserving), `outstanding_minor` (BUD‑7), `scheduled_outstanding_minor` (PAY‑14), `remaining_budget_minor` (BUD‑8), `projected_variance_minor` / `settled_variance_minor` (BUD‑9), `progress_pct` (VAL‑49), `commitment_count`, `open_commitment_count` |
| `app.v_budget_category_actuals` | project × kind | `target_minor`, `actual_minor`, `variance_minor` (BUD‑9/10) |
| `app.v_member_balances` | project × member | `owed_minor`, `contributed_minor`, `balance_minor` (BUD‑13/14/15); default equal split computed from `commitment_participants` when the commitment has no `cost_shares` (BUD‑11); deterministic minor-unit rounding (BUD‑16) |
| `app.v_timeline_events` | event | `project_id`, `occurs_at timestamptz`, `event_type`, `title`, `subject_type`, `subject_id`, `status` — `UNION ALL` of the 7 sources (TML‑1), ordered by `occurs_at` |
| `app.v_member_directory` | project × member | `member_id`, `display_name`, `avatar_url`, `role`, `status` — the columns co-members may see (feeds People tab, owner pickers) |
| `app.v_my_projects` | project | project columns + caller's `role` + `v_project_financials` summary + `attention_count` (from `get_project_health_summary`) + `next_event_at` (from `v_timeline_events`) — for Dashboard / Projects list |

> **Performance note:** `v_my_projects` calls the health summary per project. For a user's realistic project count (single digits) this is fine on read. If it ever isn't, the mitigation is a small `project_health_cache(project_id, status, attention_count, computed_at)` refreshed by an `AFTER` statement trigger on the contributing tables — still no derived *business* data stored, just a memoised count. Not in MVP.

### 8.4 Functions / RPCs — the health engine

`app.get_project_health(p_project uuid)` — `SECURITY INVOKER`, `STABLE`, returns
`setof (code text, severity text, subject_type text, subject_id uuid, subject_label text, params jsonb, message text, resolution text, affects_health boolean, dismissible boolean, dismissed boolean, snoozed_until date)`:

1. `IF NOT app.is_member(p_project) THEN RAISE insufficient_privilege; END IF;`
2. resolve thresholds: `coalesce((SELECT (projects.health_config->>'inactive_days')::int FROM public.projects WHERE id = p_project), 7)`, etc.
3. one CTE per rule set (HLT‑1…17 from [BUSINESS_RULES §9.2]), each `SELECT`ing the offending rows with a literal `code`, `severity`, computed `message`/`resolution`, `params`.
4. `UNION ALL` them.
5. `LEFT JOIN finding_dismissals` on `(project_id, code, subject_type, subject_id)` → attach `dismissed` (state `dismissed`, or `snoozed` with `snoozed_until >= today`) — but never for `blocker` rows.
6. `today` computed in the project timezone.

`app.get_project_health_summary(p_project uuid)` — reuses the same rule CTEs (shared via an internal `app._health_findings(p_project)` `SECURITY DEFINER`-free helper) and returns `(status text, blocker_count int, warning_count int, info_count int, attention_count int)` where `status ∈ {needs_attention, at_risk, healthy}` (HLT‑C) and `attention_count` counts non-dismissed `blocker`+`warning` (HLT‑E).

**No table.** Findings never persist. The only writes in this area are `finding_dismissals` upserts by the client.

### 8.5 Trigger master list (per table)

| Table | Triggers |
|-------|----------|
| `users` | set_updated_at, validate_timezone, audit_row |
| `projects` | set_updated_at, validate_timezone, currency_immutable, project_status_transition, after_insert_create_member, project_soft_delete_cascade, audit_row |
| `project_members` | set_updated_at, block_project_id_change, member_status_transition, last_organizer_guard, member_activates_project, enforce_project_writable, audit_row |
| `invitations` | set_updated_at, lowercase_email, enforce_project_writable, audit_row |
| `commitments` | set_updated_at, set_created_by, block_project_id_change, commitment_status_transition, commitment_owner_role_check, commitment_activates_project, commitment_cancel_cascade, enforce_project_writable, audit_row |
| `commitment_participants` | set_updated_at, block_project_id_change, participant_member_active_check, enforce_project_writable, audit_row |
| `cost_shares` | set_updated_at, block_project_id_change, cost_share_basis_consistency (deferred constraint trigger), enforce_project_writable, audit_row |
| `payments` | set_updated_at, set_created_by, block_project_id_change, payment_status_transition, payment_no_create_on_cancelled, payment_soft_delete_guard, payment_paid_on_not_future, enforce_project_writable, audit_row |
| `tasks` | set_updated_at, set_created_by, block_project_id_change, task_status_transition, task_assignee_role_check, enforce_project_writable, audit_row |
| `milestones` | set_updated_at, set_created_by, block_project_id_change, enforce_project_writable, audit_row |
| `budgets` | set_updated_at, enforce_project_writable, audit_row |
| `budget_category_targets` | set_updated_at, enforce_project_writable, audit_row |
| `finding_dismissals` | set_updated_at, dismissal_not_blocker, enforce_project_writable, audit_row |
| `audit_log` | audit_immutable (block UPDATE/DELETE) |
| `auth.users` | handle_new_user (AFTER INSERT) |

### 8.6 Index master list

Beyond every PK and the FK-backing indexes PostgreSQL does **not** create automatically (all FK columns get an explicit index):

```
users:                    unique(lower(email))
projects:                 (status) where deleted_at is null; (created_by)
project_members:          unique(project_id, id);
                          unique(project_id, user_id) where user_id is not null;
                          unique(project_id, lower(email)) where email is not null and status<>'removed' and deleted_at is null;
                          (user_id) where user_id is not null;
                          (project_id, role) where status='active' and deleted_at is null
invitations:              unique(token);
                          unique(project_id, lower(email)) where status='pending';
                          (project_id) where status='pending'
commitments:              unique(project_id, id);
                          (project_id, status) where deleted_at is null;
                          (owner_member_id) where deleted_at is null;
                          (project_id, starts_at) where deleted_at is null and status<>'cancelled';
                          (project_id, kind) where deleted_at is null;
                          (project_id, updated_at) where status in ('idea','researching') and deleted_at is null
commitment_participants:  unique(commitment_id, member_id); (member_id); (commitment_id); (project_id)
cost_shares:              unique(commitment_id, member_id); (commitment_id); (member_id); (project_id)
payments:                 (project_id, status) where deleted_at is null;
                          (project_id, status, due_on) where deleted_at is null and status='scheduled';
                          (commitment_id) where deleted_at is null;
                          (paid_by_member_id) where status='paid' and deleted_at is null
tasks:                    (project_id, status) where deleted_at is null;
                          (project_id, status, due_on) where deleted_at is null and status in ('open','in_progress');
                          (assignee_member_id) where deleted_at is null;
                          (commitment_id) where deleted_at is null
milestones:               (project_id, on_date); (commitment_id) where commitment_id is not null
budget_category_targets:  pk(project_id, kind)
finding_dismissals:       unique nulls not distinct (project_id, code, subject_type, subject_id); (project_id)
audit_log:                (project_id, at desc); (entity_type, entity_id, at desc); (actor_user_id, at desc)
```

---

## 9. Relationship review

### 9.1 Referential integrity
- **All** entity-to-entity links are FK-backed. Member/commitment/parent references use **composite FKs** so they cannot point across projects ([§7.1](#71-cross-project-referential-integrity)).
- Deliberate non-FKs, each justified: `projects.created_by` (cycle avoidance, [§7.2](#72-circular-dependency-projects--project_members)); `finding_dismissals.subject_id` (polymorphic, points at computed findings); `audit_log.*` (must outlive referents).
- `ON DELETE`: `CASCADE` for the purge path; `SET NULL` for optional actor/assignee/payer references so history survives.

### 9.2 Circular dependencies
- **One potential cycle** — `projects` ↔ `project_members` — resolved by having no FK from `projects` to members and creating the founding member in an `AFTER INSERT` trigger. No `DEFERRABLE` FKs anywhere.
- `commitments`/`payments`/`milestones`/`tasks` form a strict tree under `projects`; no back-references.

### 9.3 Duplicate data
- `project_id` is denormalised onto every child — **intentional and FK-consistent**, not free-floating duplication ([§1](#1-conventions)). Trade-off accepted for cross-project safety + RLS performance.
- `project_members.display_name` / `email` duplicate `users.*` — intentional (project-local identity, invite-time snapshot; [DOMAIN_MODEL MEM‑4]).
- **No** derived totals are stored (the prototype's mistake). `budgets` holds targets only.
- `currencies.minor_unit` is the only place minor-unit precision lives.

### 9.4 Unnecessary tables — evaluated
| Candidate | Verdict |
|-----------|---------|
| `budget` actuals table | **rejected** — derived ([§5.1](#51-budget-actuals)) |
| `timeline_events` table | **rejected** — derived view ([§5.2](#52-timeline)) |
| `health_findings` table | **rejected** — derived function ([§5.3](#53-health)) |
| `commitment_payment_status` / `outstanding` columns | **rejected** — derived ([§5.4](#54-payment-status), [§5.7](#57-outstanding)) |
| `member_balances` table | **rejected** — derived ([§5.5](#55-per-member-balances)) |
| `health_config` table | **folded** into `projects.health_config jsonb` — 5 optional scalars per project don't warrant a table |
| `cost_shares` for equal splits | **not stored** — equal split is derived from participants; `cost_shares` holds only explicit overrides ([§4.7](#47-cost_shares)) |
| `suppliers`, `places` | **not now** — embedded value objects ([DOMAIN_MODEL §5.12]); promotion path in [§9.5](#95-future-extensibility) |
| `currencies` | **kept** — real integrity/formatting value, static |
| `finding_dismissals` | **kept** — user intent, not derivable |
| `audit_log` | **kept** — required for auditability |

15 tables total (14 entity + 1 reference).

### 9.5 Future extensibility
| Future feature | Schema move (additive, no rewrite) |
|----------------|-----------------------------------|
| Supplier directory | new `suppliers` table; add `commitments.supplier_id` composite FK; keep or migrate embedded fields |
| Saved places / map | new `places` table; add `commitments.place_id` |
| Comments / attachments | new polymorphic `comments` / `attachments` tables keyed by `(project_id, entity_type, entity_id)`; reuse the `tg_audit_row` + `tg_enforce_project_writable` pattern |
| Global contacts | new `contacts` (user-scoped); add `project_members.contact_id` |
| Notifications + scheduled health | new `notifications` table; a cron Edge Function calls the **existing** `app.get_project_health()` and diffs — no schema change to health |
| Co-owners | new `commitment_collaborators` join; `owner_member_id` untouched |
| RSVP UI | already has `commitment_participants.rsvp` |
| iCal feed | already has `v_timeline_events`; add a per-project feed token column on `projects` |
| Multi-currency | add `currency` to money-bearing tables, backfill from `projects.currency`, relax `tg_currency_immutable`; the `currencies.minor_unit` lookup already exists |
| Settlement ("who pays whom") | new `settlements` table referencing two `project_members`; `v_member_balances` already provides the targets |
| Optimistic concurrency (GC‑6) | `updated_at` already present; add `WHERE updated_at = $expected` in the service layer — no schema change |

---

## 10. Open items for the migration phase

1. **Seed content** — port the prototype's Barcelona + Wedding fixtures to `supabase/seed.sql` as realistic dev/staging data ([TECHNICAL_ARCHITECTURE §22.2]).
2. **`health_config` JSON shape** — finalise key names + global default constants inside `app.get_project_health()` ([BUSINESS_RULES D‑6]).
3. **`v_member_balances` rounding order** — define the "stable order" for BUD‑16 remainder distribution (recommend `project_members.id` ascending).
4. **`audit_log` payload trimming** — list per-table columns excluded from `before`/`after` (large text, tokens).
5. **`transfer_and_leave` vs. separate promote/leave** — confirm the RPC is worth it for MVP or if the client sequences two writes.
6. **Realtime publication** — which tables join `supabase_realtime` for the per-project channel ([TECHNICAL_ARCHITECTURE §8.1]).
7. **`pg_cron`** — not needed for MVP (health is read-time); revisit with notifications.
```
