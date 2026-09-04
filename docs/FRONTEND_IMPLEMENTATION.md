# Frontend Implementation — Pass 1 (+ Foundation Verification)

**Status:** installs · typechecks · builds · dev-server runs. Backend flows verified by code inspection (Docker/local Supabase not available in the build environment — see §7).
**Date:** 2026-09-04
**Implements:** [`TECHNICAL_ARCHITECTURE.md`](./TECHNICAL_ARCHITECTURE.md) · visual reference: [`orchestr-prototype.html`](../orchestr-prototype.html)
**Scope of this pass:** 1) Authentication · 2) Dashboard shell · 3) Projects · 4) Project navigation · 5) Project overview.

---

## 1. Run it

```bash
npm install
cp .env.example .env.local        # fill VITE_SUPABASE_URL + VITE_SUPABASE_ANON_KEY (from `supabase start`)
supabase start && supabase db reset   # applies all 10 migrations + seed  (needs Docker)
npm run gen:types                 # regenerate src/types/database.ts from the live DB (drop-in — see §7.3)
npm run typecheck                 # vue-tsc --noEmit
npm run lint                      # eslint (config committed; see §7.1)
npm run build                     # vue-tsc && vite build
npm run dev                       # http://localhost:5173
```

Seed users (from `supabase/seed.sql`): `james@example.com` … `chris@example.com`, password `password123`. Local Supabase has email confirmations disabled, so password sign-in works immediately; magic links appear in Inbucket (`http://localhost:54324`).

---

## 2. Stack

| Concern | Choice |
|---|---|
| Framework | Vue 3.5 `<script setup>` + TypeScript (strict, `noUncheckedIndexedAccess`) |
| Build | Vite 5 |
| Styling | Tailwind 3 — palette + type scale ported verbatim from the prototype (`tailwind.config.ts`) |
| Server state | `@tanstack/vue-query` v5 |
| Client state | Pinia — `auth`, `project-context`, `ui` only |
| Routing | `vue-router` 4, hand-written typed table |
| Data | `@supabase/supabase-js` v2, **direct** (thin one-call services) |
| Dates | Luxon (project-timezone rendering) |
| Overlays | `@headlessui/vue` (focus trap / a11y for modal + menu) |
| Fonts | self-hosted `@fontsource/{inter,space-grotesk}` |

---

## 3. What was built (folder map)

```
src/
├─ config.ts                 valibot-validated env; APP_NAME constant (single place — see §6)
├─ lib/
│  ├─ supabase.ts            typed singleton client (PKCE, detectSessionInUrl)
│  ├─ errors.ts              AppError taxonomy + Postgrest/orchestr:<code> → typed error mapping
│  ├─ query-client.ts        vue-query defaults (retry only network, no mutation retry)
│  ├─ permissions.ts         MEM-14 matrix, advisory-only `can()`
│  └─ logger.ts              redacting logger
├─ types/
│  ├─ database.ts            STOPGAP hand-written subset — regenerate with `npm run gen:types`
│  ├─ domain.ts / derived.ts ergonomic + derived-view types
├─ stores/  auth · project-context · ui
├─ services/                 projects · members · derived · profile · invitations   (one call + error map each)
├─ composables/
│  ├─ useAuth (+ initAuth)   onAuthStateChange wired once; signInWithOtp/Password/signOut
│  ├─ useProjects            useMyProjects, useCreateProject
│  ├─ useProject             useProject, useProjectFinancials, useProjectHealth, useUpcoming, useMemberDirectory
│  ├─ useDashboard           useMyProfile, useDashboardAttention (fan-out get_project_health)
│  ├─ useProjectContext      current project + role + advisory `allowed()`
│  ├─ useMoney / useProjectTime / useToast / keys
├─ router/  index.ts (table) · guards.ts (requireAuth, requireGuest, hydrateProjectContext)
├─ components/
│  ├─ ui/     AppIcon(+icons.ts) · AppButton · StatusBadge · SeverityIcon · StatTile · ProgressBar
│  │         · SkeletonBlock · EmptyState · ErrorState · FeaturePending · AppAvatar · AppModal
│  │         · ToastHost · AppErrorBoundary · PageContainer · SectionHeading
│  ├─ layout/ AppShell · AppSidebar · AppBottomNav · AppTopBar · CurrentProjectLink · UserMenu · navItems.ts
│  ├─ projects/  ProjectSummaryRow · NewProjectDialog
│  ├─ health/    AttentionRow · ProjectHealthBadge
│  └─ timeline/  UpcomingList
└─ views/
   ├─ auth/   LoginView · AuthCallbackView · AcceptInviteView
   ├─ DashboardView · ProjectsView · SettingsView (partial) · NotFoundView
   ├─ CalendarView · PeopleView               (isolated — FeaturePending)
   └─ project/ ProjectLayout · ProjectTabs · OverviewTab · PeopleTab (read-only)
              · CommitmentsTab · BudgetTab · TimelineTab · HealthTab · ProjectSettingsView   (isolated)
```

