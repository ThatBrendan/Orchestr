# Production Technical Architecture

**Status:** Draft for review
**Date:** 2026-09-04
**Source material:** [`docs/PROTOTYPE_ANALYSIS.md`](./PROTOTYPE_ANALYSIS.md), [`docs/DOMAIN_MODEL.md`](./DOMAIN_MODEL.md), [`docs/BUSINESS_RULES.md`](./BUSINESS_RULES.md)
**Scope:** the production technical architecture for the MVP. Defines how the app is built, not what it does.
**Non-goals:** no implementation, no migrations, no component code, no schema DDL. This document is detailed enough to start building from without re-opening architectural questions.

**Stack (fixed):** Vue 3 · TypeScript · Tailwind CSS · Supabase (PostgreSQL · Auth · Row Level Security · Storage · Edge Functions).

---

## 0. Guiding principles

1. **The database is the backend.** Business rules, invariants, and derived calculations ([BUSINESS_RULES §GC‑7]) live in PostgreSQL — as constraints, triggers, functions, and views — not in the browser. The frontend renders and orchestrates; it never *owns* a rule.
2. **Talk to Supabase directly for authenticated CRUD.** No repository pattern, no generic `ApiClient`, no hand-rolled REST layer, no DTO-mapping tier. A thin typed service module per aggregate is the only abstraction, and it exists for query-key centralisation and testability, not indirection.
3. **Edge Functions are the exception, not the rule.** They exist only for work that *cannot* or *must not* happen in the browser (§14). If a thing can be a Postgres function guarded by RLS, it is a Postgres function.
4. **RLS is the authorization layer.** Every access decision is enforced by the database. The frontend's permission checks are for UX affordance only and are never trusted.
5. **Derived data is computed once, server-side, and cached client-side.** Budget, timeline, health, balances, progress — one canonical SQL definition each, consumed read-only.
6. **Types flow from the database outward.** Generated Supabase types are the root; domain and DTO types layer on top.

### Where logic lives

| Logic | Home | Never in |
|-------|------|----------|
| Field invariants (VAL‑1…23) | DB `CHECK` / `NOT NULL` / `UNIQUE` / FK | — |
| Cross-row rules (last organizer, currency immutability, status-transition legality, equal-split recompute, draft→active, archived read-only, soft-delete cascade) | DB triggers / functions | frontend |
| Derived reads (budget, timeline, health, balances, progress, payment_status) | DB views + set-returning functions | frontend (frontend only formats) |
| Privileged writes (accept invitation, claim member) | DB `SECURITY DEFINER` RPC | frontend |
| External I/O (transactional email, AI, geocoding) | Edge Functions | frontend, DB |
| Authorization | RLS policies + helper functions | frontend (advisory only) |
| Form UX validation, formatting, interaction, layout, routing | Frontend | — |
| Money formatting, timezone display | Frontend (pure, from server values) | — |

---

## 1. Frontend architecture

