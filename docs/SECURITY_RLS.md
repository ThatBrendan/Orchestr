# Supabase Security Model — RLS, Helpers, and Attack Analysis

**Status:** Draft for review
**Date:** 2026-09-04
**Source material:** [`docs/DOMAIN_MODEL.md`](./DOMAIN_MODEL.md), [`docs/BUSINESS_RULES.md`](./BUSINESS_RULES.md), [`docs/TECHNICAL_ARCHITECTURE.md`](./TECHNICAL_ARCHITECTURE.md), [`docs/DATABASE_SCHEMA.md`](./DATABASE_SCHEMA.md)
**Non-goals:** no migration files, no final DDL. Policy bodies below are **recommended and illustrative** — precise enough to implement, not yet implemented.

---

## 1. Security model — non-negotiables

1. **The database is the security boundary.** Every read and write is authorised by PostgreSQL Row Level Security. Vue route guards, `usePermissions()`, hidden buttons — all UX only. Removing the entire frontend and hand-crafting REST calls with a valid JWT must yield *exactly* the same access.
2. **Deny by default.** RLS is enabled and `FORCE`d on every table in `public`. A table with no policy for a (role, verb) grants nothing. `REVOKE ALL ... FROM anon, authenticated` first; `GRANT` back the minimum, then constrain with policies.
3. **Membership is derived, never asserted by the client.** A user's role in a project comes only from a `project_members` row that was created by (a) the project-creation trigger or (b) `app.accept_invitation()`. There is no code path where a client INSERT/UPDATE can make the caller a member or raise their role.
4. **Elevation is contained.** `SECURITY DEFINER` is used in exactly the places [DATABASE_SCHEMA §8.2] lists, each with `SET search_path = ''`, typed args, no dynamic SQL, and a body that can only ever act on `auth.uid()`'s own membership or a token the caller already holds.
5. **History is immutable.** `audit_log` and paid `payments` cannot be altered or removed by any client role; `audit_log` cannot be altered by `service_role` either.
6. **Soft-deleted and deleted-project data is invisible** to every non-service role, including the project's own organizers ([BUSINESS_RULES PRJ‑23]). Restore is a support/`service_role` operation in MVP.
7. **Platform administration is global and separate.** `users.platform_role` (`user`/`admin`) is the platform-admin role. `project_members.role` remains project-scoped (`organizer`/`member`/`viewer`).

---

## 2. Principals

### 2.1 PostgreSQL / PostgREST roles

| Role | Who | How it reaches the DB | RLS applies? |
|------|-----|----------------------|--------------|
| `anon` | any unauthenticated caller using the anon key | PostgREST with no/invalid JWT | yes — and almost every policy excludes it |
| `authenticated` | any signed-in user; JWT carries `sub` = `auth.uid()` | PostgREST (`supabase-js` **or** raw `fetch` — identical) | yes |
| `platform admin` | signed-in user with `users.platform_role = 'admin'` | Same anon key + JWT as any authenticated user | yes; admin SELECT policies/read models require `app.is_platform_admin()` |
| `service_role` | Edge Functions, migrations, CI, support scripts | service key, **never in the browser bundle** ([TECHNICAL_ARCHITECTURE §8.1]) | **no — bypasses RLS.** Must self-authorise. |
| `postgres` / migration owner | schema management only | direct connection | n/a |

### 2.2 Application principals (all are `authenticated` + a `project_members` fact)

| Principal | Definition | Determined by |
|-----------|------------|---------------|
| **Organizer** | active `project_members` row for the project with `role = 'organizer'` | `app.is_organizer(project_id)` |
| **Member** | active row with `role = 'member'` | `app.has_role(project_id, '{member}')` |
| **Viewer** | active row with `role = 'viewer'` | `app.has_role(project_id, '{viewer}')` |
| **Project member** (any of the above) | active row, any role, project not deleted | `app.is_member(project_id)` |
| **Non-member** | authenticated, but no active row for that project | `NOT app.is_member(project_id)` |
| **Anonymous** | not authenticated | role `anon` |

> "Project owner" in the prompt = **Organizer**. There is no single owner ([DOMAIN_MODEL §5.2]); ownership is the set of active organizers.

A user is simultaneously different principals in different projects. Every policy is evaluated **per row**, against that row's `project_id`.

---

## 3. Trust boundary & REST-bypass equivalence

`supabase-js` is a thin wrapper over PostgREST. These are the same request to the database:

```
supabase.from('commitments').select('*').eq('project_id', X)
GET /rest/v1/commitments?select=*&project_id=eq.X      (Authorization: Bearer <user JWT>, apikey: <anon key>)
```

Both arrive as role `authenticated` with `auth.uid()` from the JWT; RLS runs identically. Therefore:

- **The anon key is not a secret and grants nothing on its own** — it only selects the `anon`/`authenticated` role; data access still needs a user JWT *and* a passing policy.
- **A stolen user JWT** grants exactly that user's access until it expires (≤ 1 h, `autoRefreshToken`). Nothing in the schema trusts a claim the JWT doesn't cryptographically carry.
- **Only `service_role` is dangerous if leaked.** It is confined to Edge Functions and server tooling. A CI check fails the frontend build if a `SERVICE_ROLE|SECRET` var appears in client env ([TECHNICAL_ARCHITECTURE §21]).