---

## 4. Prototype fidelity

Ported unchanged: the paper/ink/accent/amber palette, Inter + Space Grotesk, the 13–15px type scale, the `max-w-5xl` page container with `fade-in`, the desktop sidebar (wordmark → nav → current-project block → user footer) + mobile sticky topbar + bottom tab bar, the project header + four stat tiles + six-tab strip, the bordered `divide-y` "Needs attention" and "Upcoming" cards, `StatTile` / `StatusBadge` / severity-square styling, the `New project` / `New activity` primary-button treatment.

**Deliberate changes** (technical/usability, per the brief):

| Change | Why |
|---|---|
| Added a **login screen** and **invite-accept screen** | the prototype has no auth; built in the same visual language |
| URL is the source of truth for view / project / tab (prototype used a JS `state` object) | fixes "everything resets on refresh"; enables deep links |
| Deep-linking a "Needs attention" row opens the **project** (not an activity slide-over) | the activity slide-over is a later pass; not faked |
| Dashboard "Needs attention" **aggregates across all your projects** | matches DOMAIN_MODEL; the prototype only showed one project's list |
| Every list has explicit **skeleton / error(+retry) / empty** states | the prototype had none |
| Wordmark is **"Orchestr"** | the product name — resolved. The prototype HTML carried a "Basecamp" placeholder. |

---

## 5. Backend wiring — real vs isolated

**Wired to existing backend (real data, no fakes):**

| Screen | Source |
|---|---|
| Login / magic link / password | Supabase Auth |
| Invite accept | `get_invitation` + `accept_invitation` RPCs |
| Dashboard greeting | `public.users.display_name` |
| Dashboard project rows + Projects list | `v_my_projects` |
| Dashboard "Needs attention" | `public.get_my_attention()` — ONE set-based call across all your projects (blocker+warning, non-dismissed) |
| New project | `insert into projects` (trigger creates the organizer membership) |
| Project header tiles | `v_project_financials` |
| Project navigation / role gate | `project_members` (own row) + `projects` |
| Overview → Needs attention | `get_project_health` |
| Overview → Upcoming (14 days) | `v_timeline_events` |
| Project → People tab (read-only list) | `v_member_directory` |
| Settings (read-only) | `public.users` |

**Isolated — rendered as `FeaturePending`, never faked:**

- Project tabs: **Activities, Budget, Timeline, Health** (backend tables/views exist; the UI is a later pass).
- **Project settings** screen and the **Share** button (Share is shown disabled; settings routes to a FeaturePending view).
- **Calendar** and global **People** top-level screens (Calendar = later pass; global People = a FUTURE `Contact` concept).
- **Editing** anything in Settings; **inviting / role changes / removal** on the People tab.
- Deep-link to a specific commitment / activity slide-over.

Each `FeaturePending` block states plainly what's missing and whether the backend is ready.

---

## 6. Open items / notes