- **Build:** Vite + Vue 3 (`<script setup>`, Composition API only) + TypeScript in `strict` mode. `vue-tsc` in CI.
- **Rendering:** SPA. No SSR for MVP (the app is behind auth, SEO is irrelevant, and SSR adds a server tier we deliberately don't want). Static hosting + Supabase.
- **Styling:** Tailwind CSS. The prototype's design tokens (`--paper`, `--ink`, `--accent`, …) become the Tailwind theme (`tailwind.config.ts` `theme.extend.colors`) plus a small `base` layer. Fonts (Inter, Space Grotesk) self-hosted via `@fontsource` (no runtime Google Fonts dependency). The prototype's visual design is preserved as-is (no redesign).
- **Server state:** `@tanstack/vue-query` — caching, deduplication, background refetch, invalidation, optimistic updates, retry. This replaces the prototype's "rebuild everything on every change" model and removes any need to hand-write a cache.
- **Client state:** Pinia — session/auth, active-project context, and cross-cutting UI (toasts, command palette, slide-over stack). Small.
- **Data flow:** `component → composable → (vue-query) → service → supabase-js → PostgREST/RPC → Postgres (RLS)`.
- **Module boundaries:** `views/` (routed screens) → `components/` (presentational + small container components) → `composables/` (data + behaviour) → `services/` (Supabase calls) → `lib/` (client singletons). Dependencies point downward only.
- **No global event bus.** Cross-component coordination is via Pinia stores or vue-query cache.
- **Accessibility & responsive:** the prototype's two breakpoints (`md`) are kept; components use Headless UI (Vue) for focus-trap/aria on modal, slide-over, menu, tabs — fixing the prototype's missing focus management.

---

## 2. Component architecture

### 2.1 Layers

| Layer | Location | Responsibility | May call |
|-------|----------|----------------|----------|
| **UI primitives** | `components/ui/` | Design-system atoms: `AppButton`, `AppBadge`, `StatusBadge`, `SeverityIcon`, `AppModal`, `AppSlideOver`, `AppTabs`, `MoneyText`, `DateText`, `ProgressBar`, `StatTile`, `Skeleton`, `EmptyState`, `FieldError`. Pure props/emits, no data access. | nothing |
| **Domain components** | `components/<aggregate>/` | Render one domain concept: `CommitmentRow`, `CommitmentTable`, `CommitmentSlideOver`, `PaymentList`, `BudgetSummary`, `TimelineView`, `HealthFindingList`, `MemberList`, `CostSplitEditor`, `AddCommitmentWizard`. Compose primitives. Take typed domain data as props; emit intent events. | UI primitives, `composables/useMoney`, `useProjectTime` |
| **Container views** | `views/` | One per route. Wire composables to domain components, own page-level loading/error/empty states, handle route params. | composables, domain + UI components |
| **Layout** | `components/layout/` | `AppShell`, `AppSidebar`, `AppBottomNav`, `AppTopBar`, `CurrentProjectSwitcher`. Structural chrome from the prototype. | composables (`useAuth`, `useProjectContext`), UI primitives |

### 2.2 Rules

- **CRUD-2 [rule]** Domain components are **dumb**: they never import `services/` or `lib/supabase`. All data and mutations arrive as props/events, sourced by the parent view via composables. This keeps them storybook-able and testable.
- Container views are the only place `isPending` / `isError` / empty-check branching happens (§17).
- The prototype's screens map 1:1 to views (see §3). The prototype's `renderActivityPanel` → `CommitmentSlideOver`; `renderWizard` → `AddCommitmentWizard` (a real, persisting form — §18).
- Wizard "Type" step resolves per [BUSINESS_RULES COM‑9]: Activity/Booking → commitment; Task → task; Payment → payment-on-commitment. The wizard is a stepper component with a discriminated-union model.
- Every list has an explicit `EmptyState` (the prototype has none) and a `Skeleton` variant.

---

## 3. Routing

`vue-router` (history mode), route-level code splitting (`() => import(...)`), typed routes via `unplugin-vue-router` or a hand-maintained `RouteName` enum.

### 3.1 Route table

| Path | Name | View | Guard | Notes |
|------|------|------|-------|-------|
| `/login`, `/auth/callback`, `/invite/:token` | `auth.*` | `views/auth/*` | `guestOrAny` | magic-link callback; invite acceptance |
| `/` | `dashboard` | `DashboardView` | `requireAuth` | prototype Dashboard |
| `/projects` | `projects` | `ProjectsView` | `requireAuth` | prototype Projects list |
| `/projects/:projectId` | `project` | `ProjectLayout` (nested) | `requireAuth` + `requireMembership` | redirects to `…/overview` |
| `/projects/:projectId/overview` | `project.overview` | `OverviewTab` | ↑ | |
| `/projects/:projectId/commitments` | `project.commitments` | `CommitmentsTab` | ↑ | `?commitment=<id>` opens the slide-over (deep-linkable — fixes prototype gap) |
| `/projects/:projectId/budget` | `project.budget` | `BudgetTab` | ↑ | |
| `/projects/:projectId/timeline` | `project.timeline` | `TimelineTab` | ↑ | |
| `/projects/:projectId/people` | `project.people` | `PeopleTab` | ↑ | |
| `/projects/:projectId/health` | `project.health` | `HealthTab` | ↑ | |
| `/projects/:projectId/settings` | `project.settings` | `ProjectSettingsView` | ↑ + `requireRole('organizer')` | prototype "Project settings" button |
| `/calendar` | `calendar` | `CalendarView` | `requireAuth` | global timeline ([BUSINESS_RULES TML‑6], SHOULD) |
| `/settings` | `settings` | `SettingsView` | `requireAuth` | prototype Settings (now editable) |
| `/:pathMatch(.*)*` | `not-found` | `NotFoundView` | — | |

### 3.2 Guards (`router/guards.ts`)

- **`requireAuth`** — awaits session hydration (Pinia `auth.ready`); redirects to `/login?redirect=…` if unauthenticated.
- **`requireMembership`** — prefetches the current user's `project_members` row for `:projectId` via vue-query; 404s if none (RLS would return empty anyway); populates `useProjectContext`.
- **`requireRole(role)`** — checks the cached membership role; redirects to the project overview with a toast if insufficient. **Advisory only** — RLS is the real gate.
- Guards never bypass loading: they suspend navigation until the needed query resolves, showing the global route progress bar.
- URL is the source of truth for `view` / `projectId` / `projectTab` / open slide-over — replacing the prototype's `state` object and fixing "everything resets on refresh".

---

## 4. State management

### 4.1 Split

| Kind | Tool | Examples |
|------|------|----------|
| **Server/cache state** | `@tanstack/vue-query` | projects, commitments, payments, tasks, members, budget, timeline, health findings |
| **Session state** | Pinia `useAuthStore` | `user`, `session`, `ready`, `signOut()` |
| **Active-project context** | Pinia `useProjectContextStore` | `projectId`, `membership` (role, member_id), `project` summary, `currency`, `timezone` — hydrated by `requireMembership`, cleared on leave |
| **Ephemeral UI** | Pinia `useUiStore` or local `ref` | toasts, slide-over stack, wizard open/step, command palette, theme |

- **No domain data in Pinia.** Pinia holds identity, the current-project pointer, and UI. Everything queryable lives in the vue-query cache.
- **Derived UI values** (e.g. "3 things need attention") are `computed` off query results, never stored.

### 4.2 Query key convention

```
['project', projectId]                          // project summary
['project', projectId, 'members']
['project', projectId, 'commitments', filters?]
['commitment', commitmentId]                     // detail incl. participants, cost shares, payments
['project', projectId, 'tasks', filters?]
['project', projectId, 'milestones']
['project', projectId, 'budget']                 // targets
['project', projectId, 'financials']             // derived rollup (view/RPC)
['project', projectId, 'balances']               // derived per-member
['project', projectId, 'timeline']               // derived
['project', projectId, 'health']                 // derived findings
['me', 'projects']                               // dashboard/projects list
['me', 'calendar']                               // global timeline
```

- **Invalidation rules** are documented per mutation in the service module. A commitment write invalidates `['commitment', id]`, `['project', projectId, 'commitments']`, `'financials'`, `'balances'`, `'timeline'`, `'health'`. This is the one place the "derived things depend on base things" graph is encoded on the client.
- `staleTime`: 30 s for lists, 0 for derived views (always refetch on focus), `Infinity` + manual invalidation for reference data (currencies, timezones).

### 4.3 Optimistic updates

- Used for low-risk toggles only: task done/undone, finding dismiss/snooze, participant add/remove. `onMutate` snapshots, `onError` rolls back, `onSettled` invalidates.
- Money and status changes are **not** optimistic — they wait for the server (and its triggers) to confirm.
- Optimistic-concurrency ([BUSINESS_RULES GC‑6], SHOULD): updates carry `updated_at` as `.eq('updated_at', knownValue)`; zero rows affected → `ConflictError` → refetch + surface "someone changed this".

---

## 5. Composables

Composables are the **only** thing views use for data. Each wraps vue-query + a service, exposes typed refs, and encapsulates invalidation.

| Composable | Responsibility |
|------------|----------------|
| `useSupabase()` | returns the typed client singleton (thin; mostly for tests to inject) |
| `useAuth()` | `user`, `session`, `isAuthenticated`, `signInWithOtp`, `signInWithPassword`, `signOut`; subscribes to `onAuthStateChange` once at app root |
| `useProjectContext()` | current `projectId`, `membership`, `project`, `currency`, `timezone`; used by guards + layout |
| `usePermissions()` | pure, synchronous: `can('commitment.edit')`, `can('project.settings')`, `isOrganizer` — derived from `membership.role` and the [MEM‑14] matrix, encoded once in `lib/permissions.ts`. **UX only.** |
| `useProjects()` / `useProject(id)` | list + detail, create/archive/delete mutations |
| `useMembers(projectId)` | list; invite / change-role / remove / leave mutations |
| `useCommitments(projectId, filters)` / `useCommitment(id)` | list + detail (with nested participants, cost shares, payments); CRUD; status transition |
| `usePayments(commitmentId)` | list + CRUD; mark paid / waive / cancel |
| `useCostShares(commitmentId)` | read + edit split |
| `useTasks(projectId, filters)` / `useTask(id)` | CRUD, complete/reopen |
| `useMilestones(projectId)` | CRUD |
| `useBudget(projectId)` | targets read + edit |
| `useFinancials(projectId)` | **derived**: totals, outstanding, variance, category actuals (read-only) |
| `useBalances(projectId)` | **derived**: per-member balances (read-only) |
| `useTimeline(projectId)` / `useCalendar()` | **derived** event stream (read-only) |
| `useHealth(projectId)` | **derived** findings + rollup; dismiss/snooze mutations |
| `useMoney()` | `format(amount, currency)`, `parse(input, currency)` → minor units; **formatting only**, no arithmetic on business figures |
| `useProjectTime()` | render `starts_at` etc. in `project.timezone`; compute "today" in project tz for display; wraps a date lib (Luxon or `@internationalized/date`) |
| `useToast()` | queue success/error notifications |
| `useErrorHandler()` | maps `AppError` → toast/inline; used by vue-query defaults |

**Rules:**
- A composable never contains a business calculation. `useFinancials` calls the server; it does not sum payments in JS.
- Composables are the invalidation authority — a component calling `mutate()` never touches the query cache directly.

---

## 6. Service layer

Thin, typed, one module per aggregate in `src/services/`. A service function is a **single Supabase call plus error mapping**. No composition, no caching, no business logic.

```
services/
  projects.ts     listMyProjects, getProject, createProject, updateProject, archiveProject, deleteProject
  members.ts      listMembers, updateMemberRole, removeMember, leaveProject, inviteMember*
  invitations.ts  getInvitation, acceptInvitation (→ rpc)
  commitments.ts  listCommitments, getCommitment, createCommitment, updateCommitment,
                  setCommitmentStatus, deleteCommitment, setParticipants
  payments.ts     listPayments, createPayment, updatePayment, setPaymentStatus, deletePayment
  costShares.ts   getCostShares, upsertCostShares
  tasks.ts        listTasks, getTask, createTask, updateTask, setTaskStatus, deleteTask
  milestones.ts   listMilestones, createMilestone, updateMilestone, deleteMilestone
  budget.ts       getBudget, upsertBudget, upsertCategoryTargets
  derived.ts      getFinancials, getBalances, getTimeline, getCalendar, getHealth   (view/RPC reads)
  storage.ts      uploadAvatar, uploadProjectMedia, getSignedUrl
```

- `inviteMember*` is the one function that calls an Edge Function (`functions.invoke('invitations-send')`); everything else is `supabase.from(...)` or `supabase.rpc(...)`.
- Each function returns `Promise<T>` on success and throws a typed `AppError` (§16) on failure — never returns `{ data, error }` to callers.
- Query keys are **not** defined here — they live next to composables (`composables/keys.ts`) to keep services free of caching concerns.
- Services take the client via parameter default (`client = supabase`) so tests inject a mock.
- **When a service function would just be `supabase.from('x').select()` with no error nuance, it is still kept** — for one consistent seam — but it stays a one-liner. This is the maximum abstraction permitted.

---

## 7. Type definitions

```
types/
  database.ts   // GENERATED: `supabase gen types typescript --linked` — tables, views, functions, enums
  domain.ts     // hand-written: ergonomic domain types built FROM database.ts
  derived.ts    // hand-written: HealthFinding, TimelineEvent, ProjectFinancials, MemberBalance DTOs
                //   (shapes returned by views/RPCs — kept in sync with SQL, checked in tests)
  forms.ts      // input types for create/update, derived from validation schemas (§18)
  permissions.ts// PermissionKey union
  index.ts      // re-exports
```

- **`database.ts` is regenerated in CI** on every migration and committed; a drift check fails the build.
- Domain types example intent: `Commitment = Tables<'commitments'> & { owner: MemberRef | null; participants: MemberRef[]; costShares: CostShare[]; payments: Payment[]; paymentStatus: PaymentStatus /* derived, from view */ }`.
- Enums (`commitment_status`, `commitment_kind`, `payment_type`, `payment_status`, `member_role`, `member_status`, `project_status`, `task_status`, `finding_severity`) are defined **as Postgres enums**, surfaced through `database.ts`, and re-exported from `domain.ts`. Single source.
- No `any`. `unknown` at boundaries (Edge Function payloads) narrowed by a schema parse.
- Money is a branded type `Minor<Currency>` (a `number` brand) to prevent mixing currencies or passing major units by accident.

---

## 8. Supabase client architecture

### 8.1 Browser client (`src/lib/supabase.ts`)

- **One singleton**, `createClient<Database>(url, anonKey, { auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true, flowType: 'pkce' } })`.
- Typed with the generated `Database` — every `.from()`, `.rpc()` is type-checked.
- The **anon key is public** by design; RLS protects data. No service-role key ever reaches the bundle (build fails if `SERVICE_ROLE` appears in client env).
- `onAuthStateChange` is wired **once** in `useAuth` at app root → updates `useAuthStore` → drives router guards and query cache reset on sign-out (`queryClient.clear()`).
- Realtime: a single channel per open project (`project:<id>`) subscribing to `postgres_changes` on that project's rows, mapped to `queryClient.invalidateQueries`. **SHOULD** for MVP (keeps collaborators fresh); full presence/co-editing is FUTURE.

### 8.2 Edge Function client

- Each Edge Function creates its own client. Two variants:
  - **Caller-scoped** — `createClient(url, anonKey, { global: { headers: { Authorization: req.headers.authorization } } })` to act *as the user* (RLS applies). Used to authorize the request.
  - **Service-scoped** — `createClient(url, serviceRoleKey)` for the privileged step only, after authorization passes. Never exposed, never logs the key.

### 8.3 Local dev client

- `supabase start` provides local URL + keys; `.env.development` points at `http://localhost:54321`.

---

## 9. Database access patterns

### 9.1 Reads

- **Nested selects** to avoid N+1: 
  `commitments?select=*,owner:project_members!owner_member_id(id,display_name),participants:commitment_participants(member:project_members(id,display_name)),payments(*)`.
- **Derived reads** go through a **view or set-returning function**, never assembled client-side:
  - `from('project_financials').select('*').eq('project_id', id).single()`
  - `from('timeline_events').select('*').eq('project_id', id).order('occurs_at')`
  - `rpc('get_project_health', { p_project_id: id })`
  - `rpc('get_member_balances', { p_project_id: id })`
- **Pagination:** `.range(from, to)` + a count header for commitments/tasks lists (SHOULD; the prototype assumed tiny lists). Default page size 50.
- **Filtering/sorting** is pushed to PostgREST (`.eq`, `.in`, `.order`), not done in JS.
- **Soft-deleted rows** are excluded by RLS/`WHERE deleted_at IS NULL` in every view; base-table reads add `.is('deleted_at', null)`.

### 9.2 Writes

- **Plain `insert` / `update` / `delete`** for straightforward authenticated CRUD, guarded by RLS + triggers. Example: creating a commitment is `insert` — a trigger sets `created_by`, defaults status, and (per [PRJ‑10]) flips the project to `active`.
- **Soft delete = `update { deleted_at: now() }`**; a trigger cascades to children ([COM‑43], [PRJ‑21]).
- **`upsert`** for `cost_shares` (replace-set semantics) and `budget_category_targets`.
- **`rpc(...)`** for operations that need privilege or multi-statement atomicity the client can't express safely:
  - `accept_invitation(p_token)` — `SECURITY DEFINER`; validates token, claims/creates the member, sets `user_id`.
  - `transfer_and_leave(p_new_organizer_member_id)` — atomic promote + self-remove honouring [PRJ‑7].
- **Batch writes** (e.g. set participants) use a single `rpc` or a `POST` with an array, wrapped in one transaction server-side — not a loop of round-trips.

### 9.3 What is deliberately NOT abstracted

- No query builder wrapper, no ORM, no `BaseRepository`. `supabase-js` *is* the data layer.
- No client-side join engine. If a screen needs data from three tables, that's one nested `select` or one view.

---

## 10. Authentication

- **Provider:** Supabase Auth. MVP methods: **email OTP / magic link** (primary) + **email + password** (optional). OAuth providers are FUTURE.
- **Profile mirror:** `public.users` row per `auth.users`, created by an `on_auth_user_created` trigger (`handle_new_user`) copying `id`, `email`, and defaulting `display_name`, `timezone`, `default_currency`, `notification_prefs`. The app reads/writes `public.users`, never `auth.users` directly.
- **Session lifecycle:** PKCE flow; `detectSessionInUrl` handles the magic-link callback at `/auth/callback`; `autoRefreshToken` keeps it alive; `useAuth` exposes `ready` so guards wait for hydration (no flash of login screen).
- **Sign-out:** `supabase.auth.signOut()` → `queryClient.clear()` → Pinia reset → redirect to `/login`.
- **Invite acceptance:** `/invite/:token` → if unauthenticated, send an OTP to the invited email, then on return call `rpc('accept_invitation', { p_token })` → redirect into the project. The email that carries the link is sent by the `invitations-send` Edge Function.
- **Account deletion / last-organizer conflict** ([VAL‑39]) is enforced by a DB check on the delete path; the UI surfaces the reason.

---

## 11. Authorization

- **Model:** project-scoped RBAC with three roles — `organizer`, `member`, `viewer` — held on `project_members.role` ([DOMAIN_MODEL §5.3], [BUSINESS_RULES MEM‑12…15]).
- **Enforcement point:** **RLS in PostgreSQL** (§12). Every table. Deny by default.
- **Frontend mirror:** `lib/permissions.ts` encodes the [MEM‑14] matrix as `Record<PermissionKey, (role) => boolean>`; `usePermissions()` exposes it for hiding/disabling controls. If the frontend and RLS ever disagree, RLS wins and the user sees a `PermissionError` toast — the frontend check is purely to avoid dead-end clicks.
- **Edge Functions** re-authorize independently: they load the caller's membership with a caller-scoped client and check role **before** doing any service-role work.
- **No admin/superuser role in the app.** Support/ops act through Supabase dashboard with audit.

---

## 12. RLS strategy

### 12.1 Foundations

- **RLS enabled on every table** in `public`. No table is readable without a policy.
- **Helper functions** (schema `app`, `SECURITY DEFINER`, `STABLE`, `SET search_path = ''`) — these bypass RLS internally to answer membership questions without policy recursion:
  - `app.current_member(p_project uuid) → project_members` (the caller's active membership, or null)
  - `app.is_member(p_project uuid) → boolean`
  - `app.has_role(p_project uuid, p_roles text[]) → boolean`
  - `app.is_organizer(p_project uuid) → boolean`
- **`project_members` recursion:** its own policies must not call a helper that selects from `project_members` under RLS. The helpers are `SECURITY DEFINER` precisely to break this cycle; `project_members` SELECT policy is `user_id = auth.uid() OR app.is_member(project_id)`.

### 12.2 Policy shape per table

| Table | SELECT | INSERT | UPDATE | DELETE |
|-------|--------|--------|--------|--------|
| `users` | `id = auth.uid()` (+ members of shared projects may read `id, display_name, avatar_url` via a restricted view) | via trigger only | `id = auth.uid()` | never (soft-deactivate) |
| `projects` | `app.is_member(id)` | `auth.uid() IS NOT NULL` | `app.is_organizer(id)` | `app.is_organizer(id)` (soft) |
| `project_members` | `user_id = auth.uid() OR app.is_member(project_id)` | `app.is_organizer(project_id)` (name-only add) / RPC (invite accept) | `app.is_organizer(project_id)`; self may update own `display_name` | `app.is_organizer(project_id) OR user_id = auth.uid()` (leave); trigger enforces last-organizer |
| `invitations` | `app.is_organizer(project_id)` | `app.is_organizer(project_id)` or member-invite flag | `app.is_organizer(project_id)` | `app.is_organizer(project_id)` |
| `commitments`, `commitment_participants`, `cost_shares`, `payments`, `tasks`, `milestones`, `budgets`, `budget_category_targets` | `app.is_member(project_id)` (and `deleted_at IS NULL`) | `app.has_role(project_id, '{organizer,member}')` | `app.has_role(project_id, '{organizer,member}')` | `app.has_role(project_id, '{organizer,member}')` — trigger restricts hard-delete/soft-delete per [MEM‑15a] |
| `finding_dismissals` | `app.is_member(project_id)` | `app.has_role(project_id,'{organizer,member}')` | same | same |
| `audit_log` | `app.is_organizer(project_id)` | trigger/service only | never | never |
| `health_config` | `app.is_member(project_id)` | `app.is_organizer(project_id)` | `app.is_organizer(project_id)` | `app.is_organizer(project_id)` |

- **Column restrictions:** triggers reject changes to immutable columns (`project_id`, `created_by`, `created_at`, and `currency` once locked per [PRJ‑16a]). RLS `WITH CHECK` blocks cross-project row moves.
- **`viewer` writes:** excluded by every INSERT/UPDATE/DELETE policy (role not in the allowed set).
- **Archived projects** ([PRJ‑17]): a trigger on every child table raises if the parent project's `status = 'archived'` (except the un-archive/delete paths). RLS could also encode this but a trigger gives a clear message.

### 12.3 Derived views & functions

- Views (`project_financials`, `timeline_events`, `budget_category_actuals`, `member_balances`) are declared **`WITH (security_invoker = true)`** (PG15+) so the querying user's RLS on the base tables applies automatically.
- Set-returning functions (`get_project_health`, `get_member_balances`) are **`SECURITY INVOKER`** and begin with `IF NOT app.is_member(p_project_id) THEN RAISE insufficient_privilege; END IF;`.

### 12.4 Testing

- **RLS is tested, not assumed.** `supabase/tests/` holds pgTAP tests: for each table, assert that a `member`, a `viewer`, a non-member, and an anon each can/cannot do each verb. Runs in CI against a fresh `supabase db reset`.
- A seed of two projects with overlapping and disjoint members is the fixture.

---

## 13. Storage architecture

MVP storage is minimal; the bucket layout is designed now so [FUTURE] attachments slot in.

| Bucket | Visibility | Path convention | RLS policy | MVP use |
|--------|-----------|-----------------|------------|---------|
| `avatars` | public read | `avatars/<user_id>.<ext>` | write: `name LIKE auth.uid() || '%'` | user profile picture (SHOULD) |
| `project-media` | private | `project-media/<project_id>/cover.<ext>` | read/write: `app.is_member(split_part(name,'/',2)::uuid)`; write needs `{organizer,member}` | project cover image (SHOULD) |
| `attachments` | private | `attachments/<project_id>/<commitment_id>/<uuid>-<filename>` | same predicate on `split_part(name,'/',2)` | **FUTURE** — bucket defined, unused in MVP |

- **Access:** private objects are served via **short-lived signed URLs** (`createSignedUrl`, 1 h) requested through `services/storage.ts`. No public bucket for project data.
- **Uploads:** direct browser → Storage (`supabase.storage.from(...).upload`), constrained by bucket file-size and MIME config. Image transforms (`?width=`) for thumbnails.
- **Cleanup:** deleting a project soft-deletes DB rows; a [FUTURE] scheduled job purges orphaned objects after the recovery window. MVP leaves objects (cheap, private).
- **No secrets or documents with PII** beyond what the project already contains. Virus scanning = FUTURE.

---

## 14. Edge Function strategy

### 14.1 Decision rule

An operation becomes an Edge Function **only if** it needs one of:
- a **secret** that must not be in the browser (email-provider key, AI key, maps key),
- **service-role** DB access (privileged writes beyond the caller's RLS),
- a **third-party API** call,
- **server-only** execution guarantees (webhooks, scheduled jobs),
- **AI** inference.

Everything else is direct Supabase CRUD or a Postgres function.

### 14.2 MVP functions

| Function | Why it qualifies | Auth | Notes |
|----------|------------------|------|-------|
| `invitations-send` | external transactional-email API + creates the invitation atomically | caller must be `organizer` (checked with caller-scoped client) | Input: `{ projectId, email, role }`. Validates with the shared schema, inserts `invitations` row (service-scoped), sends email with the `/invite/:token` link, writes an `audit_log` row. Idempotent per [MEM‑7]. |
| `_shared/` | — | — | shared CORS, auth-guard, zod schemas, error envelope, structured logger. Not a function. |

That is the entire MVP Edge Function surface. **Invitation *acceptance*** is a Postgres `SECURITY DEFINER` RPC (`accept_invitation`), not a function — no external I/O, so it stays in the DB.

### 14.3 Explicitly Postgres, not Edge Functions

Health engine · timeline generation · budget/balance calculation · status-transition validation · last-organizer enforcement · draft→active · equal-split recompute · soft-delete cascade · accept-invitation. All are deterministic DB logic guarded by RLS.

### 14.4 FUTURE functions (designed against, not built)

`notifications-dispatch` (cron; calls `get_project_health` diff → email/push), `ai-suggest` (itinerary/activity suggestions), `geocode` (maps API for location coordinates + travel gaps), `ical-feed` (per-project token → text/calendar), `storage-gc` (orphan purge).

### 14.5 Conventions

- Deno, TypeScript, one folder per function under `supabase/functions/`.
- Every function: CORS preflight handler → parse & `schema.parse(body)` → authorize (caller-scoped client) → do work (service-scoped only for the privileged step) → return `{ ok: true, data }` or `{ ok: false, error: { code, message } }` with the right HTTP status.
- Structured JSON logs with a generated `request_id`; **never log secrets, tokens, or full email addresses** (hash/truncate).
- Secrets via `supabase secrets set`; validated at cold start.
- Timeouts and retries: idempotency keys where a retry could double-send.

---

## 15. Health engine architecture

Implements [BUSINESS_RULES §9] and [DOMAIN_MODEL §7.3].

### 15.1 Location & shape

- **Entirely in PostgreSQL.** `app.get_project_health(p_project_id uuid)` — a `SECURITY INVOKER` set-returning function that:
  1. checks `app.is_member(p_project_id)`,
  2. loads threshold config from `health_config` (per-project row, falling back to global defaults — [HLT‑I]),
  3. evaluates each rule as a `SELECT … WHERE …` and `UNION ALL`s them,
  4. `LEFT JOIN`s `finding_dismissals` to attach `dismissed` / `snoozed_until`,
  5. returns rows: `code, severity, subject_type, subject_id, subject_label, params jsonb, message, resolution, affects_health, dismissible`.
- **`app.get_project_health_summary(p_project_id)`** returns the rollup ([HLT‑C]): `{ status: 'needs_attention'|'at_risk'|'healthy', blocker_count, warning_count, attention_count }` — computed from the same rule set (shared internal CTE so it's evaluated once).
- Message: the function returns both a **machine part** (`code` + `params`) and a **rendered English `message`/`resolution`**. Frontend shows the rendered string in MVP; the `code`+`params` allow i18n later without another migration.

### 15.2 Why here

- It is core business logic that must be **identical for every consumer** (app now, notifications cron later) — [GC‑7].
- It must **not be gameable** from the browser.
- It is **pure DB data + deterministic rules**, no external calls → an Edge Function would add deployment surface and a second language for zero benefit.
- RLS on the base tables + the membership check make it safe to expose via `rpc`.
- Recompute-on-read ([HLT‑G]) is a cheap indexed query for realistic project sizes; if it ever isn't, the fix is a materialised summary refreshed by trigger — still in the DB.

### 15.3 Frontend

- `useHealth(projectId)` → vue-query → `services/derived.getHealth()` → `rpc('get_project_health')` + `rpc('get_project_health_summary')` (or one function returning both via a composite).
- `HealthTab` renders all findings grouped by severity; `Dashboard` / `OverviewTab` render the "needs attention" subset ([HLT‑E]) from the same cached data (`computed` filter).
- **Dismiss/snooze** ([HLT‑F]): `upsert` into `finding_dismissals` `{ project_id, code, subject_type, subject_id, state, snoozed_until }`, optimistic, then invalidate `['project', id, 'health']`. Blockers have `dismissible = false`; the UI hides the control and RLS/trigger rejects the write.
- `has_open_issues` on a commitment ([COM‑20]) is a small dedicated view `commitment_issue_flags` (or a column in the commitment detail view) so lists can badge without pulling all findings.

### 15.4 Config

- `health_config(project_id, key, value)` — keys: `inactive_days` (7), `due_soon_days` (7), `tight_connection_minutes` (20), `unconfirmed_near_days` (14), `on_budget_window_days` (30). Global defaults in a `health_config_defaults` table or function constants. Organizer-editable (SHOULD; MVP can ship defaults-only with the table present).

---

## 16. Error handling

### 16.1 Taxonomy (`lib/errors.ts`)

`AppError` (base) → `AuthError` · `PermissionError` · `ValidationError` (carries `fieldErrors`) · `NotFoundError` · `ConflictError` (stale write) · `RateLimitError` · `NetworkError` · `ServerError` · `UnexpectedError`.

### 16.2 Mapping

- **Services** catch `PostgrestError` / `AuthError` / `FunctionsError` and map to `AppError`:
  - PG `SQLSTATE 23505` (unique) / `23514` (check) / `23503` (FK) / `23502` (not-null) → `ValidationError`, with `constraint` name looked up in a `constraintMessages` map → human field message.
  - Custom trigger/RPC errors use `ERRCODE = 'P0001'` with a **structured `MESSAGE`** `orchestr:<code>:<human text>`; services parse the prefix → typed error + message.
  - `401` → `AuthError` (→ redirect to login); `403` / RLS empty-update → `PermissionError`.
  - Zero-rows-affected on a guarded update → `ConflictError` or `NotFoundError` (disambiguated by a follow-up existence check only when it matters).
- **Edge Functions** return `{ ok:false, error:{ code, message, fields? } }`; `services` translate the envelope to the same `AppError` types.

### 16.3 Presentation

- vue-query global `defaultOptions.mutations.onError` / `queries.onError` → `useErrorHandler`:
  - `ValidationError` → surfaced inline on the form (field errors) — no toast.
  - `PermissionError` → toast "You don't have permission to do that" + refetch (role may have changed).
  - `ConflictError` → toast "This changed while you were editing" + refetch + keep the user's draft.
  - `NetworkError` → toast with retry action; queries auto-retry (3×, backoff) except mutations.
  - `UnexpectedError` / `ServerError` → toast + report to Sentry (SHOULD) with `request_id`.
- **Route-level:** `onErrorCaptured` in `ProjectLayout` renders an in-page error state (not a white screen); a top-level error boundary component wraps `<RouterView>`.
- **Never** swallow an error silently; **never** show a raw Postgres message to the user.

---

## 17. Loading states

The prototype has none; this is net-new.

- **Every query-backed view** branches: `isPending` → `Skeleton`; `isError` → `ErrorState` (with retry); `data.length === 0` → `EmptyState`; else content.
- **Skeletons mirror layout** (list rows, stat tiles, slide-over sections) — component per shape in `components/ui/skeletons/`.
- **Route transitions:** a global progress bar (`nprogress`-style) driven by router hooks + `isFetching` count.
- **`<Suspense>`** wraps lazy route components for the initial chunk load only; data loading uses vue-query states, not Suspense (better error control).
- **Background refetch** (`isFetching && !isPending`) shows a subtle top-of-section shimmer, not a full skeleton — content stays visible.
- **Mutations:** the triggering control shows a pending state (spinner/disabled); optimistic mutations (§4.3) update immediately.
- **Derived views** (health/budget/timeline) always show a skeleton on first load and a shimmer on refetch, because they recompute server-side.
- **Empty states** are specified by [BUSINESS_RULES §10] scenarios: no projects, no commitments, no attention items ("all clear"), no budget set, no members beyond you, no timeline events.

---

## 18. Validation

Three layers; **the database is authoritative**.

| Layer | Tech | Purpose | Authoritative? |
|-------|------|---------|----------------|
| **DB constraints + triggers** | Postgres | every VAL‑* rule, all cross-row invariants | **Yes** |
| **Shared schemas** | `valibot` (or `zod`) in `src/validation/` | form UX: inline errors before submit, type inference for form models | No — mirror only |
| **Edge Function input** | same shared schemas (imported by Deno) | reject malformed payloads before privileged work | Gatekeeper for that path |

- **Schemas mirror, never exceed, DB rules.** Each schema file cites the VAL‑IDs it reflects. A schema may be *stricter for UX* (e.g. trim + collapse whitespace) but the DB still re-checks.
- **No business rule lives only in a schema.** "Last organizer can't leave", "currency locked", "status transition legal" are **not** in valibot — they're DB triggers, surfaced to the user by mapping the trigger's `orchestr:<code>` error (§16.2).
- **Form binding:** `@tanstack/vue-form` or `vee-validate` + the shared schema; `forms.ts` types are `InferOutput<typeof schema>`.
- **Server errors re-map to fields:** a `23505` on `invitations_project_email_unique` → `fields.email = "Already invited"`.
- **Money inputs:** parsed to minor units via `useMoney().parse` with the project currency; the schema validates the integer result ≥ 0.
- **Dates/times:** captured as structured values (date + time + the project timezone), never free text ([DOMAIN_MODEL] fixes the prototype's string dates).

---

## 19. Logging

- **Frontend:** a `lib/logger.ts` wrapper (`debug|info|warn|error`), no-ops `debug` in production. `error`/`warn` optionally forwarded to Sentry as breadcrumbs/events (SHOULD). **Redaction:** never log tokens, emails, or full row payloads; log ids and codes. A `console` lint rule bans direct `console.*` outside the logger.
- **Edge Functions:** structured single-line JSON `{ level, request_id, fn, msg, ...ctx }` to stdout (captured by Supabase function logs). No secrets, truncate emails to domain. Log start/end + outcome of every invocation.
- **Postgres:** `RAISE LOG` only in RPCs for unexpected branches; rely on Supabase's Postgres logs + `pg_stat_statements` for query performance. Slow-query threshold configured per environment.
- **Correlation:** the frontend generates a `x-request-id` per Edge Function call; the function echoes it in logs and the response; client errors reported to Sentry include it.
- **Levels by environment:** dev = `debug`; staging = `info`; production = `warn`+ for frontend forwarding, `info` for functions.

---

## 20. Auditability

- **Baseline (GC‑1):** `created_at`, `updated_at` on every table (trigger-maintained); `created_by` (member id) on user-authored rows.
- **Soft delete (GC‑2):** Project, ProjectMember, Commitment, Payment, Task retain rows with `deleted_at`; **payments are never hard-deleted** — cancellation/waiver preserves financial history ([BUSINESS_RULES BUD‑6/7], §8 amendment).
- **`audit_log` table:** `(id, project_id, at, actor_user_id, actor_member_id, source ∈ {app,rpc,edge,system}, action, entity_type, entity_id, before jsonb, after jsonb, request_id)`.
  - Written by a **generic `audit_row()` trigger** (`AFTER INSERT/UPDATE/DELETE`) attached to: `projects`, `project_members`, `invitations`, `commitments`, `commitment_participants`, `cost_shares`, `payments`, `tasks`, `milestones`, `budgets`, `budget_category_targets`, `finding_dismissals`.
  - `actor_*` from `auth.uid()` + a lookup; `system`/`edge` sources set it explicitly.
  - `before`/`after` store the row minus large/irrelevant columns; jsonb diff computed on read.
- **RLS:** organizers read their project's `audit_log`; **no one** updates or deletes it (no policy for those verbs).
- **Retention:** kept for the life of the project; purged only on hard project deletion ([FUTURE]).
- **Edge Functions** write their own `audit_log` rows for privileged actions (invitation sent, member claimed).
- **FUTURE:** a user-facing activity feed is a read model over `audit_log`; finding history; per-field change timeline on a commitment.

---

## 21. Environment configuration

- **Frontend config** (`src/config.ts`): reads `import.meta.env.VITE_*`, validates with a valibot schema at module load, exports a typed frozen object. Fails fast (throws) if a required var is missing or malformed.
  - Public vars only: `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, `VITE_APP_ENV` (`development|staging|production`), `VITE_SENTRY_DSN?`, `VITE_APP_URL`.
  - **Build fails** if any var name matching `/SERVICE_ROLE|SECRET|PRIVATE_KEY/` is present in the client env.
- **Edge Function secrets:** `supabase secrets set` per project — `EMAIL_PROVIDER_API_KEY`, `EMAIL_FROM`, `APP_URL`, (`AI_API_KEY`, `MAPS_API_KEY` when those functions land). `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` / `SUPABASE_ANON_KEY` are injected automatically. Validated at cold start.
- **`.env.example`** committed with every var documented; real `.env*` files git-ignored.
- **No runtime config server.** Config is build-time for the frontend, deploy-time for functions.
- **Supabase project settings** (auth redirect URLs, email templates, JWT expiry, storage limits) are treated as config: captured in `supabase/config.toml` where supported and documented in `docs/` where not, so an environment can be reproduced.

---

## 22. Development / staging / production separation

### 22.1 Environments

| Env | Supabase | Frontend | Purpose |
|-----|----------|----------|---------|
| **local** | `supabase start` (Docker) | `vite` dev server | day-to-day dev; disposable; seeded |
| **staging** | dedicated Supabase project | preview deploy (host of choice) | integration, QA, migration dry-run, demo |
| **production** | dedicated Supabase project | production deploy | live |

- **Per-PR preview** (SHOULD): Supabase branch + preview frontend deploy, torn down on merge.
- Environments are **fully isolated** — separate DB, Auth users, Storage, secrets, keys. No shared anything.

### 22.2 Schema & data

- **All schema changes are migrations** in `supabase/migrations/` (timestamped SQL). No dashboard schema edits in staging/production.
- Flow: write migration → `supabase db reset` locally (applies + seeds + runs pgTAP) → PR → CI runs migrations + tests on an ephemeral DB → merge → CI `supabase db push` to **staging** → verify → promote (tag) → `supabase db push` to **production**.
- **Seed data** (`supabase/seed.sql`): the prototype's Barcelona + Wedding fixtures ported as realistic seed for local/staging (never production). This keeps the prototype usable as a reference.
- **Generated types** (`types/database.ts`) regenerated from the local/linked DB in CI; drift fails the build.

### 22.3 CI/CD

- **CI on every PR:** install → typecheck (`vue-tsc`) → lint (ESLint + Prettier) → unit tests (Vitest) → component tests → `supabase db reset` + pgTAP (RLS + trigger tests) → build.
- **CD on merge to `main`:** deploy frontend (immutable, env vars injected from CI secrets) → `supabase db push` (staging) → `supabase functions deploy` (staging) → smoke test.
- **Production promotion:** manual approval / tag → same steps against the production project.
- **Rollback:** frontend = redeploy previous immutable build; DB = forward-fix migration (no down-migrations in production); functions = redeploy previous.
- **Secrets** live in the CI provider and in `supabase secrets`, never in the repo.

---

## 23. Recommended project folder structure

```
orchestr/
├─ docs/
│  ├─ PROTOTYPE_ANALYSIS.md
│  ├─ DOMAIN_MODEL.md
│  ├─ BUSINESS_RULES.md
│  └─ TECHNICAL_ARCHITECTURE.md
│
├─ supabase/
│  ├─ config.toml
│  ├─ migrations/                 # timestamped SQL — the only way schema changes
│  ├─ functions/
│  │  ├─ _shared/                 # cors.ts, auth.ts, schemas.ts, logger.ts, errors.ts
│  │  └─ invitations-send/
│  │     └─ index.ts
│  ├─ tests/                      # pgTAP: rls_*.sql, triggers_*.sql, health_*.sql
│  └─ seed.sql                    # Barcelona + Wedding fixtures (local/staging only)
│
├─ src/
│  ├─ main.ts
│  ├─ App.vue
│  ├─ config.ts                   # validated env
│  │
│  ├─ router/
│  │  ├─ index.ts                 # route table (§3)
│  │  └─ guards.ts                # requireAuth / requireMembership / requireRole
│  │
│  ├─ lib/
│  │  ├─ supabase.ts              # typed singleton client
│  │  ├─ query-client.ts          # vue-query defaults (retry, staleTime, onError)
│  │  ├─ permissions.ts           # MEM-14 matrix, PermissionKey union
│  │  ├─ errors.ts                # AppError taxonomy + PostgrestError mapping
│  │  ├─ logger.ts
│  │  └─ analytics.ts             # optional
│  │
│  ├─ stores/                     # Pinia — session + UI only
│  │  ├─ auth.ts
│  │  ├─ project-context.ts
│  │  └─ ui.ts
│  │
│  ├─ services/                   # thin Supabase calls, one per aggregate (§6)
│  │  ├─ projects.ts   ├─ members.ts     ├─ invitations.ts
│  │  ├─ commitments.ts├─ payments.ts    ├─ costShares.ts
│  │  ├─ tasks.ts      ├─ milestones.ts  ├─ budget.ts
│  │  ├─ derived.ts    └─ storage.ts
│  │
│  ├─ composables/                # the only data entrypoint for views (§5)
│  │  ├─ keys.ts                  # query-key factory
│  │  ├─ useAuth.ts        ├─ usePermissions.ts   ├─ useProjectContext.ts
│  │  ├─ useProjects.ts    ├─ useProject.ts       ├─ useMembers.ts
│  │  ├─ useCommitments.ts ├─ useCommitment.ts    ├─ usePayments.ts
│  │  ├─ useCostShares.ts  ├─ useTasks.ts         ├─ useMilestones.ts
│  │  ├─ useBudget.ts      ├─ useFinancials.ts    ├─ useBalances.ts
│  │  ├─ useTimeline.ts    ├─ useCalendar.ts      ├─ useHealth.ts
│  │  ├─ useMoney.ts       ├─ useProjectTime.ts   └─ useToast.ts
│  │
│  ├─ validation/                 # shared valibot schemas (UX mirror of VAL-*) (§18)
│  │  ├─ project.ts  ├─ member.ts   ├─ commitment.ts
│  │  ├─ payment.ts  ├─ task.ts     ├─ milestone.ts  └─ budget.ts
│  │
│  ├─ types/
│  │  ├─ database.ts              # GENERATED — do not edit
│  │  ├─ domain.ts                # ergonomic types built from database.ts
│  │  ├─ derived.ts               # HealthFinding, TimelineEvent, ProjectFinancials, MemberBalance
│  │  ├─ forms.ts                 # InferOutput of validation schemas
│  │  ├─ permissions.ts
│  │  └─ index.ts
│  │
│  ├─ components/
│  │  ├─ ui/                      # primitives + skeletons + empty/error states
│  │  ├─ layout/                  # AppShell, AppSidebar, AppBottomNav, AppTopBar, CurrentProjectSwitcher
│  │  ├─ projects/                # ProjectSummaryRow, NewProjectDialog
│  │  ├─ commitments/             # CommitmentTable, CommitmentRow, CommitmentSlideOver, AddCommitmentWizard, StatusControl
│  │  ├─ payments/                # PaymentList, PaymentForm, PaymentStatusControl
│  │  ├─ budget/                  # BudgetSummary, CategoryBreakdown, BudgetTargetsForm, MemberBalances
│  │  ├─ timeline/                # TimelineView, TimelineDayGroup, TimelineEventRow
│  │  ├─ health/                  # HealthFindingList, HealthFindingRow, NeedsAttentionList, ProjectHealthBadge
│  │  ├─ members/                 # MemberList, MemberRow, InviteDialog, RoleSelect, CostSplitEditor
│  │  └─ tasks/                   # TaskList, TaskRow, TaskForm
│  │
│  ├─ views/
│  │  ├─ DashboardView.vue
│  │  ├─ ProjectsView.vue
│  │  ├─ CalendarView.vue
│  │  ├─ SettingsView.vue
│  │  ├─ NotFoundView.vue
│  │  ├─ auth/
│  │  │  ├─ LoginView.vue
│  │  │  ├─ AuthCallbackView.vue
│  │  │  └─ AcceptInviteView.vue
│  │  └─ project/
│  │     ├─ ProjectLayout.vue     # header + stat tiles + tabs + <RouterView>
│  │     ├─ OverviewTab.vue
│  │     ├─ CommitmentsTab.vue
│  │     ├─ BudgetTab.vue
│  │     ├─ TimelineTab.vue
│  │     ├─ PeopleTab.vue
│  │     ├─ HealthTab.vue
│  │     └─ ProjectSettingsView.vue
│  │
│  ├─ assets/
│  └─ styles/
│     ├─ tailwind.css
│     └─ tokens.css               # prototype design tokens
│
├─ tests/
│  ├─ unit/                       # composables (mocked services), permissions, money, errors
│  ├─ component/                  # domain components (mounted, mocked composables)
│  └─ setup.ts
│
├─ .env.example
├─ tailwind.config.ts
├─ postcss.config.js
├─ vite.config.ts
├─ vitest.config.ts
├─ tsconfig.json
├─ eslint.config.js
└─ package.json
```

### 23.1 Structure rationale

- **`services/` ↔ `composables/` ↔ `views/`** is the entire vertical. No fourth layer.
- **`components/` never imports `services/` or `lib/supabase`** — enforced by an ESLint boundary rule.
- **`supabase/` is a peer of `src/`**, not nested — the database is a first-class part of the codebase, versioned and tested alongside the frontend.
- **`types/database.ts` generated + committed** so the whole team and CI share one truth without a live DB.
- **`validation/` is shared** between `src/` and `supabase/functions/` (path alias) so the schema is written once.

---

## 24. Summary of key decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | SPA, no SSR | app is behind auth; avoids a server tier |
| 2 | vue-query for server state, Pinia for session/UI | no hand-rolled cache; clean split |
| 3 | Direct `supabase-js` for CRUD; thin one-call services | "avoid unnecessary API abstractions" |
| 4 | All derived data (budget/timeline/health/balances/progress) as Postgres views + functions | one canonical definition; not gameable; reusable by future cron |
| 5 | RLS is the authorization layer; frontend checks are advisory | security cannot live in the browser |
| 6 | `SECURITY DEFINER` helper functions for membership lookups | breaks RLS recursion on `project_members` |
| 7 | Exactly one MVP Edge Function (`invitations-send`) | only email needs a secret + external API; invite *acceptance* is an RPC |
| 8 | Health engine = `get_project_health()` SQL function + `finding_dismissals` table | deterministic, colocated with data, RLS-safe |
| 9 | DB is authoritative for validation; valibot schemas mirror for UX | no business rule enforced only client-side |
| 10 | Generic `audit_row()` trigger → `audit_log` | uniform auditability; payments never hard-deleted |
| 11 | Three isolated environments; migrations-only schema changes; prototype data as seed | reproducible, safe promotion |
| 12 | URL is the source of truth for view state | fixes the prototype's reset-on-refresh |
```