Every attack case in [§10](#10-attack-case-analysis) is written as a raw REST call for this reason.

---

## 4. Helper functions

All in schema `app`. **`app` is NOT exposed to PostgREST** (`db-schemas = public` only) — these are callable from SQL (policies, views, RPCs) but not via `supabase.rpc()`. Client-facing RPCs live in `public` ([§6](#6-rpc-authorization)).

> This refines [TECHNICAL_ARCHITECTURE §1] ("RPCs in `app`"): **RLS internals in `app` (unexposed); client RPCs in `public` (exposed).**

### 4.1 Definitions (behaviour, not final SQL)

```sql
-- All: LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
--      REVOKE EXECUTE FROM public;  GRANT EXECUTE TO authenticated;

app.is_member(p_project uuid) RETURNS boolean
  := EXISTS (
       SELECT 1 FROM public.project_members m
       JOIN public.projects pr ON pr.id = m.project_id
       WHERE m.project_id = p_project
         AND m.user_id   = (SELECT auth.uid())
         AND m.status    = 'active'
         AND m.deleted_at IS NULL
         AND pr.deleted_at IS NULL );      -- deleted project ⇒ not a member (PRJ‑23)

app.has_role(p_project uuid, p_roles public.member_role[]) RETURNS boolean
  := EXISTS ( ... same join ... AND m.role = ANY (p_roles) );

app.is_organizer(p_project uuid) RETURNS boolean
  := app.has_role(p_project, ARRAY['organizer']::public.member_role[]);

app.current_member_id(p_project uuid) RETURNS uuid
  := ( SELECT m.id FROM public.project_members m
        WHERE m.project_id = p_project
          AND m.user_id = (SELECT auth.uid())
          AND m.status = 'active' AND m.deleted_at IS NULL
        LIMIT 1 );

app.is_writable_project(p_project uuid) RETURNS boolean
  := EXISTS ( SELECT 1 FROM public.projects
              WHERE id = p_project AND deleted_at IS NULL AND status <> 'archived' );

app.finding_is_dismissible(p_code text) RETURNS boolean   -- IMMUTABLE, SECURITY INVOKER
  := p_code <> ALL (ARRAY['payment_overdue']);            -- blockers not dismissible (HLT‑F)
```

### 4.2 Why `SECURITY DEFINER` is required and why it is safe

- **Required:** RLS policies on `project_members` cannot themselves `SELECT project_members` under RLS without infinite recursion. The definer functions read that table with RLS bypassed.
- **Safe because:**
  - `SET search_path = ''` + fully-qualified names ⇒ no search-path hijack (a caller cannot shadow `public.project_members` with their own object).
  - Arguments are `uuid` / `member_role[]` only; **no dynamic SQL**, no string concatenation ⇒ no injection.
  - Every function filters on `m.user_id = auth.uid()`. The *only* fact it can reveal is something about the **caller's own** membership. Calling `app.is_member('<any project>')` tells the caller whether *they* are in it — which they already know. It cannot enumerate other users or other projects' contents.
  - `STABLE`, not `VOLATILE` — no writes.
  - `REVOKE EXECUTE FROM public` + `GRANT ... TO authenticated` — `anon` cannot even call them (and gains nothing if it could).
  - Owned by the migration role (Supabase: `postgres`); the body touches only two tables and performs no action a compromised call could leverage.
- **`app.current_member_id`** returns the caller's own member UUID — used to stamp `created_by` and to compare ownership in policies. Returning it to the caller is harmless (it's their identity in that project).

### 4.3 PostgREST exposure of `app`

`app` is omitted from `db-schemas`. Even so: `REVOKE ALL ON ALL FUNCTIONS IN SCHEMA app FROM anon;` and `REVOKE ALL ON SCHEMA app FROM anon;` as defence in depth. Trigger functions (`app.tg_*`) additionally `REVOKE EXECUTE FROM public` — calling a trigger function outside trigger context errors on `TG_OP`, but we remove the option entirely.

---

## 5. Table-by-table policies

Format per table: **Grants** (table privileges to `anon`/`authenticated`) → **SELECT / INSERT / UPDATE / DELETE** policies (USING / WITH CHECK) → **notes & attack notes**. `service_role` bypasses all of this and is covered in [§11](#11-operations-requiring-edge-functions--elevated-privilege).

Global: `ALTER TABLE <t> ENABLE ROW LEVEL SECURITY; ALTER TABLE <t> FORCE ROW LEVEL SECURITY;` on every table. `REVOKE ALL ON <t> FROM anon, authenticated;` then selective `GRANT`.

---

### 5.1 `users`

**Grants:** `anon`: none. `authenticated`: `SELECT, UPDATE` (column-limited for other users via [§5.1 notes]).

| Verb | Policy | Who |
|------|--------|-----|
| SELECT | `USING (id = (select auth.uid()))` | self only |
| INSERT | *no policy* | nobody — rows created only by `app.tg_handle_new_user()` (`SECURITY DEFINER`, on `auth.users` insert) |
| UPDATE | `USING (id = (select auth.uid())) WITH CHECK (id = (select auth.uid()))` | self only |
| DELETE | *no policy* + `REVOKE DELETE` | nobody — account deletion is an Auth-admin / Edge Function operation |

**Cross-member display data** (name + avatar of co-members) is **not** served from `users`. It comes from `app.v_member_directory` ([§7](#7-views--exposed-read-models)), a `security_invoker = false` view that joins `project_members` → `users` and returns only `(project_id, member_id, display_name, avatar_url, role, status)` for projects where `app.is_member(project_id)`. This keeps `email`, `timezone`, `default_currency`, `notification_prefs` private to the account owner.

**Attack notes:** `GET /rest/v1/users?select=*` → returns only your row unless you are a platform admin. `GET /rest/v1/users?id=eq.<someone>` → 0 rows for non-admins. `PATCH /rest/v1/users?id=eq.<someone>` → 0 rows updated. No normal-user enumeration of the user base.

**Platform role notes:** authenticated clients cannot change `users.platform_role`; `app.tg_block_client_platform_role_change()` raises `orchestr:platform_role_locked` whenever a JWT-backed session attempts it. Bootstrap the first admin only from a trusted database/Supabase administrative environment:

```sql
update public.users
set platform_role = 'admin'
where email = '<known-user@example.com>';
```

There is no email-domain rule and no frontend promotion flow.

---

### 5.2 `projects`

**Grants:** `anon`: none. `authenticated`: `SELECT, INSERT, UPDATE`.

| Verb | Policy |
|------|--------|
| SELECT | `USING (app.is_member(id))` — active members of non-deleted projects only |
| INSERT | `WITH CHECK ((select auth.uid()) IS NOT NULL AND status = 'draft' AND deleted_at IS NULL AND archived_at IS NULL)` |
| UPDATE | `USING (app.is_organizer(id)) WITH CHECK (app.is_organizer(id))` |
| DELETE | *no policy* + `REVOKE DELETE` — hard purge is `service_role` only |

**Notes:**
- On INSERT, `created_by` is ignored/overwritten and the founding `project_members` row (organizer, `user_id = auth.uid()`) is created by `app.tg_after_project_insert_create_member()` ([DATABASE_SCHEMA §7.2]). `WITH CHECK (status='draft')` blocks creating a project pre-archived or pre-completed.
- Soft delete = organizer `UPDATE ... SET deleted_at = now()`. Allowed by the UPDATE policy. Immediately after commit the row fails `app.is_member` / `app.is_organizer` for everyone → invisible ([§1](#1-security-model--non-negotiables) point 6).
- Un-archive / archive = organizer `UPDATE status`; gated by `app.tg_project_status_transition`.
- `currency` change attempts are stopped by `app.tg_currency_immutable` once money exists.

**Attack notes:**
- Non-member `GET /rest/v1/projects` → only their projects; the target project is not in the result set, and `?id=eq.<target>` → 0 rows (no info leak — indistinguishable from "does not exist").
- `POST /rest/v1/projects {"status":"active", "created_by":"<victim>"}` → `status` rejected by `WITH CHECK`; even if `draft`, `created_by` is overwritten by trigger.
- Member (non-organizer) `PATCH /rest/v1/projects?id=eq.<mine> {"name":"x"}` → `app.is_organizer` false → 0 rows. Project settings are organizer-only ([BUSINESS_RULES MEM‑14]).

---

### 5.3 `project_members`  — *the role-escalation & self-enrolment surface*

**Grants:** `anon`: none. `authenticated`: `SELECT, INSERT, UPDATE`. **No `DELETE`.**

| Verb | Policy |
|------|--------|
| SELECT | `USING (user_id = (select auth.uid()) OR app.is_member(project_id))` |
| INSERT | `WITH CHECK ( app.is_organizer(project_id) AND user_id IS NULL AND role IN ('member','viewer') AND status = 'active' AND app.is_writable_project(project_id) )` |
| UPDATE | `USING ( app.is_organizer(project_id) OR user_id = (select auth.uid()) )` `WITH CHECK ( app.is_organizer(project_id) OR user_id = (select auth.uid()) )` — **plus** trigger `app.tg_member_update_guard` (below) |
| DELETE | *no policy* + `REVOKE DELETE` |

**`app.tg_member_update_guard` (`BEFORE UPDATE`):**
- If the caller **is an organizer** of `OLD.project_id`: allow `role` and `status` changes, subject to `app.tg_member_status_transition` and `app.tg_last_organizer_guard`. Cannot change `project_id`, `user_id`, `created_at` (also covered by `tg_block_project_id_change`).
- If the caller **is not an organizer** (self-service path, `OLD.user_id = auth.uid()`): permit changes to `display_name` only, **and** `status` only for the transition `active → removed` (leaving — [BUSINESS_RULES MEM‑20]). Any change to `role`, `user_id`, `email`, or any other `status` transition → `RAISE EXCEPTION 'orchestr:forbidden_member_change:...'`.

**Notes:**
- **You cannot enrol yourself.** The INSERT policy requires `app.is_organizer(project_id)` (a non-member fails) **and** `user_id IS NULL` (so even an organizer cannot INSERT a *login-linked* membership — linking a `user_id` happens only in `app.accept_invitation()`). Self-enrolment has no code path.
- **You cannot escalate your own role.** USING lets you touch your own row; the guard trigger forbids `role` changes by non-organizers.
- **An organizer promoting another to organizer** is a normal UPDATE (allowed). Demotions/removals that would zero the active-organizer count are blocked by `app.tg_last_organizer_guard` ([DATABASE_SCHEMA §7.6]).
- **Removal** = organizer sets `status='removed'`. Soft; all downstream references preserved ([BUSINESS_RULES MEM‑17]). Hard row deletion never happens except project purge.
- SELECT deliberately lets you see your own membership rows in *every* project (needed for the "your projects" list and invite reconciliation) plus all members of projects you're in.

**Attack notes:**
- `POST /rest/v1/project_members {"project_id":"X","user_id":"<me>","role":"organizer","status":"active"}` → `app.is_organizer(X)` false → **denied**. If the attacker *is* an organizer of X and retries: `user_id IS NULL` fails → **denied** (cannot self-link or link others without invite).
- `PATCH /rest/v1/project_members?id=eq.<my row> {"role":"organizer"}` → USING passes (own row) → `tg_member_update_guard`: non-organizer changing `role` → **exception**.
- `PATCH /rest/v1/project_members?id=eq.<other member> {"role":"viewer"}` as a plain member → USING fails (`app.is_organizer` false, not own row) → **0 rows**.
- Organizer demotes the only other organizer, then themselves: first demotion allowed; self-demotion → `tg_last_organizer_guard` → **exception** ("must keep one organizer"). Correct transfer path is `public.transfer_and_leave()`.
- `DELETE /rest/v1/project_members?id=eq.X` → no policy + revoke → **denied**.
- Cross-project: `PATCH .../project_members?id=eq.<member of project I'm an organizer of, but row belongs to another project>` — impossible; `id` is unique and its `project_id` is what the policy checks.

---

### 5.4 `invitations` — *invitation abuse surface*

**Grants:** `anon`: none. `authenticated`: `SELECT` only. **No client `INSERT/UPDATE/DELETE`.**

| Verb | Policy |
|------|--------|
| SELECT | `USING (app.is_organizer(project_id))` — organizers see their project's invitations |
| INSERT | *no policy* — created only by the `invitations-send` Edge Function (`service_role`), which first verifies the caller is an organizer |
| UPDATE | `USING (app.is_organizer(project_id)) WITH CHECK (app.is_organizer(project_id))` — for `revoke` (`status='revoked'`); acceptance is via RPC |
| DELETE | `USING (app.is_organizer(project_id))` — optional hard delete; revoke is preferred |

**Invitee path (no direct table access):**
- `/invite/:token` asks the user to sign in or create an account.
- Post-auth, the client calls `public.accept_invitation(p_token)` ([§6](#6-rpc-authorization)), which:
  - looks up the invitation by `token` (a 192-bit random string — not enumerable),
  - rejects if `status <> 'pending'` or `expires_at < now()` with a **generic** error (no oracle for "exists but expired" vs "revoked"),
  - **requires `lower(auth.users.email) = lower(invitations.email)`** — a forwarded link cannot be redeemed by a different account ([BUSINESS_RULES MEM‑10]; link-only invites are [FUTURE]),
  - claims a matching name-only `project_members` row (same `lower(email)`) or inserts a new one with `user_id = auth.uid()`, `status='active'`, `role = invitations.role`,
  - sets `invitations.status='accepted'`, `accepted_at`, `accepted_member_id`,
  - writes an `audit_log` row (`source='rpc'`),
  - is **idempotent**: a second call by the same user returns the `project_id`; a call by a different user on an already-accepted token → generic error.

**Notes:**
- `invitations.role` has `CHECK (role <> 'organizer')` — an invitation can never confer organizer.
- One `pending` invitation per `(project_id, lower(email))` (partial unique index) — re-invite refreshes rather than piling up.
- The Edge Function enforces rate limits (per project, per inviter) — RLS cannot.

**Attack notes:**
- `POST /rest/v1/invitations {...}` with a user JWT → no INSERT policy → **denied**. Invitation spam via direct REST is impossible; all creation funnels through the rate-limited Edge Function.
- `PATCH /rest/v1/invitations?token=eq.<guessed> {"status":"accepted"}` → non-organizer has no UPDATE policy and no SELECT → **denied**; and acceptance requires the RPC's email check anyway.
- Token brute force: 2¹⁹² space; plus Edge/gateway rate limiting on `accept_invitation`; plus generic errors.
- A member (non-organizer) tries to read who's been invited: `GET /rest/v1/invitations?project_id=eq.X` → `app.is_organizer` false → **0 rows**.
- Accepting an invitation to gain access to a project then reading everything — this is *working as intended* (they were invited); the invitation's `role` bounds them to `member`/`viewer`.
- Self-invitation: an organizer inviting their own email and accepting → they're already a member; `accept_invitation` finds the existing active membership and no-ops. No escalation (role can't exceed the invitation's non-organizer role, and their existing role is unchanged).

---

### 5.5 `commitments`  (and **Locations** — embedded columns, no separate policy)

**Grants:** `anon`: none. `authenticated`: `SELECT, INSERT, UPDATE`. **No `DELETE`** (soft delete is an UPDATE).

| Verb | Policy |
|------|--------|
| SELECT | `USING (app.is_member(project_id) AND deleted_at IS NULL)` |
| INSERT | `WITH CHECK ( app.has_role(project_id, '{organizer,member}') AND app.is_writable_project(project_id) AND status IN ('idea','researching') AND deleted_at IS NULL )` |
| UPDATE | `USING ( app.has_role(project_id,'{organizer,member}') AND deleted_at IS NULL )` `WITH CHECK ( app.has_role(project_id,'{organizer,member}') AND ( deleted_at IS NULL OR app.is_organizer(project_id) OR created_by = app.current_member_id(project_id) OR owner_member_id = app.current_member_id(project_id) ) )` |
| DELETE | *no policy* + `REVOKE DELETE` |

**Notes:**
- **Locations** live in `location_*` columns on this table. A principal who can `SELECT` a commitment sees its location; who can `UPDATE` can change it. No extra surface.
- The UPDATE `WITH CHECK` encodes [BUSINESS_RULES MEM‑15a]: any member may *edit*, but only an organizer, the creator, or the owner may *soft-delete* (set `deleted_at`).
- Archived project → UPDATE `USING` still passes (member) but `app.tg_enforce_project_writable` raises; add `AND app.is_writable_project(project_id)` to `WITH CHECK` for RLS-level parity (belt & braces).
- Owner assignment validity (role, same project) → composite FK + `app.tg_commitment_owner_role_check` ([DATABASE_SCHEMA §7.1]).
- Status transitions → `app.tg_commitment_status_transition`.
- Cancelled commitments remain visible (only `deleted_at` hides rows).

**Attack notes:**
- Cross-project read: `GET /rest/v1/commitments?project_id=eq.<other>` → `app.is_member(other)` false → **0 rows**.
- Cross-project write: `POST /rest/v1/commitments {"project_id":"<other>", ...}` → `app.has_role(other,...)` false → **denied**.
- Viewer creates a commitment → role not in `{organizer,member}` → **denied**.
- Member soft-deletes a commitment they neither created nor own → UPDATE `WITH CHECK` fails → **denied**.
- Member sets `owner_member_id` to a `project_members` id **from another project** → composite FK `(project_id, owner_member_id)` has no matching row → **FK violation**.
- Member sets `owner_member_id` to a **viewer** in the same project → `app.tg_commitment_owner_role_check` → **exception** ([BUSINESS_RULES VAL‑12]).
- Member sets `owner_member_id` to a **non-member's `users.id`** → type/FK mismatch (`owner_member_id` references `project_members.id`, not `users.id`) → **FK violation**. *"Assigning another user as owner" is structurally impossible unless that user is already a member of the same project.*
- Member changes `project_id` to move the commitment → `app.tg_block_project_id_change` → **exception**.

---

### 5.6 `commitment_participants`

**Grants:** `anon`: none. `authenticated`: `SELECT, INSERT, DELETE, UPDATE`.

| Verb | Policy |
|------|--------|
| SELECT | `USING (app.is_member(project_id))` |
| INSERT | `WITH CHECK ( app.has_role(project_id,'{organizer,member}') AND app.is_writable_project(project_id) )` |
| UPDATE | `USING ( app.has_role(project_id,'{organizer,member}') )` `WITH CHECK ( app.has_role(project_id,'{organizer,member}') )` |
| DELETE | `USING ( app.has_role(project_id,'{organizer,member}') AND app.is_writable_project(project_id) )` |

**Notes:** hard delete is correct here (removing a participant). `member_id` may reference a viewer (a viewer can *attend*), but a viewer cannot add/remove participants. Member-active check at insert via `app.tg_participant_member_active_check`.

**Attack notes:**
- Viewer adds self to a commitment → not in `{organizer,member}` → **denied**.
- Member adds a `project_members` id from another project → composite FK `(project_id, member_id)` → **violation**.
- Member removes everyone from a costly commitment to distort balances → permitted (members are trusted with each other's plans, [§12](#12-residual-risks--accepted-design-decisions)); audited; `unallocated_cost` health finding fires.

---

### 5.7 `cost_shares`

**Grants:** `anon`: none. `authenticated`: `SELECT, INSERT, UPDATE, DELETE`.

| Verb | Policy |
|------|--------|
| SELECT | `USING (app.is_member(project_id))` |
| INSERT / UPDATE / DELETE | `USING / WITH CHECK ( app.has_role(project_id,'{organizer,member}') AND app.is_writable_project(project_id) )` |

**Attack notes:**
- A member sets their own `cost_shares` row to `basis='fixed', fixed_amount_minor=0` to avoid owing money → **permitted** by RLS (member edit right). This is a social/audit matter, not a security breach — it is logged in `audit_log`, visible in `v_member_balances`, and `tg_cost_share_basis_consistency` still enforces a coherent split. Flagged in [§12](#12-residual-risks--accepted-design-decisions).
- Cross-project `commitment_id`/`member_id` → composite FK violations.

---

### 5.8 `payments` — *payment-manipulation surface*

**Grants:** `anon`: none. `authenticated`: `SELECT, INSERT, UPDATE`. **No `DELETE`.**

| Verb | Policy |
|------|--------|
| SELECT | `USING ( app.is_member(project_id) AND deleted_at IS NULL )` |
| INSERT | `WITH CHECK ( app.has_role(project_id,'{organizer,member}') AND app.is_writable_project(project_id) AND amount_minor > 0 AND deleted_at IS NULL )` |
| UPDATE | `USING ( app.has_role(project_id,'{organizer,member}') AND deleted_at IS NULL )` `WITH CHECK ( app.has_role(project_id,'{organizer,member}') )` |
| DELETE | *no policy* + `REVOKE DELETE` |

**Trigger-enforced invariants** ([DATABASE_SCHEMA §4.8, §7.8b]): no create on a cancelled/deleted commitment; legal `status` transitions only; `paid_on <= today`; **a payment that has ever been `paid` cannot be soft-deleted** (`app.tg_payment_soft_delete_guard`); cancelling the parent commitment cancels only `scheduled` rows.

**Notes:**
- Members can create/edit payments for anyone (`paid_by_member_id` is not constrained to `auth.uid()`) — matches [BUSINESS_RULES PAY‑6] ("record who paid", org/member trusted). This is a deliberate trust decision, not an oversight — see [§12](#12-residual-risks--accepted-design-decisions).
- All financial *aggregates* (`gross_paid`, `outstanding`, balances) are **derived** ([DATABASE_SCHEMA §5]); there is no writable "amount paid" field to tamper with. The only levers are individual `payments` rows, every one of which is audited.

**Attack notes:**
- Non-member `POST /rest/v1/payments` for project X → `app.has_role(X,...)` false → **denied**.
- Viewer marks a payment `paid` → not in `{organizer,member}` → **denied**.
- Member fabricates `{"commitment_id":"<in project X>","project_id":"<project X>","status":"paid","amount_minor":80000,"paid_by_member_id":"<self>"}` to zero their balance → **permitted** by RLS (they're a member of X); recorded in `audit_log`; visible to all members in `v_member_balances`. Detection, not prevention, in MVP. [§12](#12-residual-risks--accepted-design-decisions).
- Member creates a payment with `project_id = X` but `commitment_id` from project Y → composite FK `(project_id, commitment_id) → commitments(project_id, id)` → **violation**.
- Member `DELETE /rest/v1/payments?id=eq.<a paid one>` → no DELETE policy → **denied**. `PATCH ... {"deleted_at":"now()"}` → `tg_payment_soft_delete_guard` → **exception**.
- Member changes `amount_minor` on a `paid` payment after the fact → permitted by RLS but **audited** (`before`/`after` captured); consider a trigger locking `amount_minor`/`paid_on` once `status='paid'` — recommended as a hardening follow-up ([§12](#12-residual-risks--accepted-design-decisions)).
- `project_id` change → `tg_block_project_id_change` → **exception**.

---

### 5.9 `tasks`

**Grants:** `anon`: none. `authenticated`: `SELECT, INSERT, UPDATE`. **No `DELETE`.**

| Verb | Policy |
|------|--------|
| SELECT | `USING ( app.is_member(project_id) AND deleted_at IS NULL )` |
| INSERT | `WITH CHECK ( app.has_role(project_id,'{organizer,member}') AND app.is_writable_project(project_id) AND deleted_at IS NULL )` |
| UPDATE | `USING ( app.has_role(project_id,'{organizer,member}') AND deleted_at IS NULL )` `WITH CHECK ( app.has_role(project_id,'{organizer,member}') AND ( deleted_at IS NULL OR app.is_organizer(project_id) OR created_by = app.current_member_id(project_id) OR assignee_member_id = app.current_member_id(project_id) ) )` |
| DELETE | *no policy* + `REVOKE DELETE` |

**Notes:** `commitment_id` (if set) must be same project → composite FK. Assignee must be an active organizer/member → `app.tg_task_assignee_role_check`. Soft-delete right mirrors commitments (organizer / creator / assignee).

**Attack notes:** assign a task to a viewer → trigger **exception**. Cross-project `commitment_id` → FK **violation**. Viewer creates a task → **denied**.

---

### 5.10 `milestones`

**Grants:** `anon`: none. `authenticated`: `SELECT, INSERT, UPDATE, DELETE`.

| Verb | Policy |
|------|--------|
| SELECT | `USING ( app.is_member(project_id) )` |
| INSERT / UPDATE / DELETE | `USING / WITH CHECK ( app.has_role(project_id,'{organizer,member}') AND app.is_writable_project(project_id) )` |

**Notes:** [BUSINESS_RULES MIL‑1] makes organizer creation a MUST and member creation a SHOULD; the policy above ships the SHOULD (members can create). To restrict to organizers, swap `has_role(...,'{organizer,member}')` → `app.is_organizer(project_id)`. No soft delete (milestones hard-delete). `commitment_id` link nulled by `tg_commitment_cancel_cascade`, not by the client.

---

### 5.11 `budgets` & `budget_category_targets`

**Grants:** `anon`: none. `authenticated`: `SELECT, INSERT, UPDATE, DELETE`.

| Verb | Policy (both tables) |
|------|---------------------|
| SELECT | `USING ( app.is_member(project_id) )` |
| INSERT / UPDATE / DELETE | `USING / WITH CHECK ( app.is_organizer(project_id) AND app.is_writable_project(project_id) )` |

**Notes:** budget is **project settings** → organizer-only ([BUSINESS_RULES MEM‑14]). `budget_category_targets.project_id` FK → `budgets(project_id)` so a target can't exist without a budget.

**Attack notes:** a member raises `total_target_minor` to clear a `budget_exceeded` finding → `app.is_organizer` false → **denied**. Only organizers move budget numbers.

---

### 5.12 `finding_dismissals`

**Grants:** `anon`: none. `authenticated`: `SELECT, INSERT, UPDATE, DELETE`.

| Verb | Policy |
|------|--------|
| SELECT | `USING ( app.is_member(project_id) )` |
| INSERT / UPDATE | `USING / WITH CHECK ( app.has_role(project_id,'{organizer,member}') AND app.is_writable_project(project_id) AND app.finding_is_dismissible(code) )` |
| DELETE | `USING ( app.has_role(project_id,'{organizer,member}') )` |

Also `app.tg_dismissal_not_blocker` as a second layer.

**Attack notes:** member inserts `{"code":"payment_overdue", ...}` to hide a blocker → `app.finding_is_dismissible('payment_overdue')` false → `WITH CHECK` fails → **denied** (and the trigger would raise). Member dismisses a finding in another project → `app.has_role(that project)` false → **denied**. Because findings are computed, a dismissal for a non-existent subject is inert.

---

### 5.13 `audit_log` — *audit-integrity surface*

**Grants:** `anon`: none. `authenticated`: `SELECT` only. `REVOKE INSERT, UPDATE, DELETE FROM authenticated, anon`.

| Verb | Policy |
|------|--------|
| SELECT | `USING ( project_id IS NOT NULL AND app.is_organizer(project_id) )` |
| INSERT | *no policy* — written only by `app.tg_audit_row()` (`SECURITY DEFINER`) and `service_role` |
| UPDATE | *no policy* + `REVOKE` + `app.tg_audit_immutable` raises unconditionally |
| DELETE | *no policy* + `REVOKE` + `app.tg_audit_immutable` raises unconditionally |

**Three independent layers** ([DATABASE_SCHEMA §7.12]):
1. **RLS:** no write policy for any client role.
2. **Privilege:** `REVOKE INSERT/UPDATE/DELETE` — even with `FORCE RLS` off by mistake, `authenticated` has no table privilege.
3. **Trigger:** `app.tg_audit_immutable` on `BEFORE UPDATE OR DELETE` → `RAISE EXCEPTION` always. This catches `service_role` too (triggers fire for it unless `session_replication_role='replica'`, which only migrations set, briefly, deliberately).

**Notes:**
- Members/viewers **cannot** read the audit log (it can contain `before`/`after` snapshots with other members' data). Organizer-only for MVP; widening to members is a product decision, not a security necessity.
- Global rows (`project_id IS NULL`, e.g. `users` changes) are readable by nobody via RLS — only `service_role`/support.
- `app.tg_audit_row()` is owned by a role whose sole elevated grant is `INSERT ON public.audit_log`; even a hijack of that path can only *append*.

**Attack notes:**
- Organizer `PATCH /rest/v1/audit_log?id=eq.X {"before":null}` → no UPDATE policy → **0 rows**; if forced, trigger **exception**.
- `DELETE /rest/v1/audit_log?project_id=eq.<mine>` → **denied** on all three layers.
- `SELECT app.tg_audit_row()` directly → `REVOKE EXECUTE FROM public`; and it errors on `TG_OP IS NULL` outside trigger context.
- A user tries to flood the audit log to obscure an action → they can only generate audit rows by performing real, audited mutations; there is no direct-write path.
- Member reads audit to see another member's payment history → `app.is_organizer` false → **0 rows**.

---

### 5.14 `currencies`

**Grants:** `anon`: none. `authenticated`: `SELECT`.

| Verb | Policy |
|------|--------|
| SELECT | `USING (true)` — reference data |
| INSERT/UPDATE/DELETE | *no policy* — seed/migration only |

---

### 5.15 Attachments (FUTURE — no table in MVP)

There is **no `attachments` table** in MVP ([DATABASE_SCHEMA §9.4]). File storage design is in [§8](#8-storage-policies). When an `attachments` table is added it follows the child-entity pattern exactly:

| Verb | Policy |
|------|--------|
| SELECT | `USING ( app.is_member(project_id) AND deleted_at IS NULL )` |
| INSERT/UPDATE | `WITH CHECK ( app.has_role(project_id,'{organizer,member}') AND app.is_writable_project(project_id) )` |
| DELETE | soft only; organizer / uploader |

with `(project_id, commitment_id)` / `(project_id, task_id)` composite FKs for the cross-project guarantee, and `tg_audit_row` / `tg_enforce_project_writable`.

---

## 6. RPC authorization

Client-callable RPCs live in `public` (PostgREST-exposed). `REVOKE EXECUTE ON FUNCTION ... FROM public; GRANT EXECUTE ... TO authenticated;` unless noted.

| RPC | EXECUTE | `SECURITY` | Internal authorization | Notes / attack surface |
|-----|---------|-----------|------------------------|------------------------|
| `public.accept_invitation(p_token text) → uuid` | `authenticated` | DEFINER, `search_path=''` | token must exist, `status='pending'`, `expires_at > now()`; **`lower(auth.email()) = lower(invitation.email)`**; then claim/create membership at `invitation.role` (never organizer) | generic errors (no existence oracle); idempotent for the same user; rate-limited at gateway; role bounded by `CHECK (role<>'organizer')` |
| `public.transfer_and_leave(p_project uuid, p_new_organizer_member uuid) → void` | `authenticated` | DEFINER | caller must be `app.is_organizer(p_project)`; `p_new_organizer_member` must be an `active` member of `p_project`; atomically promote target + set caller `status='removed'` | passes `tg_last_organizer_guard` because both writes happen before it re-evaluates; non-organizer caller → exception; cross-project target → "not found" |
| `public.get_project_health(p_project uuid) → setof ...` | `authenticated` | INVOKER | first statement: `IF NOT app.is_member(p_project) THEN RAISE insufficient_privilege; END IF;` | no writes; non-member gets an error before any row is read — no leak |
| `public.get_project_health_summary(p_project uuid) → record` | `authenticated` | INVOKER | same membership check | — |
| `public.get_invitation(p_token text) → record` | `authenticated` | DEFINER | returns `(project_name, inviter_name, role, status)` **only if** `lower(auth.email()) = lower(invitation.email)`; else generic "not found" | lets the invite screen render "You've been invited to X" without exposing the `invitations` table or enabling enumeration |
| `public.restore_project(p_project uuid)` | **not granted** to `authenticated` | DEFINER | `service_role` / support only in MVP | self-serve restore is [FUTURE] and needs its own policy carve-out |
| `app.is_member`, `app.has_role`, `app.is_organizer`, `app.current_member_id` | `authenticated` (SQL use); `app` schema **not** PostgREST-exposed | DEFINER | filter on `auth.uid()` | direct call (if it were exposed) reveals only the caller's own membership |

**RPCs are not a bypass.** Every one either performs its own membership/role check or is inherently safe (reveals only the caller's own facts). None accept a `role` or `member_id` that lets the caller act as someone else.

---

## 7. Views / exposed read-models

All in `app`, `GRANT SELECT TO authenticated`. `app` unexposed to PostgREST, so the client reads them via `supabase.from('app.v_...')`? — no: **the client-facing views are created in `public`** (or `app` is exposed for views only). Recommendation: **views in `public` with `security_invoker = true`**, helpers in `app` unexposed. Then base-table RLS ([§5](#5-table-by-table-policies)) automatically constrains every view row.

| View | Row visibility (inherited) |
|------|---------------------------|
| `v_commitment_financials`, `v_project_financials`, `v_budget_category_actuals`, `v_member_balances`, `v_timeline_events`, `v_my_projects` | `security_invoker` ⇒ exactly the rows the caller could `SELECT` from the underlying tables ⇒ members-only, non-deleted, cross-project-safe automatically |
| `v_member_directory` | `security_invoker = false` **by design** — joins `users` for `avatar_url`, which members otherwise can't read; the view body itself filters `WHERE app.is_member(project_id)` and selects only 6 non-sensitive columns |
| `v_admin_users`, `v_admin_user_memberships`, `v_admin_projects`, `v_admin_project_members`, `v_admin_invitations`, `v_admin_audit_log` | admin-only inspection views. They are `security_invoker = true`, base-table SELECT policies are gated by `app.is_platform_admin()`, and each view also filters with `WHERE app.is_platform_admin()`. |

`v_member_directory` is the one deliberate definer view; its safety rests on (a) the internal `is_member` filter and (b) the column whitelist. Documented and pgTAP-tested.

`public.get_admin_overview()` and `public.get_admin_project_health_summary(uuid)` are the admin RPCs in this phase. They are `SECURITY DEFINER`, use `SET search_path = ''`, validate `app.is_platform_admin()`, and return set-based operational data. Normal users can invoke the RPC names but receive `orchestr:platform_admin_required`; no rows are leaked.

---

## 8. Storage policies

Three buckets ([DATABASE_SCHEMA / TECHNICAL_ARCHITECTURE §13]). Policies on `storage.objects`, keyed by `bucket_id` and the first path segment.

### 8.1 `avatars` — public read, owner write

Path: `avatars/<user_id>/<filename>`.

| Verb | Policy on `storage.objects` |
|------|----------------------------|
| SELECT | `bucket_id = 'avatars'` — public (bucket is public) |
| INSERT / UPDATE / DELETE | `bucket_id = 'avatars' AND (storage.foldername(name))[1] = (select auth.uid())::text` |

### 8.2 `project-media` — private, membership-scoped

Path: `project-media/<project_id>/<filename>` (e.g. `cover.jpg`).

| Verb | Policy |
|------|--------|
| SELECT | `bucket_id = 'project-media' AND app.is_member(((storage.foldername(name))[1])::uuid)` |
| INSERT / UPDATE / DELETE | `bucket_id = 'project-media' AND app.has_role(((storage.foldername(name))[1])::uuid, '{organizer,member}') AND app.is_writable_project(((storage.foldername(name))[1])::uuid)` |

### 8.3 `attachments` — private, membership-scoped (bucket defined, unused in MVP)

Path: `attachments/<project_id>/<commitment_id>/<uuid>-<filename>`.

| Verb | Policy |
|------|--------|
| SELECT | `bucket_id = 'attachments' AND app.is_member(((storage.foldername(name))[1])::uuid)` |
| INSERT / UPDATE / DELETE | `bucket_id = 'attachments' AND app.has_role(((storage.foldername(name))[1])::uuid,'{organizer,member}') AND app.is_writable_project(...)` |

### 8.4 Storage notes & attack analysis

- **Invalid UUID in path** (`attachments/not-a-uuid/...`) → the `::uuid` cast raises → operation denied (fails closed).
- **Path traversal** (`../`) → Supabase Storage normalises object keys; `foldername` sees the normalised path; a crafted key that escapes its project folder does not parse to another project's UUID.
- **Non-member GET** `…/object/project-media/<projectB>/cover.jpg` → SELECT policy `app.is_member(projectB)` false → **403**.
- **Member uploads into another project's folder** → INSERT policy `app.has_role(<other>, ...)` false → **denied**.
- **Signed URLs** bypass RLS for their TTL. In MVP: (a) private objects are fetched via authenticated `download` (RLS-checked) — no signed URLs needed for in-app display; (b) signed URLs for email embeds are [FUTURE] and will be minted **only inside an Edge Function** after an explicit `is_member` check, with ≤ 1 h TTL.
- **Bucket config** enforces max file size and allowed MIME types (defence beyond RLS).
- **Orphaned objects** after project soft-delete: left in place (private, cheap); purge is a [FUTURE] `storage-gc` job.

---

## 9. Master policy matrix

Legend: **✔** allowed · **✔ᶜ** allowed with a row condition (organizer/creator/owner/assignee) · **trig** additionally gated by a trigger · **✘** denied · `org` = organizer, `mem` = member, `view` = viewer, `non` = non-member (authenticated), `anon` = unauthenticated.

| Table | Verb | anon | non | view | mem | org | Notes |
|-------|------|:---:|:---:|:---:|:---:|:---:|-------|
| **users** | SELECT | ✘ | self | self | self | self | co-member name/avatar via `v_member_directory` |
| | INSERT | ✘ | ✘ | ✘ | ✘ | ✘ | trigger on `auth.users` only |
| | UPDATE | ✘ | self | self | self | self | own profile |
| | DELETE | ✘ | ✘ | ✘ | ✘ | ✘ | Auth-admin only |
| **projects** | SELECT | ✘ | ✘ | ✔ | ✔ | ✔ | members of non-deleted projects |
| | INSERT | ✘ | ✔ | ✔ | ✔ | ✔ | any authed user; `status='draft'` forced; becomes org via trigger |
| | UPDATE | ✘ | ✘ | ✘ | ✘ | ✔ | settings, archive, soft-delete; trig: status, currency |
| | DELETE | ✘ | ✘ | ✘ | ✘ | ✘ | purge = service_role |
| **project_members** | SELECT | ✘ | own rows | ✔ | ✔ | ✔ | own membership everywhere + co-members |
| | INSERT | ✘ | ✘ | ✘ | ✘ | ✔ᶜ | `user_id IS NULL`, role ∈ {member,viewer} only |
| | UPDATE | ✘ | ✘ | self ᶜ | self ᶜ | ✔ | self: `display_name` + leave only (trig); org: role/status (trig: last-org, transition) |
| | DELETE | ✘ | ✘ | ✘ | ✘ | ✘ | removal = `status='removed'` |
| **invitations** | SELECT | ✘ | ✘ | ✘ | ✘ | ✔ | invitee path = `get_invitation` RPC |
| | INSERT | ✘ | ✘ | ✘ | ✘ | ✘ | Edge Function (`invitations-send`) only |
| | UPDATE | ✘ | ✘ | ✘ | ✘ | ✔ | revoke; accept = RPC |
| | DELETE | ✘ | ✘ | ✘ | ✘ | ✔ | optional |
| **commitments** / locations | SELECT | ✘ | ✘ | ✔ | ✔ | ✔ | non-deleted |
| | INSERT | ✘ | ✘ | ✘ | ✔ | ✔ | `status ∈ {idea,researching}` |
| | UPDATE | ✘ | ✘ | ✘ | ✔ | ✔ | trig: status, owner-role, project_id |
| | soft-DELETE | ✘ | ✘ | ✘ | ✔ᶜ | ✔ | creator/owner/org only |
| | hard DELETE | ✘ | ✘ | ✘ | ✘ | ✘ | purge |
| **commitment_participants** | SELECT | ✘ | ✘ | ✔ | ✔ | ✔ | |
| | INSERT/UPDATE/DELETE | ✘ | ✘ | ✘ | ✔ | ✔ | trig: member active |
| **cost_shares** | SELECT | ✘ | ✘ | ✔ | ✔ | ✔ | |
| | INSERT/UPDATE/DELETE | ✘ | ✘ | ✘ | ✔ | ✔ | trig: basis consistency |
| **payments** | SELECT | ✘ | ✘ | ✔ | ✔ | ✔ | non-deleted |
| | INSERT | ✘ | ✘ | ✘ | ✔ | ✔ | trig: not on cancelled commitment |
| | UPDATE | ✘ | ✘ | ✘ | ✔ | ✔ | trig: status, paid-immutability, no-future-paid_on |
| | soft-DELETE | ✘ | ✘ | ✘ | ✔ᶜ | ✔ᶜ | **only if never paid** (trig) |
| | hard DELETE | ✘ | ✘ | ✘ | ✘ | ✘ | purge |
| **tasks** | SELECT | ✘ | ✘ | ✔ | ✔ | ✔ | non-deleted |
| | INSERT/UPDATE | ✘ | ✘ | ✘ | ✔ | ✔ | trig: assignee role, status |
| | soft-DELETE | ✘ | ✘ | ✘ | ✔ᶜ | ✔ | creator/assignee/org |
| | hard DELETE | ✘ | ✘ | ✘ | ✘ | ✘ | purge |
| **milestones** | SELECT | ✘ | ✘ | ✔ | ✔ | ✔ | |
| | INSERT/UPDATE/DELETE | ✘ | ✘ | ✘ | ✔ | ✔ | (SHOULD: members; MUST: org) |
| **budgets** / **budget_category_targets** | SELECT | ✘ | ✘ | ✔ | ✔ | ✔ | |
| | INSERT/UPDATE/DELETE | ✘ | ✘ | ✘ | ✘ | ✔ | project settings |
| **finding_dismissals** | SELECT | ✘ | ✘ | ✔ | ✔ | ✔ | |
| | INSERT/UPDATE | ✘ | ✘ | ✘ | ✔ | ✔ | non-blocker codes only (policy + trig) |
| | DELETE | ✘ | ✘ | ✘ | ✔ | ✔ | un-dismiss |
| **audit_log** | SELECT | ✘ | ✘ | ✘ | ✘ | ✔ | project rows only; global rows nobody |
| | INSERT | ✘ | ✘ | ✘ | ✘ | ✘ | trigger / service_role |
| | UPDATE/DELETE | ✘ | ✘ | ✘ | ✘ | ✘ | never (RLS + REVOKE + trigger) |
| **currencies** | SELECT | ✘ | ✔ | ✔ | ✔ | ✔ | reference |
| | write | ✘ | ✘ | ✘ | ✘ | ✘ | seed only |

Platform admins add read-only inspection access through the admin views/RPC above: all users, all projects, invitations, project members, selected project financial summaries, and global audit rows. This does not grant unrestricted mutation, impersonation, password reset, billing access, hard deletion, or project intervention.

---

## 10. Principal capability summary

### Anonymous (`anon`)
- **SELECT/INSERT/UPDATE/DELETE: nothing** on any `public` table. No policy references `anon`; all table privileges revoked.
- Can only hit Supabase **Auth** endpoints (sign up / sign in) — not RLS-controlled.
- Cannot read `currencies`, cannot see that a project or invitation exists, cannot enumerate users.

### Authenticated non-member (of a given project)
- **SELECT:** own `users` row; own `project_members` rows (across all projects); `currencies`. **Nothing** belonging to projects they're not in — commitments, payments, members, invitations, audit, storage all return **0 rows / 403**.
- **INSERT:** a new `project` (becoming its organizer); nothing else.
- **UPDATE:** own `users` row; own `project_members.display_name` / leave. Nothing in projects they're not in.
- **DELETE:** nothing.

### Viewer (in a project)
- **SELECT:** everything in that project except `invitations` and `audit_log` — commitments, participants, cost shares, payments, tasks, milestones, budgets, finding dismissals, member directory, all derived views, `project-media` files.
- **INSERT / UPDATE / DELETE:** **nothing** in the project. Can update own `users` profile and `project_members.display_name`; can leave.
- Can be *named* as a commitment participant by an organizer/member (they attend) but cannot be an owner or assignee.

### Member (in a project)
- **SELECT:** as viewer.
- **INSERT:** commitments, participants, cost shares, payments, tasks, milestones, finding dismissals (non-blocker); `project-media` uploads.
- **UPDATE:** all of the above (any row, not just their own — [BUSINESS_RULES MEM‑15]); commitment/task status; assign owners/assignees (organizer/member targets only).
- **DELETE:** hard-delete participants / cost shares / milestones; **soft-delete** commitments & tasks they created/own/are assigned, payments they created/own **only if never paid**.
- **Cannot:** touch `projects` settings, `budgets`, `invitations`, `audit_log`, member roles; cannot dismiss blockers; cannot act in other projects.

### Organizer (in a project)
- **Everything a member can**, plus:
- **SELECT:** `invitations`, `audit_log` (project rows).
- **INSERT:** name-only `project_members` (role member/viewer); `budgets` / targets. Invitations via the Edge Function.
- **UPDATE:** `projects` (name, dates, timezone, cover, `health_config`, `status` incl. archive, `deleted_at` incl. soft-delete); any member's `role`/`status` (subject to last-organizer + transition triggers); `invitations` (revoke); `budgets`.
- **DELETE:** `invitations`; soft-delete any commitment/task/payment (payment only if never paid).
- **Cannot:** hard-delete anything; edit `audit_log`; change `currency` after money exists; remove/demote the last organizer; act in other projects.

---

## 11. Operations requiring Edge Functions or elevated privilege

| Operation | Why RLS/CRUD is insufficient | Mechanism | Authorisation performed |
|-----------|------------------------------|-----------|-------------------------|
| **Send an invitation** (create row + email) | external email API + secret; rate limiting; must not be spammable via direct REST | Edge Function `invitations-send` (`service_role`) | function verifies `app.is_organizer(projectId)` with a **caller-scoped** client before any `service_role` write |
| **Accept an invitation** | invitee is not yet a member — every needed write fails RLS | `public.accept_invitation()` `SECURITY DEFINER` RPC | token validity + `auth.email() = invitation.email`; role taken from the invitation (≤ member) |
| **Read an invitation pre-membership** | invitee has no SELECT on `invitations` | `public.get_invitation()` `SECURITY DEFINER` RPC | `auth.email() = invitation.email` |
| **Create a project's founding organizer** | creator has no `project_members` row to satisfy the INSERT policy | `app.tg_after_project_insert_create_member()` `SECURITY DEFINER` trigger | runs only in the creator's own INSERT transaction; hard-codes `user_id = auth.uid()`, `role='organizer'` |
| **`draft → active` auto-transition** | a `member` creating a commitment lacks UPDATE on `projects` | `app.tg_*_activates_project()` `SECURITY DEFINER` triggers | updates only `status`, only `draft→active` |
| **Count organizers for the last-organizer guard** | must see rows the caller may not under RLS | `app.tg_last_organizer_guard()` `SECURITY DEFINER` trigger | pure count; raises or allows |
| **Atomic transfer-and-leave** | ordering trap in the last-organizer guard | `public.transfer_and_leave()` `SECURITY DEFINER` RPC | caller must be organizer; target must be same-project member |
| **Write `audit_log`** | no client INSERT privilege by design | `app.tg_audit_row()` `SECURITY DEFINER` trigger (owner: `INSERT`-only role) | n/a — append-only |
| **Mirror new `auth.users` → `public.users`** | new user has no rights on `public.users` | `app.tg_handle_new_user()` `SECURITY DEFINER` trigger | n/a |
| **Restore a soft-deleted project** | deleted data is invisible to all client roles | `service_role` / support (self-serve = `public.restore_project`, [FUTURE]) | support process |
| **Hard purge** after recovery window | no DELETE policy anywhere | `service_role` scheduled job ([FUTURE]) | system |
| **AI / geocoding / notifications / iCal** | external APIs, secrets, cron | Edge Functions ([TECHNICAL_ARCHITECTURE §14.4], all [FUTURE]) | each self-authorises |

**Everything else — all day-to-day CRUD on commitments, payments, tasks, milestones, participants, cost shares, budgets, dismissals, member management — is direct Supabase CRUD under RLS. No Edge Function.**

---

## 12. Residual risks & accepted design decisions

| # | Risk / decision | Rationale | Mitigation / revisit |
|---|-----------------|-----------|----------------------|
| R1 | **Any member can create/edit/delete another member's commitments, payments, tasks, cost shares** (including setting their own cost share to 0, or fabricating a payment to zero their balance). | [BUSINESS_RULES MEM‑15] — collaborative planning assumes mutual trust among members; per-resource permissions are [FUTURE][AD‑6]. | Every mutation is in `audit_log` (organizer-visible); balances/financials are derived and transparent to all members; add per-field locks or per-resource ACLs when the product needs them. |
| R2 | **`amount_minor` / `paid_on` of an already-`paid` payment can be edited by a member** (RLS allows; only audited). | financial history preservation focuses on *non-deletion*; edits are rarer and audited. | **Recommended hardening:** a trigger freezing `amount_minor`, `paid_on`, `paid_by_member_id`, `commitment_id` once `status` has ever been `paid` (allow only `status → waived/cancelled` and `notes`). Add before launch if cheap. |
| R3 | **Organizer can read `audit_log` before/after snapshots** containing other members' data. | organizers are the project's trust root and already see all project data. | acceptable; if audit ever stores anything an organizer shouldn't see, redact in `app.tg_audit_row()`. |
| R4 | **Members are trusted with `finding_dismissals`** — one member can dismiss a warning others rely on. | warnings are advisory; blockers are undismissable. | dismissals are audited and per-(code,subject); a re-triggered finding reappears. |
| R5 | **Forwarded invitation link** — mitigated by the `auth.email() = invitation.email` check, but that assumes the org invited the right address. | standard email-invite model. | organizer can revoke; audit shows acceptance. |
| R6 | **`service_role` compromise = total compromise.** | inherent to Supabase. | key only in Edge Function env + CI secrets; `tg_audit_immutable` still blocks audit tampering even for `service_role`; monitor function logs. |
| R7 | **`v_member_directory` is a definer view.** | members legitimately need co-members' names/avatars; `users` stays locked. | column whitelist + internal `is_member` filter; pgTAP test asserts no extra columns and no cross-project rows. |
| R8 | **Self-serve project restore not available** — a mistaken delete needs support. | keeps [BUSINESS_RULES PRJ‑23] absolute and RLS simple for MVP. | `public.restore_project` + a "Trash" policy carve-out is a small [FUTURE] addition. |
| R9 | **No rate limiting in RLS** (invitation acceptance, project creation, payment creation). | RLS can't rate-limit. | gateway / Edge Function limits on `accept_invitation` and `invitations-send`; consider a per-user project-creation cap if abused. |

---

## 13. Test plan (pgTAP — runs in CI on `supabase db reset`)

Fixtures: `userA` (organizer of P1, member of P2), `userB` (member of P1), `userC` (viewer of P1), `userD` (organizer of P2, no relation to P1), `userE` (authenticated, no memberships), plus name-only member `nameOnly` in P1. P3 is soft-deleted; P4 is archived.

**Assertion families (≈ one test per matrix cell + attack):**

1. **Cross-project isolation** — for every table: `userD` (P2 only) `SELECT/INSERT/UPDATE/DELETE` against P1 rows ⇒ 0 rows / error. `userE` ⇒ same. `anon` ⇒ same.
2. **Role gradient** — `userC` (viewer) write to every P1 table ⇒ denied; `userB` (member) ⇒ allowed where the matrix says, denied for `projects`/`budgets`/`invitations`/`audit_log`; `userA` (organizer) ⇒ the organizer column.
3. **Self-enrolment** — `userE` `INSERT project_members {project_id:P1, user_id:userE, role:*}` ⇒ denied (every role value). `userE` `INSERT project_members {project_id:P1, user_id:NULL}` ⇒ denied (not organizer).
4. **Role escalation** — `userB` `UPDATE project_members SET role='organizer' WHERE id = <own>` ⇒ exception. `userC` likewise. `userB` `UPDATE ... SET role='organizer' WHERE id = <userC row>` ⇒ 0 rows.
5. **Last-organizer** — `userA` demote self in P1 (sole organizer) ⇒ exception; `userA` `UPDATE status='removed'` self ⇒ exception; `transfer_and_leave(P1, userB_member)` ⇒ success, `userB` now organizer, `userA` removed.
6. **Owner assignment** — `userB` set `commitments.owner_member_id` to: a P2 member id ⇒ FK error; `userC`'s (viewer) member id ⇒ trigger exception; `userE`'s `users.id` ⇒ FK error; `userB`'s own member id ⇒ success.
7. **Invitation abuse** — `userE` `INSERT/UPDATE invitations` ⇒ denied; `userB` `SELECT invitations` in P1 ⇒ 0 rows; `accept_invitation` with wrong-email account ⇒ error; with correct account ⇒ membership at invited role; second accept (same user) ⇒ idempotent; (other user) ⇒ error; expired/revoked token ⇒ generic error.
8. **Payment manipulation** — `userC` `INSERT payments` ⇒ denied; `userD` `INSERT payments` for P1 ⇒ denied; `userB` `INSERT payments {project_id:P1, commitment_id:<P2 commitment>}` ⇒ FK error; `userB` soft-delete a `paid` payment ⇒ trigger exception; hard `DELETE` ⇒ denied.
9. **Audit integrity** — `userA` (organizer) `UPDATE/DELETE audit_log` ⇒ denied (RLS) and exception (trigger); `userB` `SELECT audit_log` ⇒ 0 rows; `userA` `SELECT audit_log` for P1 ⇒ rows; direct `SELECT app.tg_audit_row()` ⇒ error/permission denied.
10. **Soft-deleted rows** — after soft-deleting a P1 commitment: `userA`/`userB` `SELECT` ⇒ excluded; `UPDATE` ⇒ 0 rows. P3 (deleted project): all users ⇒ project + all children invisible.
11. **Platform admin** — anon cannot read admin views; normal authenticated users get 0 rows from admin views, cannot update their own `platform_role`, and cannot run `get_admin_overview()` successfully; admins can read approved admin views and global audit.
12. **Archived project** (P4) — `SELECT` by members ⇒ works; any child `INSERT/UPDATE/DELETE` ⇒ exception (`tg_enforce_project_writable`); `projects UPDATE status='active'` by organizer ⇒ works (un-archive).
13. **Direct REST parity** — a subset of the above re-run as raw `http` calls with each user's JWT and with the anon key, asserting identical outcomes (proves no frontend dependency).
14. **Storage** — `userD` download `project-media/P1/...` ⇒ 403; `userC` upload to `project-media/P1/...` ⇒ denied; `userB` upload ⇒ ok; malformed-UUID path ⇒ denied.
14. **Helper safety** — `anon` `EXECUTE app.is_member` ⇒ denied; `authenticated` `EXECUTE app.is_member('<any project>')` ⇒ returns only a boolean about self; `app` schema not in PostgREST introspection.
```
