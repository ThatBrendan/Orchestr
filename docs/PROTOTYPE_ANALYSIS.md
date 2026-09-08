# Prototype Analysis

**Source of truth:** [`orchestr-prototype.html`](../orchestr-prototype.html) — a single-file, client-only HTML/JS/Tailwind prototype.
**Date analysed:** 2026-09-04
**Purpose:** Document what the prototype currently represents so a production architecture can be derived from it. This document does **not** redesign the product, propose a database, or add functionality that is not visible in the prototype. Where the prototype is silent or contradictory, the gap is called out explicitly as an **Architectural Decision (AD)**.

---

## 0. What the prototype is

- One file, ~830 lines. No build step, no backend, no persistence, no router.
- Rendering is a single `render()` function that rebuilds `#app` from an in-memory `DATA` object and a `state` object, then rebinds all DOM event listeners (`bindEvents()`).
- Styling: Tailwind via CDN + a small `:root` custom-property palette + Google Fonts (Inter, Space Grotesk).
- All content is hardcoded in the `DATA` constant. Nothing is fetched, saved, or validated.
- Product name is ambiguous — see [§14](#14-inconsistencies-and-ambiguities).

---

## 1. Current screens

Navigation is driven by `state.view`. Routes are resolved in `renderMain()`.

| # | Screen | `state.view` | Renderer | Status in prototype |
|---|--------|-------------|----------|---------------------|
| 1 | Dashboard | `dashboard` | `renderDashboard()` | Fully built, Barcelona + Wedding data |
| 2 | Projects (list) | `projects` | `renderProjects()` | Fully built |
| 3 | Project detail | `project` | `renderProject()` → tabbed | Fully built for `barcelona`; partial for `wedding` |
| 4 | — Project ▸ Overview tab | `projectTab = overview` | `renderOverviewTab()` | Built |
| 5 | — Project ▸ Activities tab | `activities` | `renderActivitiesTab()` | Built (desktop table + mobile cards) |
| 6 | — Project ▸ Budget tab | `budget` | `renderBudgetTab()` | Built |
| 7 | — Project ▸ Timeline tab | `timeline` | `renderTimelineTab()` | Built |
| 8 | — Project ▸ People tab | `people` | `renderPeopleTab()` | Built |
| 9 | — Project ▸ Health tab | `health` | `renderHealthTab()` | Built |
| 10 | Activity detail (slide-over panel) | `state.activityPanel` | `renderActivityPanel()` | Built, Barcelona activities only |
| 11 | Add-activity wizard (modal) | `state.addWizardOpen` | `renderWizard()` | Built UI, 7 steps, **does not persist** |
| 12 | Calendar | `calendar` | `renderPlaceholder()` | **Placeholder only** — copy: "A combined view of every deadline, booking and payment across your projects." |
| 13 | People (global) | `people-global` | `renderPlaceholder()` | **Placeholder only** — copy: "Everyone across every project, in one place." |
| 14 | Settings | `settings` | `renderSettings()` | Built as static read-only rows |

### Screen-level notes
- The project detail header shows two buttons — **Share** and **Project settings** — that have no handlers.
- The Projects list has a **New project** button with no handler.
- The Activities tab **Add activity** button opens the wizard (step 1 offers *Activity / Booking / Task / Payment*), but the tab, table columns, and slide-over are all modelled around a single "activity" concept.

---

## 2. Navigation

### Primary navigation (persistent chrome)
Defined twice, once per breakpoint, with the **same five destinations**:

| Item | `data-nav` id | Desktop sidebar label | Mobile bottom-nav label |
|------|--------------|----------------------|-------------------------|
| Dashboard | `dashboard` | Dashboard | Home |
| Projects | `projects` | Projects | Projects |
| Calendar | `calendar` | Calendar | Calendar |
| People | `people-global` | People | People |
| Settings | `settings` | Settings | Settings |

- **Desktop:** left sidebar (`.desktop-only`, `w-60`), fixed. Shows a **"Current project"** shortcut block when `state.projectId` is set. Footer shows avatar "JD" + name "James".
- **Mobile:** sticky top bar (title only) + fixed bottom tab bar (`.mobile-only`). No project shortcut on mobile.
- Breakpoint: 768px (`md`). `.desktop-only` / `.mobile-only` toggled via CSS media queries.

### Secondary navigation
- **Project tabs:** Overview / Activities / Budget / Timeline / People / Health — `state.projectTab`, horizontal, scrollable on overflow.
- **Active-project sidebar link** uses `data-nav="project"`, which sets `state.view = "project"` without changing `state.projectId`.

### Navigation transitions (from `bindEvents()`)
| Trigger | Effect |
|---------|--------|
| `[data-nav]` (except `project`) | `state.view = id` |
| `[data-nav="project"]` | `state.view = "project"` (keeps existing `projectId`) |
| `[data-open-project="<id>"]` (dashboard/projects rows) | sets `projectId`, `projectTab = "overview"`, `view = "project"` |
| `[data-attention="<id>"]` (dashboard/overview attention row) | sets `projectId` (from `data-project`), `view = "project"`, `projectTab = "activities"`, `activityPanel = <id>` |
| `[data-project-tab="<id>"]` | `state.projectTab = id` |
| `[data-activity="<id>"]` | `state.activityPanel = id` (opens slide-over) |
| backdrop / close button | clears `activityPanel` or `addWizardOpen` |

### Not present
- No URL / deep-linking / browser history integration. Refresh always returns to Dashboard.
- No breadcrumb; no explicit "back to project" from the activity panel other than closing it.
- The **"Needs attention"** rows carry a `link: {view:"activity", id:...}` field in `DATA` that is **never read** — the click handler uses `data-attention` + `data-project` attributes instead. Dead data.

---

## 3. Core user flows

Only the following flows are actually wired in the prototype:

1. **Review what needs attention**
   Dashboard → greeting + "You have 3 things that need your attention" → project summary rows → "Needs attention" list → click a row → lands on Project ▸ Activities with the relevant activity slide-over open.

2. **Open a project**
   Dashboard or Projects list → project summary row → Project ▸ Overview.

3. **Browse a project**
   Project detail → switch between the six tabs. Each tab is read-only.

4. **Inspect an activity**
   Activities tab (table row or mobile card) → slide-over panel with financial / responsibility / booking / location / notes sections → close.

5. **Add an activity (UI only)**
   Activities tab → "Add activity" → 7-step wizard (Type → Name → Date & time → Location → Cost → Owner → Review) → "Add activity" button on the final step just closes the modal. **Nothing is created; `wizardData` is discarded.**

6. **Navigate to placeholder areas**
   Calendar / People (global) → empty-state placeholder screen.

### Flows implied by UI but NOT implemented
- Creating a project ("New project" button, no-op).
- Sharing / inviting ("Share" button, no-op).
- Editing project settings ("Project settings" button, no-op).
- Editing any field anywhere (all values are display-only text).
- Marking a payment as made, assigning an owner, adding a booking reference, resolving a health issue.
- Editing settings (Settings screen is static text).

---

## 4. Project structure

From `DATA.projects` — an object keyed by project id (`barcelona`, `wedding`).

### Fields present on **both** projects
| Field | Type | Example (barcelona) | Notes |
|-------|------|---------------------|-------|
| `id` | string | `"barcelona"` | Also the object key |
| `name` | string | `"Barcelona Stag Weekend"` | |
| `dates` | string | `"16–18 May 2027"` | **Free text, not a date range** — un-parseable as-is (en-dash, month name, single string) |
| `progress` | number | `72` | Percent 0–100. Source unknown — see [Derived](#6-derived-information) |
| `budget` | number | `5000` | Currency implied GBP (`money()` uses `en-GB` + `£`) |
| `committed` | number | `4680` | |
| `paid` | number | `3340` | |
| `outstanding` | number | `1340` | |
| `remaining` | number | `320` | |
| `attentionCount` | number | `3` | Barcelona value (3) matches `needsAttention.length`; **Wedding says 5 with no `needsAttention` array** |
| `cover` | string | `"Barcelona"` | Never rendered anywhere. Likely intended as a cover image / theme key |

### Fields present on **barcelona only**
`needsAttention[]`, `upcoming[]`, `activities[]`, `budgetBreakdown[]`, `timeline[]`, `people[]`, `health[]`.

The Wedding project is a **stub**: it renders on the Dashboard and Projects list (summary row only) but opening it would show empty tabs (`renderOverviewTab` etc. would call `.map` on `undefined` and throw). In practice the prototype only ever deep-links into `barcelona`; `renderProject()` falls back to `barcelona` if `state.projectId` is null.

### Structural observations
- A project is a container for: activities, people, a budget (with a category breakdown), a timeline, "needs attention" items, "upcoming" items, and "health" findings.
- There is **no project owner field**, no created/updated timestamps, no status (draft/active/archived), no description, no location, no currency setting at project level.
- "Organizer" exists only as a **person role** inside `people[]`, not as a project attribute.

---

## 5. Activity / commitment structure

`DATA.projects.barcelona.activities[]` — 5 entries (`boat`, `restaurant`, `transfer`, `hotel`, `golf`).

### Fields per activity
| Field | Type | Example | Used in | Notes |
|-------|------|---------|---------|-------|
| `id` | string | `"boat"` | table/panel keys | |
| `name` | string | `"Boat Party"` | everywhere | |
| `date` | string | `"Sat 16 May"` | table, panel | Free text; format varies (`"Fri 15 May"`, `"Check-in 15:00"` appears in `time`) |
| `time` | string | `"11:00–15:00"` | panel | Free text; sometimes a range, sometimes `"14:00"`, sometimes `"Check-in 15:00"` |
| `owner` | string \| null | `"Mike"` / `null` | table, panel | Plain name string; `null` → "Unassigned" (amber). **Not a reference to `people[]`** |
| `cost` | number | `1200` | table, panel, budget maths | |
| `deposit` | number | `400` | panel | |
| `paid` | number | `400` | panel (`cost - paid` = outstanding) | |
| `status` | string | `"Confirmed"` | badge | Enum-like: `Confirmed`, `Fully Paid`, `Researching`. Also seen: `"Fully Paid"` (hotel). `statusBadge()` only styles `Confirmed` / `Fully Paid` / `Researching`; anything else → grey default |
| `location` | string | `"Port Olímpic, Barcelona"` | panel | Free text |
| `bookingRef` | string | `"ABC123"` / `"—"` | panel | `"—"` used as "empty" sentinel |
| `supplier` | string | `"Barcelona Boats"` / `"—"` | panel | |
| `contact` | string | `"+34 600 123 456"` / `"—"` | panel | |
| `dueDate` | string | `"12 May 2027"` / `"—"` / `"Paid in full"` / `"Pay on arrival"` | panel | **Overloaded** — a date OR a status phrase |
| `participants` | number | `12` | panel | All 5 activities = 12. No link to `people[]` (which has 6 entries) |
| `category` | string | `"Activities"` | **not rendered** | Values: `Activities`, `Food`, `Transport`, `Accommodation`. Note `budgetBreakdown` uses `Accommodation, Activities, Food, Transport, Other` — close but "Food" vs implied categories differ from the restaurant's `category:"Food"` |
| `notes` | string | long text | panel | |
| `prevGap` / `nextGap` | string | `"18 min"` / `"—"` | panel "Location" section | Travel gap to adjacent activities. Precomputed strings, not derived |
| `missingBooking` | bool (optional) | `true` (restaurant) | panel highlights ref in amber | Flag |
| `missingOwner` | bool (optional) | `true` (transfer) | — (not actually read; `owner === null` drives UI) | Redundant flag |

### Observations
- The wizard's **Type** step (Activity / Booking / Task / Payment) implies four *kinds* of commitment, but the data model has only one flat `activities[]` list with no `type`/`kind` field. Everything is an "activity".
- `status` values are inconsistent with payment fields: `hotel` has `status:"Fully Paid"` and also `paid == cost`; `golf` is `"Confirmed"` with `paid:0`. There is no single rule mapping payment state → status.
- No concept of activity date/time as a sortable value; ordering in the table is array order.
- No sub-items, checklists, attachments, or comments on an activity.

---

## 6. People and ownership

### `DATA.projects.barcelona.people[]` — 6 entries
| Field | Type | Example | Notes |
|-------|------|---------|-------|
| `name` | string | `"James"` | First name only; used as identity key |
| `role` | string | `"Organizer"` / `"Participant"` | Two values only |
| `responsibilities` | string[] | `["Airport Transfer","Crazy Golf"]` | **Activity names as free strings**, not ids |
| `paid` | string | `"Fully paid"` / `"Deposit paid"` / `"Owes £70"` | Free text; UI only checks `.startsWith("Owes")` to colour amber |

### Ownership model in the prototype
- Activity **`owner`** is a name string (`"Mike"`), or `null`.
- Person **`responsibilities`** is a list of activity-name strings.
- These two are **maintained independently and can disagree.** e.g. Sarah's `responsibilities` include `"Airport Transfer"`, but `transfer.owner` is `null` and the activity is flagged `missingOwner`. Also `restaurant.owner = "Chris"` and Chris's responsibilities = `["Restaurant"]` (consistent), but nothing enforces this.
- `hotel.owner = "James"`, and James (Organizer) has `responsibilities:["Hotel"]` — consistent.
- The current user is `DATA.user = { name: "James" }`. Sidebar/footer hardcode initials **"JD"** and name **"James"**; Settings screen says **"James Dawson"** / `james@example.com`. Three slightly different identities for the same user.
- `participants` (per activity, always 12) does not match `people.length` (6). "12" also appears as stag-party size in notes. **No participant list per activity.**

### Not present
- No email/phone/avatar for people (settings aside).
- No invitation/membership status, no auth identity, no user-account linkage.
- No notion of a person belonging to multiple projects (though the global People screen copy implies it).
- Wedding project has no `people[]`.

---

## 7. Financial information

### Project-level (both projects carry these five numbers)
`budget`, `committed`, `paid`, `outstanding`, `remaining`.

Rendered in:
- **Dashboard summary row:** `committed` "spent of" `budget`.
- **Project header stat tiles:** `budget`, `committed`, `remaining` (amber if `< 500`), `progress%`.
- **Budget tab:** all five as tiles + `budgetBreakdown[]` as horizontal bars (bar width = amount / max amount).

### Barcelona number check
| Field | Value |
|-------|-------|
| budget | 5000 |
| committed | 4680 |
| paid | 3340 |
| outstanding | 1340 |
| remaining | 320 |

- `paid + outstanding = 4680 = committed` ✓
- `budget - committed = 320 = remaining` ✓
- Sum of `activities[].cost` = 1200 + 600 + 240 + 1800 + 180 = **4020** ≠ committed (4680). **Does not reconcile.**
- Sum of `activities[].paid` = 400 + 600 + 0 + 1800 + 0 = **2800** ≠ paid (3340). **Does not reconcile.**
- `budgetBreakdown` sum = 1800 + 1200 + 900 + 480 + 300 = **4680 = committed** ✓ (but category amounts don't match per-activity costs — e.g. breakdown Activities = 1200 but boat+golf = 1380).

**Conclusion:** project financial totals are authored independently of activities. In production they must be *either* derived from activities *or* explicitly stored as project-level plan figures — [AD-7](#areas-requiring-an-architectural-decision).

### Activity-level
`cost`, `deposit`, `paid`; panel derives `outstanding = cost - paid`. `dueDate` is free text.

### Person-level
`paid` status string only — no amount owed as a number (except embedded in text `"Owes £70"`), no share calculation, no ledger. Three people "Owe £70" — implies a per-head split of some shared cost, but the split logic is not represented.

### Currency
- Hardcoded GBP: `money(n)` = `"£" + n.toLocaleString("en-GB")`.
- Settings shows "Currency: GBP (£)" as a static row.
- No multi-currency, no FX, no per-project currency.

---

## 8. Timeline

Two separate representations, not connected:

### `DATA.projects.barcelona.timeline[]` (Timeline tab)
Array of `{ date: string, items: [{ label: string, type: "payment"|"activity"|"milestone" }] }`.
- `date` is free text (`"12 May"`, `"15 May"`…).
- Rendered as a vertical timeline with a coloured dot per item type (amber=payment, ink=milestone, accent=activity).
- Entries are **hand-authored labels** (`"£800 Boat Party balance due"`), not references to activities or payments.

### `DATA.projects.barcelona.upcoming[]` (Overview tab)
Array of `{ day: string, items: [{ time: string, title: string }] }`.
- `day` free text (`"Friday 15 May"`), `time` free text (`"18:00"`).
- Items like `"Hotel check-in"`, `"Dinner"` — **do not all map to activities** (`"Dinner"` and `"Restaurant"` both appear; `"Hotel check-in"` vs activity `"Hotel"`).

### Observations
- Timeline dates (`"15 May"`, `"16 May"`) sit inside the project's `dates` string `"16–18 May 2027"` — but the timeline references 12 May and 15 May, i.e. **before** the stated project start. Inconsistent.
- No year on timeline/upcoming dates; year only in `dueDate` / project `dates`.
- The Calendar screen (placeholder) is presumably the intended home for a unified cross-project timeline.
- `prevGap`/`nextGap` on activities is a third, activity-local time representation.

---

## 9. Health / issue functionality

### `DATA.projects.barcelona.health[]` — 5 entries
`{ title: string, detail: string, severity: "warning"|"info"|"ok" }`.

| severity | icon | colour | count |
|----------|------|--------|-------|
| `warning` | alert | amber | 3 |
| `info` | alert | grey | 1 |
| `ok` | check | green | 1 |

Rendered in the Health tab as a static list. Copy header: "What might go wrong, and what to do next."

### Relationship to "Needs attention"
- `needsAttention[]` (Dashboard + Overview) is a **different** list: `{ id, title, subject, detail, kind: "payment"|"owner"|"booking", link }`.
- Overlap in meaning but not in data: health "Missing owner — Airport Transfer has no one assigned" ≈ needsAttention "Missing owner / Airport Transfer / No person assigned". Maintained as two hand-authored lists.
- `needsAttention` items are clickable (jump to activity); `health` items are not.
- `attentionCount` (project field) is a **third** hand-maintained number.

### Observations
- No severity for `needsAttention`; no `kind` for `health`.
- Health findings like "no update for 9 days", "18 min gap", "£320 under budget" are **the kind of thing a rules engine would derive**, but here they are static text — [AD-9](#areas-requiring-an-architectural-decision).
- No resolve / dismiss / snooze action. No history.
- `attentionIcon(kind)` ignores its `kind` argument and always renders the same amber alert icon.

---

## 10. Forms and modal flows

### Add-activity wizard (`renderWizard` / `renderWizardStep`)
- Modal, centred, `state.addWizardOpen` + `state.wizardStep` (1–7) + `state.wizardData`.
- `WIZARD_STEPS = ["Type","Name","Date & time","Location","Cost","Owner","Review"]`.
- Step 1: pick a type — **Activity / Booking / Task / Payment** (stored in `wizardData.type`).
- Steps 2–6: single free-text `<input>` fields (name; date+time as one string; location; cost + deposit + due date; owner). No date pickers, no dropdowns, no numeric inputs, no currency handling ("£"+value on review).
- Step 7: read-only review table.
- **No validation.** "Continue" always advances; "Add activity" on step 7 just sets `addWizardOpen = false`. **`wizardData` is never written to `DATA` or anywhere else.**
- Same wizard regardless of chosen type — the type selection has no effect on subsequent steps.
- Dismiss: backdrop click or X button.

### Activity slide-over (`renderActivityPanel`)
- Not a form — display only. Sections: header (name + status badge + date/time + location), Financial, Responsibility, Booking, Location (with prev/next gap), Notes.
- No edit affordance anywhere in the panel.
- Dismiss: backdrop click or X.

### Other "forms"
- **Settings** — rendered as static label/value rows. Not editable, no inputs.
- **New project**, **Share**, **Project settings** — buttons with no modal / no handler.

### Modal/panel mechanics
- Both overlays are re-rendered from scratch on every `render()`; state lives in the `state` object.
- Only one of `activityPanel` / `addWizardOpen` expected at a time (no explicit guard).
- No focus trap, no `Esc` handler, no scroll lock on body.

---

## 11. Existing states

### Application state (`state` object)
```
view:          "dashboard" | "projects" | "project" | "settings"   (also "calendar", "people-global" at runtime)
projectId:     null | "barcelona" | "wedding"
projectTab:    "overview" | "activities" | "budget" | "timeline" | "people" | "health"
activityPanel: null | <activity id>
addWizardOpen: boolean
wizardStep:    1..7
wizardData:    { type, name, date, location, cost, deposit, due, owner }
```
- The `view` comment lists only 4 values but 6 are reachable.
- No loading, error, empty, offline, unauthenticated, or saving states exist anywhere.
- No optimistic updates (nothing updates).

### UI display states that ARE represented
| State | Where | Trigger |
|-------|-------|---------|
| Unassigned owner | activities table, slide-over | `owner === null` → amber "Unassigned" |
| Missing booking ref | slide-over | `missingBooking` → amber "— missing" |
| Empty sentinel `"—"` | slide-over booking/supplier/contact/dueDate | authored literal |
| Outstanding balance | slide-over | `cost - paid > 0` → amber |
| Low remaining budget | project header stat tile | `remaining < 500` → amber |
| Person owes money | People tab | `paid.startsWith("Owes")` → amber |
| Status badge variants | everywhere | `Confirmed`/`Fully Paid`/`Researching` mapped; else grey |
| Health severity | Health tab | `warning`/`info`/`ok` |
| Timeline item type | Timeline tab | `payment`/`activity`/`milestone` dot colour |
| No responsibilities | People tab | empty array → "No responsibilities yet" |
| Active nav item | sidebar / bottom nav / tabs | `state.view` / `state.projectTab` match |
| "Current project" block | sidebar | `state.projectId` set |
| Placeholder / not-built | Calendar, People (global) | `renderPlaceholder()` |

### States NOT represented (and likely needed)
Empty project (no activities), empty attention list ("all clear"), zero projects, wizard field errors, long text truncation, many activities (pagination/scroll), permission-denied, project archived/completed, past-dated project.

---

## 12. Existing static / mock data

Everything under `const DATA`:

- `user`: `{ name: "James" }` (plus hardcoded "JD" / "James Dawson" / "james@example.com" elsewhere).
- `projects.barcelona`: full fixture — 5 activities, 6 people, 3 attention items, 5 health items, 5 budget categories, 4 timeline days, 2 upcoming days.
- `projects.wedding`: summary-only fixture (11 scalar fields, no child collections).
- `Icon`: inline SVG string set (`home`, `projects`, `calendar`, `people`, `settings`, `chevronRight`, `close`, `plus`, `pin`, `alert`, `check`).
- `WIZARD_STEPS`: array of 7 step labels.
- Static strings in `renderSettings()`: `[["Name","James Dawson"],["Email","james@example.com"],["Currency","GBP (£)"],["Notifications","Email + push"]]`.
- Placeholder copy strings for Calendar / People.
- `statusBadge` colour map; `sevStyle` colour map in `renderHealthTab`.
- All dates, money amounts, phone numbers, booking refs, supplier names, notes — fictional.

**Data fields defined but never rendered:** `project.cover`, `project.id` (only used as key), `activity.category`, `activity.missingOwner`, `needsAttention[].link`, `needsAttention[].kind` (only used to pick an icon that ignores it).

---

## 13. Components that must become data-driven

| Prototype function | Currently reads | In production must be backed by |
|--------------------|-----------------|-------------------------------|
| `renderDashboard` greeting + "3 things need attention" | `DATA.user.name`, hardcoded "3" | current user; live count of open attention items across the user's projects |
| `projectSummaryRow` | one project object | project record + rolled-up progress + attention count + financial totals |
| `attentionRow` / "Needs attention" list | `project.needsAttention[]` | derived issue/attention items (per project, per user) |
| `renderProjects` list | `Object.values(DATA.projects)` | projects the current user is a member of |
| `renderProject` header stat tiles | `budget/committed/remaining/progress` | project financials (stored or derived) + progress definition |
| project tabs | static | per-project data loads |
| `renderOverviewTab` "Upcoming" | `project.upcoming[]` | scheduled items derived from activities/timeline within a date window |
| `renderActivitiesTab` table + mobile cards | `project.activities[]` | activity records, sortable/filterable |
| `renderActivityPanel` | one activity | activity record + owner reference + supplier + payments + notes |
| `renderBudgetTab` tiles + breakdown bars | `budget*` fields + `budgetBreakdown[]` | financial summary + category aggregation |
| `renderTimelineTab` | `project.timeline[]` | events derived from activities + payments + milestones |
| `renderPeopleTab` | `project.people[]` | project membership + role + responsibilities + payment status |
| `renderHealthTab` | `project.health[]` | rules-engine output over project state |
| `renderSettings` | 4 hardcoded rows | user profile + preferences |
| `renderWizard` | `state.wizardData` (discarded) | create-activity mutation with validation |
| `renderSidebar` "Current project" + avatar | `state.projectId`, "JD"/"James" | last-opened project (persisted) + authenticated user profile |
| `renderTopbarMobile` titles | static map | route titles including dynamic project name |
| `statusBadge`, `sevStyle` maps | inline enums | shared enum definitions (activity status, issue severity) |
| `money()` | GBP literal | project/user currency |
| Calendar screen | placeholder | cross-project aggregated events |
| People (global) screen | placeholder | people across all the user's projects, deduplicated |

---

## 14. Inconsistencies and ambiguities

### Product identity
- The prototype HTML's `<title>` / wordmark carried a placeholder ("Basecamp"); the file, directory, and repo were originally `Orchestr`. **The product name is now "Orchestrio"** (resolved — see [AD-1](#areas-requiring-an-architectural-decision)). Tagline: "Plan it. Run it. Done."

### User identity
- `DATA.user.name = "James"`; sidebar avatar "JD" + "James"; Settings "James Dawson" / `james@example.com`. Three representations, no single user object.

### Financial reconciliation
- Project totals (`committed`, `paid`) do **not** equal the sum of activity `cost` / `paid` (§7). `budgetBreakdown` sums to `committed` but its category amounts don't match activity costs by category.
- `attentionCount` (Barcelona=3) matches `needsAttention.length`; (Wedding=5) has no list to match.

### Owner vs responsibilities
- Activity `owner` (name string or null) and person `responsibilities` (array of activity-name strings) are duplicated, unlinked, and already contradict each other (Sarah ↔ Airport Transfer, §6).

### Dates
- All dates are free-text strings in multiple formats: `"16–18 May 2027"`, `"24 July 2027"`, `"Sat 16 May"`, `"Fri 15 May"`, `"12 May"`, `"Friday 15 May"`, `"14:00"`, `"Check-in 15:00"`, `"Paid in full"` (in a date field).
- Timeline references 12 & 15 May; project `dates` start at 16 May → timeline predates the project.
- No timezone anywhere (relevant: activities are abroad — Barcelona/CET vs a UK user).

### Enum drift
- `activity.status`: `Confirmed`, `Fully Paid`, `Researching` in data; but "Researching" text elsewhere reads "Researching" and one activity uses free phrasing. `statusBadge` map is the only enum authority.
- `activity.category` (`Activities/Food/Transport/Accommodation`) vs `budgetBreakdown.label` (`Accommodation/Activities/Food/Transport/Other`) — overlapping but separately authored.
- Wizard "Type" (`Activity/Booking/Task/Payment`) has no counterpart field in the data model.

### `dueDate` overloading
- Holds a date (`"12 May 2027"`), or a status (`"Paid in full"`, `"Pay on arrival"`), or empty (`"—"`). Two semantics in one field.

### `"—"` as sentinel
- Empty values are the literal em-dash string, not `null`/`""`. `owner` uses real `null`. Inconsistent empty-value convention.

### Duplicate / dead data
- `needsAttention[].link` never read. `activity.missingOwner` never read (UI keys off `owner===null`). `activity.category`, `project.cover` never rendered.
- Nav item id `people-global` vs `state.view` value — works, but the `view` comment (`dashboard | projects | project | settings`) is stale (omits `calendar`, `people-global`).

### Wedding project
- Renders in lists but has no child collections; opening it in the real prototype flow is avoided. `renderProject()` silently falls back to `barcelona` when `projectId` is null, masking the gap.

### Rendering / engineering
- Full `innerHTML` rebuild + full event re-bind on every interaction. No component isolation, no keys, loses input focus/scroll (wizard inputs re-created on each `render()` — typing works only because `input` events fire before re-render is triggered elsewhere; step navigation re-renders and would drop unsynced state, but fields write to `state` on every keystroke).
- HTML built by string concatenation with no escaping — user-entered `wizardData` and any future dynamic strings are an **XSS risk** if this approach is carried forward.
- Single breakpoint (768px); desktop table has fixed pixel column widths.

---

## Current entities implied by the UI

> These are **implied** by the prototype's data and screens. Naming, keys, and relationships are for analysis only — not a schema. Anything marked ⚠ needs an architectural decision.

| Entity | Evidence | Key attributes visible | Notes |
|--------|----------|------------------------|-------|
| **User / Account** | `DATA.user`, sidebar footer, Settings | name, email, currency pref, notification pref | ⚠ Only one user; no auth model |
| **Project** | `DATA.projects` | id, name, date range (free text), progress %, budget figures, attention count, cover/theme | ⚠ No owner, status, timestamps, currency, description |
| **Activity** (aka Commitment / Item) | `activities[]`, Activities tab, slide-over, wizard | id, name, date, time, owner (name), cost, deposit, paid, status, location, bookingRef, supplier, contact, dueDate, participants count, category, notes, prev/next travel gap | ⚠ Wizard implies 4 sub-types (Activity/Booking/Task/Payment) not in the model |
| **Person / Participant** | `people[]`, People tab | name, role (Organizer/Participant), responsibilities (activity names), payment status (text) | ⚠ Not linked to User; not linked to Activity by id; no contact info |
| **Supplier / Vendor** | activity `supplier` + `contact` | name, contact phone | Implied sub-object of Activity, not a first-class entity yet |
| **Budget line / Category total** | `budgetBreakdown[]` | label, amount | ⚠ Separate from activity costs; category taxonomy undefined |
| **Payment / Due item** | activity `deposit`/`paid`/`dueDate`, timeline `type:"payment"`, needsAttention `kind:"payment"` | amount, due date, paid state | ⚠ No payment entity — only aggregate numbers and text |
| **Timeline event** | `timeline[]` | date, label, type (payment/activity/milestone) | ⚠ Hand-authored, not derived from activities |
| **Upcoming item** | `upcoming[]` | day, time, title | ⚠ Overlaps timeline + activities; separate list |
| **Attention item** | `needsAttention[]` | id, title, subject, detail, kind (payment/owner/booking), link | ⚠ Overlaps Health; separately maintained |
| **Health finding** | `health[]` | title, detail, severity (warning/info/ok) | ⚠ Should probably be derived |
| **Membership** (User×Project) | Projects list = "everything you're planning"; global People screen copy | — | ⚠ Entirely implied, no data |

---

## User actions (complete list from the prototype)

**Wired:**
1. Navigate between Dashboard / Projects / Calendar / People / Settings.
2. Open a project from a summary row.
3. Open a project via the sidebar "Current project" shortcut.
4. Switch project tabs (Overview/Activities/Budget/Timeline/People/Health).
5. Click a "Needs attention" item → jump to its activity.
6. Open an activity slide-over (from Activities table/card).
7. Close the slide-over (backdrop / X).
8. Open the Add-activity wizard.
9. Move through wizard steps (Continue / Back), pick a type, type into fields.
10. "Finish" the wizard (closes it; **no persistence**).
11. Close the wizard (backdrop / X).

**Present in UI, not wired (no handler / no-op):**
12. New project.
13. Share (project).
14. Project settings.
15. Edit anything in Settings.
16. Any edit/save/delete/assign/pay/resolve action on any entity.

---

## Data currently represented (summary)

- **Identity:** one hardcoded user (inconsistently named).
- **Projects:** 2 (one full, one stub). Free-text dates, a progress %, five financial totals, an attention count.
- **Activities:** 5, with scheduling (free text), ownership (name), cost/deposit/paid, status, booking details, supplier + contact, location, travel gaps, notes, category, participant count.
- **People:** 6, with role, responsibility list (by name), payment-status text.
- **Budget:** project totals + 5 category amounts.
- **Timeline:** 4 dated groups of labelled events (3 types).
- **Upcoming:** 2 dated groups of timed items.
- **Attention:** 3 actionable items (3 kinds).
- **Health:** 5 findings (3 severities).
- **Enums (implied):** activity status, issue severity, timeline item type, person role, attention kind, wizard type, budget category.

---

## Relationships implied by the UI

```
User ──(member of / organizes)── Project          [⚠ membership not in data]
Project 1──* Activity
Project 1──* Person                                 [project-scoped people]
Project 1──1 Budget summary 1──* BudgetCategory
Project 1──* TimelineEvent                          [⚠ authored, not derived]
Project 1──* UpcomingItem                           [⚠ overlaps Timeline/Activity]
Project 1──* AttentionItem                          [⚠ overlaps Health]
Project 1──* HealthFinding                          [⚠ should be derived]
Activity *──1 Person (owner)                        [⚠ by name string, nullable]
Activity *──1 Supplier (name+contact inline)        [⚠ not a first-class entity]
Activity 1──* Payment                               [⚠ no payment records — only totals + due text]
Person *──* Activity (responsibilities)             [⚠ by name string; contradicts owner link]
Activity ──(counts)── participants: 12              [⚠ a number, not a set of Person]
```

---

## Derived information

Values the prototype **shows** that in production would be **computed**, not stored (or need an explicit decision to store):

| Shown value | Plausible derivation |
|-------------|---------------------|
| Dashboard "3 things need your attention" | count of open attention/issue items |
| Project `progress` % | ⚠ undefined — could be (confirmed activities / total), (paid / budget), (completed tasks / total), or a manual field |
| `attentionCount` per project | count of that project's attention items |
| Project `committed` | Σ activity cost (currently doesn't reconcile) |
| Project `paid` | Σ activity paid (currently doesn't reconcile) |
| Project `outstanding` | committed − paid |
| Project `remaining` | budget − committed |
| Activity "Outstanding" in slide-over | `cost − paid` (this one IS computed in the view) |
| Low-budget amber flag | `remaining < 500` (threshold hardcoded) |
| Person "Owes £70" | per-head split of shared costs − amount paid |
| `budgetBreakdown` amounts | Σ activity cost grouped by category |
| Timeline / Upcoming entries | activities + payment due dates + milestones within a window, sorted by date |
| Health findings ("no update for 9 days", "18 min gap", "£320 under budget") | rules over activity timestamps, schedule adjacency, and budget |
| `prevGap` / `nextGap` travel time | distance/time between consecutive activity locations |
| "Unassigned" / "missing" flags | null-checks on owner / bookingRef |
| Status badge default (grey) | fallback for unmapped status value |

---

## Areas requiring an architectural decision

| ID | Decision | Why it's open |
|----|----------|---------------|
| **AD-1** | ~~**Product name** and branding.~~ **RESOLVED: the product is "Orchestrio".** (The prototype HTML's placeholder wordmark said "Basecamp"; that was never the name.) | — |
| **AD-2** | **Is "Activity" one entity or several** (Activity / Booking / Task / Payment)? Single table with a `type`, or distinct entities, or Activity-with-optional-booking/payment sub-records? | Wizard offers 4 types; data model has 1 flat list. |
| **AD-3** | **What is `progress`?** Manual field, or derived — and from what? | No formula is expressed anywhere. |
| **AD-4** | **Owner model.** Is an activity owner a project Person, a User, or a free label? How does it relate to Person `responsibilities` (one direction only, or a single join)? | Prototype has two unlinked, contradictory representations. |
| **AD-5** | **Are `Person` and `User` the same thing?** Can a participant have a login? Project-scoped people vs global contacts (global People screen implies global). | Prototype people are project-local, name-only. |
| **AD-6** | **Membership & sharing model** — roles, permissions, invitations. "Share" button + role field (`Organizer`/`Participant`) hint at it; nothing defined. | No membership data at all. |
| **AD-7** | **Financial source of truth.** Are project totals derived from activities/payments, or independently entered plan figures? Both? | Prototype numbers don't reconcile with activities. |
| **AD-8** | **Payment modelling.** First-class Payment records (deposit + balance + schedule + paid-on), or just the current scalar fields? Who-owes-whom / split-cost ledger? | "Owes £70" implies a split engine that isn't modelled. |
| **AD-9** | **Health / attention: derived vs authored.** Rules engine over project state, or user-managed issue list? Are "Needs attention" and "Health" one concept or two? | Three overlapping hand-maintained lists today. |
| **AD-10** | **Date & time model.** Structured dates/times + timezone (activities are abroad) + all-day vs timed + ranges. Replace all free-text date strings. | Every date is unstructured text, inconsistent formats, no year/tz. |
| **AD-11** | **Category taxonomy.** Fixed enum, per-project custom, or tags? Reconcile activity `category` with budget categories. | Two divergent lists. |
| **AD-12** | **Timeline / Upcoming / Calendar** — one derived event stream or separately curated lists? What feeds the (placeholder) global Calendar? | Three representations, one unbuilt. |
| **AD-13** | **Supplier/vendor** as a first-class entity (reusable across activities/projects) or inline fields. | Currently inline strings. |
| **AD-14** | **Participants per activity** — a real set of People, or just a headcount? | Currently a constant number unrelated to `people[]`. |
| **AD-15** | **Multi-project scope for People** (global People screen). Cross-project person identity / dedupe. | Placeholder screen, no data. |
| **AD-16** | **Currency** — per-user, per-project, multi-currency? | Hardcoded GBP. |
| **AD-17** | **Project lifecycle** — draft / active / completed / archived; what happens after the event date passes. | No status field. |
| **AD-18** | **Persistence, auth, and API shape** — the prototype has none. | Greenfield. |
| **AD-19** | **Routing / deep-linking / state restoration** (currently everything resets to Dashboard on reload). | No router. |
| **AD-20** | **Notifications** ("Email + push" in Settings) — channels, triggers, preferences. | Mentioned once, undefined. |

---

## Potential technical risks

1. **Financial figures that don't reconcile.** If production derives totals from activities, the seeded/expected numbers change; if it stores them separately, the two can drift (as they already do). Reconciliation rules and rounding must be defined before any money UI is trusted.
2. **Free-text dates everywhere.** Migrating to structured date/time is invasive — it touches the project header, activities, slide-over, timeline, upcoming, wizard, and all sorting/grouping. Timezone handling for overseas activities is a correctness risk (payment "due" and "check-in" times).
3. **Name-based identity for people/owners.** Duplicate names, renames, and the owner↔responsibilities split will produce inconsistent data. Needs stable ids and a single ownership relationship from day one.
4. **Overloaded / sentinel fields** (`dueDate` holding statuses, `"—"` vs `null`). Carrying these forward pollutes the schema; must be normalised during modelling.
5. **String-concatenated HTML, no escaping.** The current rendering approach is an XSS vector the moment any user text (wizard, notes, names) is displayed. Production must use a framework with auto-escaping / safe templating.
6. **Full re-render + re-bind on every interaction.** Does not scale; loses focus/scroll; no place for async/loading states. A component framework with real state management is required.
7. **"Derived" health/attention content.** If a rules engine is chosen, its cost (recompute frequency, where it runs) and explainability need design; if authored, someone must maintain it and the demo's "smart" feel is lost.
8. **Wedding stub / silent fallback.** `renderProject()` falling back to `barcelona` hides missing-data bugs — production must handle genuinely empty projects and missing collections explicitly.
9. **Single breakpoint & fixed-width desktop table.** Activities table uses fixed pixel columns; real data (long names, many rows, more columns once "type" exists) will overflow. Needs a responsive/data-grid strategy.
10. **No pagination / virtualization anywhere.** Lists assume a handful of items (5 activities, 6 people). Real projects (weddings especially) will have many more.
11. **Enum authority lives in view code** (`statusBadge`, `sevStyle`, dot colours). Without a shared definition, statuses/severities will drift between API and UI.
12. **Progress metric undefined (AD-3).** Any choice changes what the headline number means; stakeholders may assume different definitions.
13. **`participants: 12` vs 6 people.** If participants becomes a real relation, existing "12" is meaningless; if it stays a count, it can contradict the People tab.
14. **No optimistic-update / conflict story.** Collaborative planning (multiple organizers) implies concurrent edits; nothing in the prototype anticipates it.

---

## What should NOT be carried directly into the production architecture

- **The `DATA` shape as a schema.** It is a view-model fixture, not a data model — denormalised, name-keyed, with computed values stored as literals that don't reconcile.
- **Free-text date/time strings** (`"Sat 16 May"`, `"16–18 May 2027"`, `"Check-in 15:00"`). Replace with structured, timezone-aware values.
- **`"—"` as an empty-value sentinel** and **`dueDate` overloaded** with status phrases. Normalise to nullable typed fields.
- **Owner as a name string + parallel `responsibilities` name-array.** Collapse into one id-based ownership relationship (see AD-4).
- **Three separate hand-maintained "something's wrong" lists** (`needsAttention`, `health`, `attentionCount`). Decide one model (AD-9).
- **Three separate schedule representations** (`timeline`, `upcoming`, activity `date/time` + `prevGap/nextGap`). Derive from one source (AD-12).
- **Project financial totals as authored constants** independent of activities/payments (AD-7).
- **`participants: 12` as a magic number** unrelated to the people list (AD-14).
- **Hardcoded user identity** ("James" / "JD" / "James Dawson" / `james@example.com`) and hardcoded currency (GBP).
- **The rendering strategy** — `innerHTML` rebuild, string-concatenated unescaped HTML, global re-bind. Rebuild on a component framework.
- **Placeholder screens (Calendar, global People) as if they define scope.** Their copy is a hint, not a spec — treat as AD-12 / AD-15.
- **`cover` / theme keys, `category` field, `missingOwner` flag, `needsAttention.link`** — dead fields; don't reintroduce without a purpose.
- **Wizard-as-spec.** The wizard collects 6 free-text fields and throws them away; it is not a definition of the create-activity contract. In particular its 4 "types" are unresolved (AD-2).
- **The prototype's placeholder wordmark "Basecamp".** The product is **Orchestrio** (AD-1, resolved).
- **Threshold magic numbers** (`remaining < 500`, "9 days", "18 min") baked into views.

---

## Appendix: file map

| Lines | Contents |
|-------|----------|
| 10–54 | CSS custom properties (palette) + animations + responsive helpers |
| 60–146 | `DATA` — all fixtures |
| 148–161 | `state` object + `money()` |
| 166–178 | `Icon` SVG set |
| 183–195 | `statusBadge()`, `attentionIcon()` |
| 200–280 | Shell: `render()`, sidebar, mobile topbar, bottom nav |
| 285–306 | Route switch + `renderPlaceholder()` |
| 308–364 | Dashboard + `projectSummaryRow` + `attentionRow` |
| 366–381 | Projects list |
| 383–428 | Project detail shell + tabs + `statTile` |
| 430–597 | Six project tab renderers |
| 599–612 | Settings |
| 617–685 | Activity slide-over |
| 690–753 | Add-activity wizard (7 steps) |
| 758–823 | `bindEvents()` — all interaction handlers |
| 825 | `render()` bootstrap |