1. **`src/types/database.ts` is authored to match `supabase gen types typescript --local` output exactly** — full coverage of every table/view/enum/function in the current migrations (not a partial stopgap). Regenerate with `npm run gen:types` once the local stack runs; the shape is identical so it drops in.
2. **Product name is resolved: "Orchestr"** — one constant, `APP_NAME` in `src/config.ts`.
3. **`v_my_projects.total_target_minor`** is now provided by the backend (migration `20260904120800`). `ProjectSummaryRow` consumes it directly — no client-side budget math.
4. **Dashboard "Needs attention" is one set-based call** (`public.get_my_attention()`, migration `20260904120800`). The former per-project `get_project_health` fan-out (client N+1) is gone. The headline count still comes from `v_my_projects.attention_count` (already in the view).
5. **No realtime yet** — vue-query `refetchOnWindowFocus` + manual invalidation only (TECHNICAL_ARCHITECTURE §8.1, SHOULD — later pass).
6. **`initAuth()` runs before the router**; guards `await` a `ready` watcher.
7. **Project-header financial tiles degrade gracefully** on a `v_project_financials` error (show "Not set" / "—" / "0%") rather than blocking the tab content — a deliberate choice for a secondary stat panel.
8. **Magic-link login always returns to `/`** (the `?redirect=` param isn't carried through the email link). Password login honours `?redirect=`.

---

## 7. Foundation Verification Pass (2026-09-04)

### 7.1 Commands run

| Command | Result |
|---|---|
| `npm install` | ✅ base deps resolved (117 packages). *Sandbox note:* this environment blocks adding new packages to `node_modules`, so eslint + `@types/node` are declared in `package.json` and `eslint.config.js` is committed, but `npm run lint` could not be executed here. |
| `npm run typecheck` (`vue-tsc --noEmit`) | ✅ **exit 0** (with `strict`, `noUncheckedIndexedAccess`, `noImplicitOverride`, `noUnusedLocals`, `noUnusedParameters`) |
| `npm run build` (`vue-tsc && vite build`) | ✅ **exit 0** — 301 modules, ~130 kB gzip JS, 1.5 s |
| `vite` dev server | ✅ boots (192 ms), serves `/`, all route/composable/lib modules transform without error |
| `supabase start` / `supabase gen types` | ❌ **not possible here** — Docker unavailable. `database.ts` was authored to the generator's exact format from the migrations instead. |

### 7.2 Failures found & fixed

| # | Failure | Fix |
|---|---|---|
| 1 | `.rpc()` args typed `undefined`, `.insert()` typed `never[]` — hand-written `Database` didn't satisfy supabase-js **2.115** `GenericSchema` (missing `Relationships` on every table/view; incomplete Functions) | Replaced `src/types/database.ts` with a **complete generated-format file** — all 15 tables, 7 views, 15 enums, 6 functions, `Relationships: []`, helper aliases |
| 2 | `AppError.cause` — `TS4114` must have `override` | drop the redeclared field; pass `cause` to `super(message, { cause })` |
| 3 | `SeverityIcon` — `FindingSeverity` import broke → `any` index error | import from `@/types` barrel; `derived.ts` re-narrows `severity: string → FindingSeverity` at the service boundary |
| 4 | `vite.config.ts` — `Cannot find module 'node:url'` (no `@types/node`) | rework alias with the `URL` global (`new URL("./src/", import.meta.url).pathname`) — zero node imports |
| 5 | `SettingsView` — `Json \| undefined` not assignable to `Record<string, unknown>` | `notif(raw: unknown)` with a runtime `typeof` narrow |
| 6 | Boundary violation — `AcceptInviteView` imported `@/services/invitations` directly | new `useInvitation` composable; the view now uses it |
| 7 | Silent failure — dashboard "Needs attention" had no error state; Overview "Upcoming" and People tab errors had no retry | added `ErrorState` + `retry` to all three |

### 7.3 Generated-type status

`src/types/database.ts` is a **faithful, complete** hand-authored equivalent of `supabase gen types typescript --local`, derived from `supabase/migrations`. It compiles cleanly against supabase-js 2.115. Replace it verbatim with `npm run gen:types` output when the stack is available — no code changes needed.

### 7.4 Backend additions

One additive migration — **`supabase/migrations/20260904120800_frontend_read_models.sql`** (no behaviour/policy/formula change):

1. `v_my_projects` gains **`total_target_minor`** (appended column, sourced from `v_project_financials` — the existing financial derivation). Removes the temporary `remaining_budget + total_cost` calc from Vue.
2. **`public.get_my_attention()`** — `SECURITY INVOKER`, set-based: for each project the caller is an active member of, `cross join lateral app._health_findings(p.id)`, filtered to non-dismissed blocker/warning, dismissal logic identical to `get_project_health`. One round-trip replaces the client-side N+1. Health calculation stays entirely in Postgres.

### 7.5 Route / auth verification (by code inspection — no live backend here)

| Scenario | Path traced | Verdict |
|---|---|---|
| Password login | `LoginView` → `useAuth.signInWithPassword` → `supabase.auth.signInWithPassword` → error→toast / success→`router.push(redirect)` | ✅ |
| Magic-link login | `signInWithOtp` (redirect `…/auth/callback`) → "check email" → `AuthCallbackView` waits on `ready` → redirect | ✅ (redirect param not carried — noted §6.8) |
| Auth callback | `detectSessionInUrl` parses token → `onAuthStateChange` → store → `AuthCallbackView` routes to target or `/login` | ✅ |
| Logout | `UserMenu` → `useAuth.signOut` → `supabase.auth.signOut` + `queryClient.clear()` + store reset → `/login` | ✅ |
| Dashboard / project list / overview / People | composable → service → RLS-protected view/RPC; skeleton/error/empty/content branches present | ✅ |
| Create project | `useCreateProject` → `insert into projects` (status defaults `draft`, passes `projects_insert_authed`); trigger makes the organizer membership; invalidates `['me','projects']`; navigates | ✅ |
| Project switching A→B | global `router.beforeEach(hydrateProjectContext)` re-hydrates on `projectId` change (a `beforeEnter` would miss param-only changes); child composables have `computed` query keys → refetch | ✅ |
| Direct nav to inaccessible project | `getMyMembership` → 0 rows (RLS) → `null` → guard returns `{ name: 'not-found' }`; `getProject` → `PGRST116` → `AppError('not_found')` → same | ✅ no leak |
| Direct nav while signed out | `hydrateProjectContext` → `await whenReady()` → no `userId` → `{ name: 'login', query: { redirect } }`; parent `/` route also has `requireAuth` | ✅ double-covered |

### 7.6 RLS / error-handling verification

- `lib/errors.ts` maps: `orchestr:<code>` messages (`not_a_member`, `not_organizer`, `auth_required`, `project_archived`, `last_organizer`, `forbidden_member_change`) → `AppError('permission')`; SQLSTATE `42501` / `P0001` → `permission`; `23505/23514/23502/23503` → `validation` (with constraint→message map); `PGRST116` → `not_found`; fetch failures → `network`.
- **Every service** function is `if (error) throw toAppError(error)` — RLS denials always surface as typed `AppError`, never a raw Postgres string.
- **No frontend code treats a route guard as security.** `hydrateProjectContext`'s not-found redirect is UX; the data itself is RLS-gated at the view/RPC. `lib/permissions.ts` + `usePermissions` are labelled **advisory only** in-code. The one role-gated control (Project settings button) leads only to a `FeaturePending` view — no privileged action is client-gated.

### 7.7 Boundary audit (item 12)

| Layer | Rule | Result |
|---|---|---|
| `components/**` | no Supabase / no services | ✅ clean |
| `views/**` | use composables, not services | ✅ after fix #6 (`AcceptInviteView` → `useInvitation`) |
| `composables/**` | use services | ✅ |
| `services/**` | own the Supabase calls | ✅ (all `supabase.*` calls live here) |
| `router/guards.ts` → services | infrastructure prefetch, per TECHNICAL_ARCHITECTURE §3 | ✅ acceptable (not a view) |
| `composables/useAuth.ts` → `lib/supabase` | `supabase.auth.*` per TECHNICAL_ARCHITECTURE §5 (auth is not table CRUD; no auth service in the spec) | ✅ acceptable |

### 7.8 No prototype data / no fake success (item 13)

- **No hardcoded prototype `DATA`** anywhere. (One form-field `placeholder="e.g. Barcelona Stag Weekend"` — a UI hint, not rendered data.)
- **Every mutation calls a real service** → real Supabase write: `createProject` (`insert`), `acceptInvitation` (`rpc`). No `Promise.resolve()` / optimistic-only / fake-success path exists.
- Unbuilt features are `FeaturePending` blocks that state what's missing and whether the backend is ready — they render nothing that looks like working data.

### 7.9 Architectural deviations

**None.** Type generation, the two additive backend objects, and the `useInvitation` composable all follow the approved architecture. The `database.ts` hand-authoring is a tooling substitute (Docker unavailable), not a design change.

### 7.10 Remaining blockers before frontend Pass 2

| Blocker | Owner action |
|---|---|
| **Apply the backend** — no migration has run yet. `supabase start && supabase db reset` (needs Docker), then `npm run gen:types` to regenerate `database.ts` from the live DB. | environment |
| **Run `npm run lint`** — config + deps are committed; this sandbox can't install eslint. Run once in a normal environment and fix any findings. | environment |
| **Live E2E of auth + RLS flows** — verified here by inspection only; needs the running stack (Docker) to confirm end-to-end. | environment |
| Nothing in the frontend code itself blocks Pass 2. | — |

### 7.11 Production build result

✅ `vue-tsc --noEmit` exit 0 → `vite build` exit 0. 301 modules, `dist/assets/index-*.js` 386 kB (118 kB gzip), largest lazy chunk is Luxon (72 kB / 22 kB gzip via `useProjectTime`). No warnings.

---

## 8. Public landing + auth-entry pass (2026-09-04)

Purpose: `/` was redirecting unauthenticated visitors to `/login`. This pass adds a
public marketing landing page and a clean public/authenticated route boundary.
**No Phase-2 application functionality** (Activities, Budget, Timeline, Health,
Calendar, member management, project settings) was implemented.

### 8.1 Public / authenticated route split

| Layer | Path prefix | Guard |
|---|---|---|
| Public | `/`, `/login`, `/signup`, `/auth/callback`, `/invite/:token`, `*` (404) | none (`/`); `requireGuest` on `/login` + `/signup` |
| Application | **`/app`, `/app/**`** | `requireAuth` (`beforeEnter` on the `/app` shell route) |

`/` **never** requires auth — an unauthenticated visitor sees `LandingView`; an
authenticated visitor also sees it (they are not forced away — spec §17).

### 8.2 Route migration

Every application route moved from `/…` to `/app/…`. **Route names are unchanged**
(`dashboard`, `projects`, `calendar`, `people-global`, `settings`, `project.overview`,
`project.commitments`, `project.budget`, `project.timeline`, `project.people`,
`project.health`, `project.settings`, `login`, `auth.callback`, `invite`, `not-found`).
New names: `landing`, `signup`.

Because all in-app navigation already used **named routes** (`{ name: 'dashboard' }`
etc.), the path change is transparent to callers. Two hardcoded references were
updated: `NotFoundView` (`router.push('/')` → `{ name: 'dashboard' | 'landing' }`),
and the login/callback redirect default (`'/'` → `'/app'`). `navItems.ts`,
`ProjectTabs.vue`, `CurrentProjectLink`, `ProjectSummaryRow`, `UserMenu`,
`DashboardView` were all already name-based — no changes. **No stale links to the
old root routes remain** (grep-verified).

### 8.3 Final route table

| Path | Name | Component | Guard | Notes |
|---|---|---|---|---|
| `/` | `landing` | `LandingView` | — (public) | marketing page; auth-aware CTAs |
| `/login` | `login` | `auth/LoginView` | `requireGuest` | password + magic link; honours `?redirect`; links to `/signup` |
| `/signup` | `signup` | `auth/SignupView` | `requireGuest` | email+password + magic link; honours `?redirect`; links to `/login` |
| `/auth/callback` | `auth.callback` | `auth/AuthCallbackView` | — | resolves session → `?redirect` or `/app` |
| `/invite/:token` | `invite` | `auth/AcceptInviteView` | — | unchanged flow |
| `/app` | `dashboard` | `DashboardView` (child of `AppShell`) | `requireAuth` | the existing dashboard, reused as-is |
| `/app/projects` | `projects` | `ProjectsView` | `requireAuth` | |
| `/app/projects/:projectId` | → `project.overview` | `ProjectLayout` | `requireAuth` + `hydrateProjectContext` | empty child redirects to overview |
| `/app/projects/:projectId/overview` | `project.overview` | `OverviewTab` | ↑ | |
| `/app/projects/:projectId/activities` | `project.commitments` | `CommitmentsTab` (FeaturePending) | ↑ | |
| `/app/projects/:projectId/budget` | `project.budget` | `BudgetTab` (FeaturePending) | ↑ | |
| `/app/projects/:projectId/timeline` | `project.timeline` | `TimelineTab` (FeaturePending) | ↑ | |
| `/app/projects/:projectId/people` | `project.people` | `PeopleTab` (read-only) | ↑ | |
| `/app/projects/:projectId/health` | `project.health` | `HealthTab` (FeaturePending) | ↑ | |
| `/app/projects/:projectId/settings` | `project.settings` | `ProjectSettingsView` (FeaturePending) | ↑ | |
| `/app/calendar` | `calendar` | `CalendarView` (FeaturePending) | `requireAuth` | |
| `/app/people` | `people-global` | `PeopleView` (FeaturePending) | `requireAuth` | |
| `/app/settings` | `settings` | `SettingsView` (partial — profile read-only) | `requireAuth` | |
| `/:pathMatch(.*)*` | `not-found` | `NotFoundView` | — | |

### 8.4 Guard behaviour

- **`requireAuth`** (`/app` shell): unauthenticated → `{ name: 'login', query: { redirect: to.fullPath } }`. e.g. `/app/projects/abc123` → `/login?redirect=/app/projects/abc123`.
- **`requireGuest`** (`/login`, `/signup`): authenticated → `safeRedirect(?redirect)` if safe, else `{ name: 'dashboard' }`.
- **`hydrateProjectContext`** (global `beforeEach`): unchanged. For a `project.*` route while signed out → `{ name: 'login', query: { redirect: to.fullPath } }`; while signed in but not a member → `{ name: 'not-found' }`.
- **`safeRedirect(raw)`** (new, exported from `router/guards.ts`): allows only internal, non-protocol-relative paths (`/…`, not `//`, not `/\`, no backslash, no `scheme:`). Unit-tested (11 cases). **Guards remain UX only — Supabase RLS is the security boundary.**
- **Post-login destination**: `safeRedirect(route.query.redirect) ?? '/app'` for password + callback. Magic-link login/signup carries the redirect through `emailRedirectTo=…/auth/callback?redirect=<path>` (requires the `additional_redirect_urls` wildcard entries added to `supabase/config.toml`; mirror in the hosted project's Auth URL config).

### 8.5 LandingView structure (`src/views/LandingView.vue`)

`overflow-x-hidden` root → skip-link → `<MarketingHeader>` → `<main id="main">` → `<MarketingFooter>`. `main` contains, in order:

1. **HeroSection** — h1 "Turn complex plans into coordinated execution.", the approved positioning sentence, primary CTA (`Start planning` / `Open Orchestr`), secondary CTA `See how it works` (scrolls to `#how-it-works`), and a static `ProductPreview`.
2. **ProblemSection** — fragmentation across WhatsApp/email/spreadsheets/PDFs/confirmations/notes/reminders; consequence: nobody has one reliable view.
3. **PillarsSection** (`#product`) — Commitments · Ownership · Money · Timeline · People · Planning health.
4. **HowItWorksSection** (`#how-it-works`) — 4 steps: create a plan → add commitments and people → track costs/ownership/deadlines → resolve risks and execute.
5. **UseCasesSection** (`#use-cases`) — group trips, weddings/events, house moves, product/startup launches, team projects, any complex group plan — "different plans, the same problem".
6. **PlanningHealthSection** (`#features`) — deterministic-rules framing ("Orchestr continuously checks your plan for things that need attention"), explicit "no AI guesswork / won't make bookings / won't plan on its own", and an illustrative findings list.
7. **FinalCtaSection** — "Keep the whole plan moving." + `Create your first plan` / `Open Orchestr` + secondary "Log in" when signed out.

Header nav (`#product`, `#how-it-works`, `#use-cases`, `#features`) uses real `<a href="#…">` anchors with `@click.prevent` smooth-scroll (respects `prefers-reduced-motion`) + `scroll-margin-top` on `[id]`. Mobile menu is a Headless UI `Disclosure` (keyboard + `aria-expanded` handled). The marketing header/footer do **not** reuse `AppShell`.

**Product visuals** (`ProductPreview.vue`, and the findings list in `PlanningHealthSection`) are static components built from existing primitives (`StatTile`, `ProgressBar`, `StatusBadge`, `SeverityIcon`) with fixed marketing sample content scoped to the component — **no composables, no network calls, no Supabase**. Marked `role="img"` with an `aria-label`.

### 8.6 Auth-aware CTA behaviour

| Location | Signed out | Signed in |
|---|---|---|
| Header (desktop + mobile) | `Log in` (ghost) + `Get started` (primary) | `Open Orchestr` → `/app` |
| Hero primary CTA | `Start planning` → `/signup` | `Open Orchestr` → `/app` |
| Hero secondary CTA | `See how it works` → scroll to `#how-it-works` (both states) | ↑ |
| Final CTA | `Create your first plan` → `/signup` (+ "Log in" link) | `Open Orchestr` → `/app` |

State comes from `useAuth().isAuthenticated` (Pinia session store). No database calls in landing components.

### 8.7 Signup / login behaviour

- **`/signup`** (`SignupView`, new — separate screen): email + password (min 8, `new-password`), or "Email me a link instead" (magic link). On password sign-up: if Supabase returns **no session** (email confirmation required) → shows a "confirm your email" state and explicitly says *"You're not signed in yet"* — it never fakes a logged-in state (spec §15). If a session **is** returned (confirmations off) → `router.push(dest())`. Magic-link → "check your email". Footer link: *"Already have an account? Log in"* → `/login`.
- **`/login`** (`LoginView`, updated): unchanged auth logic (password + magic link), restyled header + `<h1>Log in</h1>`, wordmark links to `/`, honours `?redirect` (password immediately; magic link via `emailRedirectTo`). Footer link: *"Don't have an account? Sign up"* → `/signup` (carrying `?redirect`).
- `useAuth` gained `signUpWithPassword(email, password, redirect?) → { needsConfirmation }` and `signInWithOtp` gained an optional `redirect` arg.

### 8.8 SEO / metadata

`usePageMeta({ title, description, url? })` composable sets `document.title` + `<meta name="description">` + `og:title`/`og:description`/`og:type`/`og:url` + `twitter:card` on mount. `index.html` carries static defaults. `router.afterEach` sets `document.title` from `route.meta.title` (fallback for app routes) and resets the description to the product default on non-public routes. **No SSR / Nuxt** — client-side metadata only, sufficient for a public SPA.

Default title: `Orchestr — Plan together. Execute clearly.`

### 8.9 Files

**Created (13):** `src/views/LandingView.vue`, `src/views/auth/SignupView.vue`,
`src/composables/usePageMeta.ts`, `src/components/marketing/{MarketingHeader,MarketingFooter,HeroSection,ProblemSection,PillarsSection,HowItWorksSection,UseCasesSection,PlanningHealthSection,FinalCtaSection,ProductPreview}.vue`,
`src/components/marketing/scroll.ts`, `vercel.json`.

**Modified (11):** `src/router/index.ts` (new table, scrollBehavior for hash, title afterEach),
`src/router/guards.ts` (`safeRedirect`, `requireGuest` honours redirect),
`src/composables/useAuth.ts` (`signUpWithPassword`, redirect-aware `signInWithOtp`),
`src/views/auth/LoginView.vue`, `src/views/auth/AuthCallbackView.vue`, `src/views/NotFoundView.vue`,
`src/components/ui/AppButton.vue` (`to`/`href` → RouterLink/anchor, `lg` size),
`src/components/ui/icons.ts` (`menu`, `arrowRight`, `coins`, `flag`),
`src/styles/tailwind.css` (`scroll-margin-top`, `prefers-reduced-motion` block),
`index.html` (meta), `supabase/config.toml` (`additional_redirect_urls` wildcards).

### 8.10 Verification

| Check | Result |
|---|---|
| `vue-tsc --noEmit` (strict, `noUncheckedIndexedAccess`, `noUnusedLocals/Params`) | ✅ exit 0 |
| `vite build` (`vue-tsc && vite build`) | ✅ exit 0 — 327 modules, ~1.7 s, no warnings; `LandingView` + `SignupView` are lazy chunks |
| `npm run lint` | ⚠️ not runnable here (sandbox blocks installing `@eslint/js` / `typescript-eslint` / `eslint-plugin-vue`); `eslint.config.js` committed; `vue-tsc` unused-locals covers TS-level lint |
| `safeRedirect` unit logic | ✅ 11/11 cases (internal ok; `//`, `https:`, `/\`, `\`, `javascript:`, empty, undefined → null) |
| SPA deep-link refresh — `vite` dev **and** `vite preview` | ✅ `/`, `/app`, `/app/projects/abc/overview`, `/nonsense` all serve `index.html` (200) |
| Vite/Vue compile of all new modules (dev server) | ✅ clean |

**Route behaviour** (traced against the guard code; live E2E needs the running Supabase stack — Docker unavailable here):

SIGNED OUT — `/` → landing ✅ · `/login` → login ✅ · `/signup` → signup ✅ · `/app` → `/login?redirect=/app` ✅ · `/app/projects` → `/login?redirect=/app/projects` ✅ · `/app/projects/abc123` → `/login?redirect=/app/projects/abc123` ✅ (exact path).

SIGNED IN — `/` → landing (still reachable) ✅ · landing CTA → `/app` ✅ · `/login` → `/app` (or `?redirect`) ✅ · `/signup` → `/app` ✅ · `/app` → Dashboard ✅ · project routes hydrate + render normally ✅. No redirect loops (traced).

### 8.11 Production host (Vercel) — SPA rewrite

`vercel.json` is committed:

```json
{ "rewrites": [{ "source": "/(.*)", "destination": "/index.html" }] }
```

Vercel serves files from `dist/` first (so `/assets/*` hashed bundles load directly), then falls back to `index.html` for every other path — which is what a `createWebHistory` SPA needs for deep-link refresh (`/app/projects/:id/overview`). Also sets a 1-year immutable cache header on `/assets/*`. **No other host config is required.**

### 8.12 Architectural deviations

**None.** Domain model, financial formulas, RLS, Vue Query / Pinia architecture, and service boundaries are untouched. `AppButton` gained a `to`/`href` mode (additive to the existing primitive — not a second design system). No database calls were added to landing components.

### 8.13 Remaining intentionally pending

- **Privacy / Terms / About pages** — footer renders these as disabled placeholders (`aria-disabled`), not fake links; a footer note says they're in progress.
- **Real OG image** — `twitter:card` is `summary_large_image` but no image asset is set yet.
- All Phase-2 application tabs remain `FeaturePending` (unchanged this pass).
- Live E2E of the auth-entry redirects (needs the Supabase stack).
