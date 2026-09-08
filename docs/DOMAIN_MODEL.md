# Production Domain Model

**Status:** Draft for review
**Date:** 2026-09-04
**Source material:** [`docs/PROTOTYPE_ANALYSIS.md`](./PROTOTYPE_ANALYSIS.md) and [`orchestr-prototype.html`](../orchestr-prototype.html)
**Scope of this document:** define the production domain model — persistent entities, relationships, derived systems, and deferred functionality. This document deliberately stops short of a database schema, but is intended to be detailed enough that a schema can be derived from it mechanically, without re-opening product questions.

**Non-goals:** no Supabase tables, no migrations, no code, no API design, no UI redesign.

---

## 1. How to read this document

The product is a **collaborative planning and execution platform**: small groups plan an event or trip together, divide up who is responsible for what, track money, and work through everything until it is done ("Plan it. Run it. Done.").

Everything below is sorted into four buckets, per the architectural goal:

| Bucket | Meaning | Rule of thumb |
|--------|---------|---------------|
| **1. Persistent entity** | A record that is the source of truth for something a user created or decided. | If losing it would lose user intent, it is persisted. |
| **2. Relationship** | A link between entities. May be a foreign key or a join record. | Model as a join record when the link itself carries data or history. |
| **3. Derived / calculated** | Computed on demand (or cached) from persistent entities. Never edited directly. | If two people editing it independently makes no sense, it is derived. |
| **4. Future functionality** | Implied by the prototype or the product vision but **out of scope** for the first schema. | Named here so the model leaves room for it, not so it gets built. |

Where the prototype analysis raised an **Architectural Decision (AD-n)**, this document either **resolves it** (with reasoning) or **carries it forward** as a residual product decision in [§11](#11-residual-product-decisions).

Conceptual types used below: `id` (UUID), `text`, `enum(...)`, `money` (integer minor units + currency code), `date`, `timestamp`, `bool`, `int`, `ref→Entity` (foreign key), `[value object]` (embedded, no independent identity).

---

## 2. Modelling principles

1. **Persist intent, derive consequences.** Users decide "the boat party costs £1,200 and Mike owns it". They do not decide "the project is 72% complete" or "the timeline has a gap" — those are read-outs. Consequences are derived.
2. **One fact, one place.** The prototype stores ownership twice (activity `owner` string + person `responsibilities[]` array) and they already disagree. Every fact has exactly one authoritative location; everything else is a query.
3. **Identity by reference, never by name.** People, owners, participants, and payers are all references to a single project-scoped identity record, never free-text names.
4. **Money is events, not columns.** A commitment's financial life is a stream of `Payment` records, not a `paid` scalar and an overloaded `dueDate` string.
5. **Budget, Timeline, and Health are systems, not tables.** They are evaluated below as derived views. Only their *inputs* (budget targets, dismissals) are persisted.
6. **Nullable, not sentinel.** No `"—"` strings. Absent values are null and carry defined UI meaning ("unassigned", "no reference yet").
7. **Structured time.** All dates/times are typed and timezone-aware. No free-text date strings anywhere in the model.
8. **Soft-delete where history matters.** Projects, members, commitments, and payments are soft-deleted so that historical ownership and money references stay intact.
9. **Every record carries `created_at` / `updated_at`.** The health engine depends on `updated_at` (the "inactive commitment" rule), so this is a modelling requirement, not a convention.

---

## 3. Decision: is the core concept "Activity" or "Commitment"?

This decision sets the name and the shape of the single most important entity in the system, so it is worked through in full.

### 3.1 What the prototype actually contains

The prototype's `activities[]` for the Barcelona project holds five items: **Boat Party, Restaurant, Airport Transfer, Hotel, Crazy Golf**. The "Add" wizard's first step offers four *types*: **Activity / Booking / Task / Payment**. The concept list for this exercise separately names **Tasks** and **Milestones**.

So the prototype already can't decide whether "activity" is:
- the umbrella for every line item in a plan, **or**
- one *kind* of line item (the fun, experiential kind) sitting next to bookings, tasks, and payments.

That ambiguity is [AD-2](./PROTOTYPE_ANALYSIS.md#areas-requiring-an-architectural-decision) and it must be resolved before anything else.

### 3.2 What every line item has in common

Looking across boat party, restaurant, transfer, hotel, golf — and plausible future items like travel insurance, a group gift collection, a visa run, a villa cleaning fee:

| Shared invariant | Evidence in prototype |
|------------------|-----------------------|
| It belongs to exactly one project | `activities` nested under a project |
| Someone is — or should be — **accountable** for it | `owner` field; "Missing owner" is both a *health* finding and a *needs-attention* item |
| The group is **collectively on the hook** for it (socially and financially) | shared budget, "Owes £70" per person |
| It moves through a **lifecycle** from vague idea to done | `status`: Researching → Confirmed → (Fully Paid) |
| It **may** cost money, **may** have a schedule slot, **may** have a location, **may** need a booking | every one of these is optional and partially filled across the five items |

The single thing that is *always* true and *always* central is **accountability**: who has taken this on, and what has the group committed itself to. "Missing owner" is the headline risk in the prototype. The experiential nature ("an activity you do") is true for only three of the five items and is incidental.

### 3.3 Option A — keep "Activity" as the primary domain term

**Model:** one `Activity` entity, with a `type`/`category` discriminator, that is also the umbrella term.

| Consequence | Assessment |
|-------------|------------|
| Zero relabelling; matches current UI ("Activities" tab, "Add activity"). | ➕ Real short-term benefit. |
| "Activity" is semantically wrong for Hotel, Airport Transfer, travel insurance, deposits, admin. Users filing a *flight booking* under "Activities" is odd and gets worse as the product covers more of the plan. | ➖ Permanent low-grade friction. |
| The umbrella-vs-leaf ambiguity (AD-2) is not resolved — "activity" still means both "any line item" and "the fun kind". Team conversations and code stay ambiguous. | ➖ The core problem persists. |
| Payment and Task, offered as peer "types" in the wizard, tend to get modelled as awkward siblings of Activity (parallel top-level tables), so Budget/Timeline/Health must aggregate across three unrelated things. | ➖ More surface area, more bugs. |
| "Who is accountable for what" — the execution loop — has no natural noun. You end up saying "activity ownership" which sounds like a permissions concept. | ➖ Weakens the product's own framing. |

### 3.4 Option B — "Commitment" is the underlying concept

**Model:** one `Commitment` entity is the base for every planned line item. It has a `kind` (accommodation, transport, food, experience, services, other). **Payment is not a kind** — it is a financial event *attached to* a commitment. **Task is a separate, lighter concept** — subordinate work, often a child of a commitment. **Milestone is mostly derived** (see [§7.2](#72-milestone)).

| Consequence | Assessment |
|-------------|------------|
| One noun covers every line item that exists now and every one we can foresee — experiences, bookings, logistics, admin, fees. The domain term describes the whole set. | ➕ Correct by construction. |
| Names the invariant the product is actually about: accountability and collective obligation. "Commitment ownership", "unowned commitment", "overdue commitment" all read naturally and map onto existing health rules. | ➕ Strengthens the model and the product story ("Run it"). |
| Resolves AD-2: "commitment" is unambiguously the umbrella; `kind` values (which *may* include one literally called "activity") are unambiguously the leaves. | ➕ Kills the ambiguity. |
| Forces the right call on the wizard's four "types": Payment is demoted to a financial event; Task is separated as lighter work; only genuine line items remain. | ➕ Corrects a prototype mistake. |
| "Commitment" is mild jargon for end users. | ➖ Mitigated: the **UI label is a separate, reversible presentation choice** — the product can display "Activity", "Item", "Plan item", or "Commitment". The domain / API / schema / team vocabulary is `Commitment` regardless. |
| Requires the team and all docs to adopt the term consistently from now. | ➖ One-time cost, paid now while the codebase is empty. |
| Risk of over-abstraction if Task and Commitment were forced into one table. | ➖ Avoided — Task is kept **separate** precisely because it is lighter (no cost identity, no participants, no booking, has a done-state). |

### 3.5 Recommendation

**Adopt `Commitment` as the core domain entity and the primary domain term.**

- The domain, the schema, the API, and all internal language use **Commitment**.
- **Payment**, **Task**, and **Milestone** are distinct concepts, not `kind`s of Commitment (reasoning in their sections).
- A Commitment has a **`kind`** enum for classification and budget grouping.
- The **user-facing label is a product/UX decision** and is explicitly *not* settled here. Recommended default for continuity: keep calling it **"Activity"** in the UI initially. This costs nothing in the model — it is a single glossary mapping (`Commitment` ⇄ displayed as "Activity") — and can change without touching the schema. Carried forward as [residual decision D-1](#11-residual-product-decisions).

The rest of this document uses **Commitment**.

---

## 4. Domain model at a glance

```
                        ┌──────────┐
                        │   User   │  (global auth identity)
                        └────┬─────┘
                             │ may claim
                             │ 0..*
                        ┌────┴───────────┐        ┌──────────────┐
              ┌─────────│  ProjectMember │────────│  Invitation  │
              │ 1..*    └────┬───────────┘  1..*  └──────────────┘
              │              │ belongs to
        ┌─────┴────┐    1    │ 1
        │  Project │─────────┤
        └─────┬────┘         │
   1 │  │  │  │  │ 1         │ referenced as owner / participant / payer / assignee
     │  │  │  │  │           ▼
     │  │  │  │  └──────► Budget (targets only)         ── actuals DERIVED
     │  │  │  │
     │  │  │  └─────────► Milestone (thin, manual)
     │  │  │
     │  │  └────────────► Task ──────────► (opt) Commitment
     │  │                                        ▲
     │  └───────────────► Commitment ────────────┘
     │                       │ 1
     │                       ├── 1..* Payment ──────► (opt) ProjectMember (payer)
     │                       ├── 0..* CommitmentParticipant ──► ProjectMember
     │                       ├── 0..* CostShare ──────────────► ProjectMember
     │                       ├── 0..1 [Location value object]
     │                       └── 0..1 [Booking value object: supplier, ref, contact]
     │
     └── DERIVED SYSTEMS (no tables): Timeline, Health/Risk findings,
         progress %, per-member balances, budget actuals, travel gaps
```

---

## 5. Persistent entities

Each entity documents: **Purpose · Represents · Persistence · Key attributes · Relationships · Lifecycle · Ownership & permissions · Notes/decisions.**

---

### 5.1 User

- **Purpose:** authentication identity and cross-project account.
- **Represents:** a real person who can log in. Distinct from their presence in any one project.
- **Persistence:** persisted.
- **Key attributes:**

| Attribute | Type | Notes |
|-----------|------|-------|
| `id` | id | |
| `email` | text, unique | login identity |
| `display_name` | text | |
| `avatar_url` | text, nullable | |
| `default_currency` | enum(ISO 4217) | seeds new projects; prototype implies `GBP` |
| `notification_prefs` | [value object] | channels on/off; prototype Settings shows "Email + push" — [future detail](#10-future-functionality) |
| `timezone` | text (IANA) | for rendering times |
| `created_at` / `updated_at` | timestamp | |

- **Relationships:** `User 1 ──0..* ProjectMember` (a user claims one membership per project). No direct link to Project, Commitment, etc. — always via `ProjectMember`.
- **Lifecycle:** `pending` (invited, not yet signed up) → `active` → `suspended` → `deleted` (soft).
- **Ownership:** self. A user edits only their own record.
- **Notes/decisions:**
  - The prototype's three inconsistent identities ("James" / "JD" / "James Dawson" / `james@example.com`) collapse into one `User` plus per-project `ProjectMember.display_name`.
  - Resolves the identity half of [AD-5](./PROTOTYPE_ANALYSIS.md#areas-requiring-an-architectural-decision).

---

### 5.2 Project

- **Purpose:** the top-level container and unit of collaboration, permissions, and billing.
- **Represents:** one thing being planned — a trip, a wedding, an event.
- **Persistence:** persisted.
- **Key attributes:**

| Attribute | Type | Notes |
|-----------|------|-------|
| `id` | id | |
| `name` | text | "Barcelona Stag Weekend" |
| `description` | text, nullable | not in prototype; low-cost addition |
| `starts_on` | date, nullable | **replaces** the free-text `dates` string |
| `ends_on` | date, nullable | |
| `timezone` | text (IANA) | the event's timezone (Barcelona ≠ organiser's home) — see [§8.9](#89-timeline-generation) |
| `currency` | enum(ISO 4217) | **one currency per project** (multi-currency = future); defaults from creator's `User.default_currency` |
| `status` | enum(`draft`,`active`,`completed`,`archived`) | resolves [AD-17]; `completed` set manually or suggested once `ends_on` passes |
| `cover_theme` | text, nullable | the prototype's unused `cover` field, kept as an optional visual key only |
| `created_by` | ref→User | audit only; control is via memberships |
| `created_at` / `updated_at` / `archived_at` | timestamp | |

- **Relationships:**
  - `Project 1 ──1..* ProjectMember`
  - `Project 1 ──0..* Commitment`
  - `Project 1 ──0..* Task`
  - `Project 1 ──0..* Milestone`
  - `Project 1 ──0..1 Budget`
- **Lifecycle:** `draft` (being set up) → `active` → `completed` (event happened) → `archived` (read-mostly). Soft-delete separate from archive.
- **Ownership:** owned collectively by its members with the `organizer` role. At least one organizer must always exist.
- **Notes/decisions:**
  - No stored `progress`, `budget*` totals, or `attentionCount` — all derived ([§7](#7-derived-systems)).
  - No `owner` column — ownership is expressed through `ProjectMember.role`.

---

### 5.3 ProjectMember

- **Purpose:** a person's identity **within one project**. The pivot of the entire model: owners, participants, payers, and assignees are all `ProjectMember` references.
- **Represents:** "someone involved in this project" — whether or not they have a login yet.
- **Persistence:** persisted.
- **Key attributes:**

| Attribute | Type | Notes |
|-----------|------|-------|
| `id` | id | |
| `project_id` | ref→Project | |
| `user_id` | ref→User, nullable | set when the person signs up / accepts an invite; **null = a named person who can't log in yet** |
| `display_name` | text | "Mike" — always present, even without a `user_id` |
| `email` | text, nullable | used to match a future invite acceptance |
| `role` | enum(`organizer`,`member`,`viewer`) | base permission tier (finer permissions = future, [AD-6]) |
| `status` | enum(`invited`,`active`,`removed`) | |
| `invited_at` / `joined_at` / `removed_at` | timestamp | |
| `created_at` / `updated_at` | timestamp | |

- **Relationships:**
  - `ProjectMember *──1 Project`
  - `ProjectMember 0..1 ──1 User`
  - referenced by `Commitment.owner_member_id`, `CommitmentParticipant.member_id`, `CostShare.member_id`, `Payment.paid_by_member_id`, `Task.assignee_member_id`.
- **Lifecycle:** `invited` → `active` (accepted, or added directly by an organizer as a name-only member) → `removed` (soft; references preserved, rendered as "former member").
- **Ownership:** the project (managed by organizers). A member with a linked `user_id` may edit their own `display_name`/`email`.
- **Notes/decisions:**
  - **Resolves [AD-4] and [AD-5]:** there is exactly one identity type for "people in a project". A name-only participant ("Tom", who owes £70 and never logs in) is a `ProjectMember` with `user_id = null`.
  - Prototype `people[].role` had only `Organizer` / `Participant`; `viewer` is added for read-only sharing (the "Share" button).
  - Prototype `people[].responsibilities[]` is **deleted as stored data** — it becomes the query "commitments where `owner_member_id = me`" ([§8.2](#82-commitment-ownership)).
  - Prototype `people[].paid` status text is **deleted** — replaced by a derived per-member balance ([§8.8](#88-budget-calculations)).

---

### 5.4 Invitation

- **Purpose:** manage a pending request for someone to join a project before they have accepted.
- **Represents:** "we've asked this email address to join as a `member`".
- **Persistence:** persisted.
- **Key attributes:** `id`, `project_id ref→Project`, `email text`, `role enum`, `invited_by ref→ProjectMember`, `token text`, `status enum(pending,accepted,expired,revoked)`, `expires_at`, `created_at`, `accepted_at`.
- **Relationships:** `Invitation *──1 Project`. On acceptance, links/creates a `ProjectMember` and sets its `user_id`.
- **Lifecycle:** `pending` → `accepted` | `expired` | `revoked`.
- **Ownership:** organizers of the project.
- **Notes/decisions:** Minimal but required for the collaboration story ("Share" button, prototype). Bulk invite, invite links, and approval flows are [future](#10-future-functionality). Partially addresses [AD-6].

---

### 5.5 Commitment

- **Purpose:** the core unit of planning and execution — a single line item the group has taken on.
- **Represents:** boat party, restaurant, airport transfer, hotel, crazy golf — and any future experience, booking, logistical arrangement, service, or fee.
- **Persistence:** persisted.
- **Key attributes:**

| Attribute | Type | Notes |
|-----------|------|-------|
| `id` | id | |
| `project_id` | ref→Project | |
| `title` | text | "Boat Party" |
| `kind` | enum(`accommodation`,`transport`,`food`,`experience`,`services`,`other`) | **replaces** prototype `category`; **also the budget category** — reconciles the two divergent lists in [AD-11]. "Activities" → `experience` |
| `status` | enum(`idea`,`researching`,`confirmed`,`booked`,`completed`,`cancelled`) | explicit, user-set lifecycle. Prototype "Researching"→`researching`, "Confirmed"→`confirmed`. **"Fully Paid" is NOT here** — it is a derived payment flag |
| `owner_member_id` | ref→ProjectMember, nullable | **the single source of ownership.** null = "Unassigned" |
| `estimated_cost` | money, nullable | while `researching` |
| `confirmed_cost` | money, nullable | once a price is locked; UI shows `confirmed_cost ?? estimated_cost` |
| `starts_at` | timestamp, nullable | structured; nullable because not every commitment is scheduled (e.g. travel insurance) |
| `ends_at` | timestamp, nullable | |
| `is_all_day` | bool | |
| `schedule_note` | text, nullable | e.g. "Check-in from 15:00" — free text that the prototype crammed into `time` |
| `location` | [Location value object], nullable | see [§8.7](#87-locations) |
| `booking` | [Booking value object], nullable | see below |
| `notes` | text, nullable | prototype `notes` |
| `created_by` | ref→ProjectMember | |
| `created_at` / `updated_at` | timestamp | `updated_at` feeds the "inactive" health rule |
| `deleted_at` | timestamp, nullable | soft-delete |

- **Booking value object** (embedded; replaces prototype `bookingRef` / `supplier` / `contact` / `missingBooking`): `supplier_name text?`, `supplier_contact text?`, `reference text?`, `confirmed bool` (default false). "Missing booking reference" becomes `booking.confirmed = false OR booking.reference IS NULL` — a derived health finding, not a stored flag.

- **Relationships:**
  - `Commitment *──1 Project`
  - `Commitment *──0..1 ProjectMember` (owner)
  - `Commitment 1 ──0..* CommitmentParticipant`
  - `Commitment 1 ──0..* CostShare`
  - `Commitment 1 ──0..* Payment`
  - `Commitment 1 ──0..* Task` (optional parent)
  - `Commitment 0..1 [Location]`, `0..1 [Booking]` (embedded)

- **Lifecycle:**
  `idea` → `researching` → `confirmed` → `booked` → `completed`; `cancelled` reachable from any state.
  Transitions are **user-driven**. The system may *suggest* a transition (e.g. "all payments settled — mark as booked?") but does not force one. `completed` may be auto-suggested after `ends_at` passes.
  Derived, layered on top (not stored as status): `payment_status ∈ {unpaid, deposit_paid, part_paid, paid_in_full}` and `has_open_issues bool`.

- **Ownership & permissions:** the project. Editable by the `owner_member_id`, any `organizer`, and (default policy) any `member`. `viewer` cannot edit. Fine-grained field-level permissions = future.

- **Notes/decisions:**
  - **Participants are a real set, not a number.** Prototype `participants: 12` (a constant unrelated to the 6-person `people[]`) becomes `count(CommitmentParticipant)` — derived. Resolves [AD-14].
  - **`prevGap` / `nextGap`** (travel time to adjacent commitments) are **derived** ([§8.7](#87-locations)), never stored.
  - **`missingOwner` flag** deleted — it is just `owner_member_id IS NULL`.
  - Supplier stays embedded until a supplier directory is a real feature ([AD-13] → resolved: embed now, promote later; see [§8.7](#87-locations)).

---

### 5.6 CommitmentParticipant

- **Purpose:** record who is involved in / attending a specific commitment.
- **Represents:** "Mike, Chris, and Tom are on the boat party".
- **Persistence:** persisted (join record — carries its own data, so not a bare FK array).
- **Key attributes:** `id`, `commitment_id ref→Commitment`, `member_id ref→ProjectMember`, `rsvp enum(going,maybe,not_going,unknown)` (default `unknown`; RSVP UI itself is [future](#10-future-functionality) but the column is cheap and shapes CostShare), `added_at`, `added_by ref→ProjectMember`.
- **Relationships:** connects one `Commitment` and one `ProjectMember`. Unique on `(commitment_id, member_id)`.
- **Lifecycle:** created when someone is added to a commitment; deleted when removed; cascades on either parent's deletion.
- **Ownership:** the commitment's owner / organizers.
- **Notes/decisions:**
  - Default on commitment creation is configurable: *no participants* or *all active project members*. Recommended default: **all active members** (matches the prototype's "everyone" assumption) — carried forward as [residual decision D-2](#11-residual-product-decisions).
  - Participation drives the **default** cost split ([§8.4](#84-payment-modelling)).

---

### 5.7 CostShare

- **Purpose:** record **how a commitment's cost is divided** among members — the basis for "who owes what".
- **Represents:** "the €1,200 boat is split equally among the 12 going" or "Sarah covers the whole transfer".
- **Persistence:** persisted **only when non-default**. If absent, the system assumes an equal split across current participants.
- **Key attributes:** `id`, `commitment_id ref→Commitment`, `member_id ref→ProjectMember`, `basis enum(equal,weight,fixed)`, `weight numeric, nullable`, `fixed_amount money, nullable`, `created_at`, `updated_at`.
- **Relationships:** `CostShare *──1 Commitment`, `*──1 ProjectMember`. Unique on `(commitment_id, member_id)`.
- **Lifecycle:** created/edited when someone overrides the default split; recalculated (if `basis=equal`) when participants change, unless a member's share was explicitly fixed.
- **Ownership:** commitment owner / organizers.
- **Notes/decisions:**
  - This is the minimum needed to reproduce the prototype's "Owes £70". Full **settlement** ("Tom pays Mike £40 to square up") is [future](#10-future-functionality).
  - Keeping this separate from `Payment` is deliberate: **CostShare = who is responsible for which slice; Payment = money that actually moved.** A member's balance is the difference between the two ([§8.8](#88-budget-calculations)).
  - Whether cost-sharing is modelled per-commitment (recommended, flexible) or only as one project-wide equal split is [residual decision D-3](#11-residual-product-decisions). The entity above supports both; the simple case is "no CostShare rows anywhere".

---

### 5.8 Payment

- **Purpose:** represent one planned or actual movement of money for a commitment.
- **Represents:** "£400 deposit, paid 3 Feb by Mike"; "£800 balance, due 12 May, not yet paid".
- **Persistence:** persisted.
- **Key attributes:**

| Attribute | Type | Notes |
|-----------|------|-------|
| `id` | id | |
| `commitment_id` | ref→Commitment | payments always belong to a commitment |
| `type` | enum(`deposit`,`balance`,`installment`,`full`,`refund`) | |
| `amount` | money | positive; `refund` represents money coming back |
| `direction` | enum(`outgoing`,`incoming`) | default `outgoing`; `incoming` for refunds / collections |
| `status` | enum(`scheduled`,`paid`,`waived`,`cancelled`) | `due` / `overdue` are **derived** from `due_on` + today, not stored |
| `due_on` | date, nullable | **replaces** the overloaded `dueDate` string; null = "no due date" (e.g. "pay on arrival") |
| `paid_on` | date, nullable | set when `status=paid` |
| `paid_by_member_id` | ref→ProjectMember, nullable | who actually paid |
| `method` | text, nullable | free text for now (`bank transfer`, `card`); enum = future |
| `reference` | text, nullable | transaction reference |
| `notes` | text, nullable | |
| `created_by` | ref→ProjectMember | |
| `created_at` / `updated_at` | timestamp | |

- **Relationships:** `Payment *──1 Commitment`; `Payment *──0..1 ProjectMember` (payer).
- **Lifecycle:** `scheduled` → `paid` | `waived` | `cancelled`. `overdue` is a derived display state (`status=scheduled AND due_on < today`). Edits after `paid` are allowed but audited.
- **Ownership:** the commitment's owner / organizers; the `paid_by_member_id` may edit their own payment.
- **Notes/decisions:**
  - **Replaces** prototype `activity.deposit`, `activity.paid`, and `activity.dueDate` entirely. Resolves the [AD-8] payment-modelling question and the `dueDate` overload.
  - "Deposit £400 paid, balance £800 due 12 May" = two `Payment` rows. "Paid in full" = every non-cancelled Payment is `paid` and their sum ≥ `confirmed_cost`.
  - "Payment due" in *Needs Attention* and "£800 Boat Party balance due" on the *Timeline* both read from the same `Payment` rows ([§8.9](#89-timeline-generation), [§8.10](#810-healthrisk-detection)).
  - Payment **collection** (actually taking money from members through the platform) is explicitly [future](#10-future-functionality) — this entity only *records* money movement.

---

### 5.9 Task

- **Purpose:** a small unit of work needed to move the plan forward — a checklist item.
- **Represents:** "Chase the restaurant for a confirmation number"; "Book minibus"; "Send the packing list".
- **Persistence:** persisted.
- **Key attributes:**

| Attribute | Type | Notes |
|-----------|------|-------|
| `id` | id | |
| `project_id` | ref→Project | a task always belongs to a project |
| `commitment_id` | ref→Commitment, nullable | optional parent — most tasks hang off a commitment |
| `title` | text | |
| `status` | enum(`open`,`in_progress`,`done`,`cancelled`) | |
| `assignee_member_id` | ref→ProjectMember, nullable | |
| `due_on` | date, nullable | |
| `notes` | text, nullable | |
| `created_by` | ref→ProjectMember | |
| `created_at` / `updated_at` / `completed_at` | timestamp | |

- **Relationships:** `Task *──1 Project`; `Task *──0..1 Commitment`; `Task *──0..1 ProjectMember` (assignee).
- **Lifecycle:** `open` → `in_progress` → `done`; `cancelled` from any state.
- **Ownership:** creator, assignee, organizers.
- **Notes/decisions:**
  - **Kept separate from Commitment** (see [§3.4](#34-option-b--commitment-is-the-underlying-concept)): a task has no cost identity, no participants, no booking, no financial lifecycle, and has a binary done-state a commitment does not. Merging them would mean a wide table of mostly-null columns.
  - The wizard's "Task" type is honoured here as its own entity.
  - Tasks with a `due_on` appear on the Timeline ([§8.9](#89-timeline-generation)). An overdue task is a health finding ([§8.10](#810-healthrisk-detection)).
  - Sub-tasks, recurring tasks, comments, and checklists-within-tasks are [future](#10-future-functionality).

---

### 5.10 Milestone

- **Purpose:** a user-pinned significant date that is **not** already implied by a commitment or payment.
- **Represents:** "RSVP deadline", "Final numbers to caterer", "Passports must be valid until".
- **Persistence:** persisted, but **thin and optional**. Most dated markers on the timeline are *derived*, not milestones (see [§7.2](#72-milestone)).
- **Key attributes:** `id`, `project_id ref→Project`, `title text`, `on_date date`, `commitment_id ref→Commitment nullable` (optional link), `notes text nullable`, `created_by ref→ProjectMember`, `created_at` / `updated_at`.
- **Relationships:** `Milestone *──1 Project`; `Milestone *──0..1 Commitment`.
- **Lifecycle:** trivial — `upcoming` vs `passed` is derived purely from `on_date`. Manually created / edited / deleted.
- **Ownership:** organizers.
- **Notes/decisions:**
  - The prototype's timeline `type:"milestone"` items ("Checkout", project end) are **derived from `Project.ends_on` and commitment schedules**, *not* `Milestone` rows.
  - `Milestone` exists only for dates a user wants to track that have no other home.
  - **Open question:** a manual milestone and an unassigned `Task` with a `due_on` and no assignee are nearly identical. They are kept separate for now because milestones are not "worked" or "completed". Merging `Milestone` into `Task` (as `is_milestone`) is [residual decision D-4](#11-residual-product-decisions).

---

### 5.11 Budget

- **Purpose:** store the project's financial **plan** — the targets only.
- **Represents:** "total budget £5,000; roughly £1,800 for accommodation".
- **Persistence:** persisted — but **only targets**. Every "actual" figure is derived ([§7.1](#71-budget)).
- **Key attributes:**
  - `Budget`: `id`, `project_id ref→Project` (1:1), `total_target money, nullable`, `created_at`, `updated_at`.
  - `BudgetCategoryTarget` (child): `id`, `budget_id ref→Budget`, `kind enum` (same enum as `Commitment.kind`), `amount money`. Unique on `(budget_id, kind)`.
- **Relationships:** `Project 1 ──0..1 Budget`; `Budget 1 ──0..* BudgetCategoryTarget`.
- **Lifecycle:** created when the user first sets a budget; edited freely; no deletion (empty = no targets).
- **Ownership:** organizers.
- **Notes/decisions:**
  - Prototype `project.budget` → `Budget.total_target`. Prototype `budgetBreakdown[]` → `BudgetCategoryTarget` rows.
  - Prototype `committed` / `paid` / `outstanding` / `remaining` are **NOT stored here** — they are derived and, in the prototype, don't even reconcile with the activities. Resolves [AD-7].

---

### 5.12 Embedded value objects (no independent identity)

| Value object | Embedded in | Fields | Why not an entity (yet) |
|--------------|-------------|--------|-------------------------|
| **Location** | `Commitment.location` | `label text`, `address text?`, `latitude numeric?`, `longitude numeric?`, `external_place_id text?` | No evidence of place reuse across commitments in the prototype. Promote to a shared `Place` entity when a map view or places directory needs dedup ([§8.7](#87-locations)). |
| **Booking** | `Commitment.booking` | `supplier_name text?`, `supplier_contact text?`, `reference text?`, `confirmed bool` | No evidence of supplier reuse. Promote to a `Supplier` entity when a supplier directory is a feature ([AD-13]). |
| **NotificationPrefs** | `User.notification_prefs` | per-channel booleans | Only meaningful attached to a user. |

---

## 6. Relationships catalogue

| # | From | To | Cardinality | Kind | Carries data? | Notes |
|---|------|----|-------------|------|---------------|-------|
| R1 | User | ProjectMember | 1 → 0..* | FK (`ProjectMember.user_id`, nullable) | — | one membership per project per user |
| R2 | Project | ProjectMember | 1 → 1..* | FK | — | ≥1 organizer always |
| R3 | Project | Invitation | 1 → 0..* | FK | — | |
| R4 | Project | Commitment | 1 → 0..* | FK | — | |
| R5 | Project | Task | 1 → 0..* | FK | — | |
| R6 | Project | Milestone | 1 → 0..* | FK | — | |
| R7 | Project | Budget | 1 → 0..1 | FK | — | |
| R8 | Budget | BudgetCategoryTarget | 1 → 0..* | FK | yes (`amount`) | |
| R9 | Commitment | ProjectMember (owner) | 0..1 ← * | FK (`owner_member_id`, nullable) | — | **the** ownership link; resolves AD-4 |
| R10 | Commitment | ProjectMember (participants) | * ↔ * | join: `CommitmentParticipant` | yes (`rsvp`) | |
| R11 | Commitment | ProjectMember (cost split) | * ↔ * | join: `CostShare` | yes (`basis`,`weight`,`fixed_amount`) | absent = equal split |
| R12 | Commitment | Payment | 1 → 0..* | FK | yes | |
| R13 | Payment | ProjectMember (payer) | 0..1 ← * | FK (`paid_by_member_id`, nullable) | — | |
| R14 | Commitment | Task | 1 → 0..* | FK (`Task.commitment_id`, nullable) | — | task may also be project-only |
| R15 | Task | ProjectMember (assignee) | 0..1 ← * | FK (nullable) | — | |
| R16 | Milestone | Commitment | 0..1 → * | FK (nullable) | — | optional link |
| R17 | Invitation | ProjectMember | 1 → 0..1 | created on acceptance | — | also sets `ProjectMember.user_id` |

**Deleted prototype "relationships" that do not carry forward:**
- `person.responsibilities[]` (name strings) — replaced by the reverse of R9.
- `activity.owner` (name string) — replaced by R9.
- `activity.participants` (integer) — replaced by `count(R10)`.
- `needsAttention[].link` — dead data; navigation is derived from the finding's subject.

---

## 7. Derived systems

The architectural principle: **Budget, Timeline, and Health are evaluated as derived views/systems, not automatically as tables.** Conclusion for each below.

### 7.1 Budget

- **Verdict: derived, except targets.**
- **Persisted input:** `Budget` + `BudgetCategoryTarget` (targets only, [§5.11](#511-budget)).
- **Derived outputs** (computed from `Commitment` + `Payment` + `CostShare`):

| Figure | Definition |
|--------|------------|
| **Committed** | Σ `confirmed_cost ?? estimated_cost` over non-cancelled commitments |
| **Paid** | Σ `Payment.amount` where `status=paid` and `direction=outgoing` − Σ refunds |
| **Outstanding** | Committed − Paid |
| **Remaining** | `Budget.total_target` − Committed |
| **Actual by category** | group the "Committed" sum by `Commitment.kind` |
| **Target vs actual by category** | join `BudgetCategoryTarget.amount` with actual-by-category |
| **Per-member balance** | see [§8.8](#88-budget-calculations) |

- **Why not a table:** these numbers must always agree with the underlying commitments and payments. In the prototype they are stored separately and already disagree (committed 4,680 vs Σ costs 4,020). Storing them re-creates that bug.
- **Caching:** a `project_financials` materialised view / cache is acceptable for performance and for historical snapshots, but is never the source of truth and is never user-editable.

### 7.2 Timeline

- **Verdict: fully derived. No timeline table.**
- **Persisted inputs:** `Commitment` (`starts_at`/`ends_at`), `Payment` (`due_on`, `paid_on`), `Task` (`due_on`), `Milestone` (`on_date`), `Project` (`starts_on`/`ends_on`).
- **Derived output:** an ordered list of `TimelineEntry` DTOs — `{ occurs_at, kind ∈ (commitment|payment|task|milestone|project_boundary), title, subject_ref, status }` — sorted, groupable by day. See [§8.9](#89-timeline-generation).
- **Why not a table:** the prototype maintains `timeline[]` **and** `upcoming[]` by hand, and they already drift from the activities (timeline references 12 & 15 May; the project "starts" 16 May). A single derivation removes the drift. The global **Calendar** screen is the same derivation run across all of a user's projects.
- **Caching:** optional read-model; not authoritative.

### 7.3 Health / Risk

- **Verdict: derived engine. No findings table** (one small optional state table).
- **Persisted inputs:** essentially the whole project graph, plus `updated_at` timestamps.
- **Optional persisted state:** `FindingState` — `{ id, project_id, finding_code, subject_ref, state ∈ (open|snoozed|dismissed), snoozed_until, actor_member_id, updated_at }` — so users can dismiss/snooze a finding without it reappearing every render. This is the *only* persistent part, and it is [future-adjacent](#10-future-functionality) (v1 can render findings statelessly).
- **Derived output:** `Finding` objects — `{ code, severity ∈ (blocker|warning|info|ok), title, detail, subject_ref, suggested_action }`. See [§8.10](#810-healthrisk-detection) for the rule set.
- **"Needs attention"** = `Finding`s with `severity ≥ warning` and an actionable `subject_ref`, minus dismissed/snoozed. `attentionCount` = its length.
- **Why not a table:** the prototype hand-maintains three overlapping lists (`health[]`, `needsAttention[]`, `attentionCount`) that already say different things. One rules engine over live data replaces all three. Resolves [AD-9].

### 7.4 Other derived values (not systems, just computed fields)

| Value | Derivation | Replaces |
|-------|-----------|----------|
| Project **progress %** | see [§8.9-note]; recommended: `count(status ∈ {confirmed,booked,completed}) / count(status ≠ cancelled)` | prototype `progress` (arbitrary — Barcelona shows 72% where the data implies 80%) |
| Commitment **payment_status** | from its `Payment` rows | prototype "Fully Paid" status value |
| Commitment **outstanding** | `(confirmed_cost ?? estimated_cost) − Σ paid payments` | prototype slide-over `cost - paid` |
| Commitment **has_open_issues** | any `Finding` with `subject_ref` = this commitment | prototype `missingBooking`/`missingOwner` flags |
| **Travel gap** (prev/next) | time between consecutive scheduled commitments; distance/duration via a routing provider | prototype `prevGap`/`nextGap` strings |
| Member **"Owes £X"** | [§8.8](#88-budget-calculations) | prototype `people[].paid` text |
| **"Unassigned"**, **"missing"** labels | null checks | prototype sentinels |

---

## 8. Focus topics (deep dives)

### 8.1 Project membership

- **Entity:** `ProjectMember` ([§5.3](#53-projectmember)) — one row per person per project.
- **Key property:** `user_id` is **nullable**. A `ProjectMember` can exist for "Tom" who has never opened the app. This is essential: the prototype assigns owners and tracks "Owes £70" for people who are just names.
- **A `User` ↔ `ProjectMember` becomes linked** when: (a) an `Invitation` to their email is accepted, or (b) an organizer links an existing name-only member to an invited user. One `User` has many `ProjectMember` rows (one per project); each `ProjectMember` has at most one `User`.
- **Roles:** `organizer` (manage members, budget, project settings, delete), `member` (create/edit commitments, tasks, payments; be an owner/participant), `viewer` (read-only — the "Share a read-only link" case). Finer permissions (per-commitment, per-tab) are [future](#10-future-functionality); this 3-tier base is enough to build against. Partially resolves [AD-6].
- **Removal:** soft (`status=removed`). Their historical ownership, payments, and participation remain and render as "former member". Organizers must reassign or acknowledge orphaned commitments (a health finding surfaces them).
- **Global cross-project contacts** (the prototype's placeholder "People" screen) are **not** modelled now. That is a `Contact` / address-book concept — [future](#10-future-functionality), [AD-15].

### 8.2 Commitment ownership

- **One link only:** `Commitment.owner_member_id → ProjectMember` (nullable).
- **"Responsibilities" is a query, not data:** a member's responsibilities = `SELECT * FROM commitment WHERE owner_member_id = :member`. The prototype's separate `responsibilities[]` array (which already contradicts the `owner` field for Sarah/Airport Transfer) is **deleted**. Resolves [AD-4].
- **Unassigned is a first-class state:** `owner_member_id IS NULL`. This drives the "Missing owner" finding and the amber "Unassigned" label. No `missingOwner` boolean.
- **Owner vs creator:** `created_by` is recorded separately for audit; it has no ongoing meaning.
- **One owner, not many.** Co-ownership / helpers can be modelled later as a `CommitmentCollaborator` join; not now.
- **Owner must be an active member of the same project** (referential + status rule).

### 8.3 Commitment participants

- **Entity:** `CommitmentParticipant` ([§5.6](#56-commitmentparticipant)) — an explicit set, replacing the prototype's magic `participants: 12`.
- **`rsvp` attribute** is stored from the start (`going|maybe|not_going|unknown`) even though RSVP-collection UI is [future](#10-future-functionality) — because the participant set and their RSVP drive the **default cost split**.
- **Default membership on commitment creation:** recommended *all active project members*, matching the prototype's implicit "the whole group" assumption. Configurable — [D-2](#11-residual-product-decisions).
- **Derived:** participant count, per-commitment attendee list, "who on the boat party still owes money".

### 8.4 Payment modelling

- **Entity:** `Payment` ([§5.8](#58-payment)) — one row per planned or actual money movement, always attached to a `Commitment`.
- **The prototype's three scalars collapse in:**
  - `activity.cost` → `Commitment.estimated_cost` / `confirmed_cost`
  - `activity.deposit` → a `Payment{type:deposit}`
  - `activity.paid` → the sum of `Payment{status:paid}`
  - `activity.dueDate` → `Payment.due_on` (a real date) — the status phrases it also held ("Paid in full", "Pay on arrival") become derived state or a `schedule_note`
- **Typical shape:** a confirmed commitment has one `deposit` payment (often already `paid`) and one `balance` payment (`scheduled`, with a `due_on`). Installment plans = multiple `installment` rows.
- **Derived, never stored:** `due` / `overdue` (from `due_on` vs today), `payment_status`, `outstanding`, project `paid` / `outstanding`.
- **Cost responsibility vs payment:** kept in separate entities — `CostShare` says Tom is responsible for 1/12 of the boat; `Payment` says Mike actually paid the £400 deposit. Member balance reconciles the two ([§8.8](#88-budget-calculations)).
- **Explicitly out of scope:** taking payments *through* the platform, payment reminders/automation, splitwise-style settlement graphs. [Future](#10-future-functionality). Resolves [AD-8] for the *modelling* question.

### 8.5 Tasks

- **Entity:** `Task` ([§5.9](#59-task)) — separate from `Commitment` by design.
- **Belongs to a `Project`; optionally to a `Commitment`.** "Chase restaurant for confirmation number" → `Task{commitment_id: restaurant}`. "Make a group chat" → `Task{commitment_id: null}`.
- **Distinct lifecycle:** binary-ish completion (`open→in_progress→done`), which a commitment does not have.
- **Feeds:** Timeline (if `due_on` set), Health (overdue tasks, unassigned tasks near their due date).
- **Deferred:** subtasks, checklists, dependencies, recurrence, comments.

### 8.6 Locations

- **Now:** `Location` is an **embedded value object** on `Commitment` — `label`, optional `address`, optional `lat`/`lng`, optional `external_place_id`.
- **Why not an entity now:** the prototype shows no place being reused across commitments; each activity has its own one-off location string. A `Place` table would be normalisation with no current payoff.
- **Promote to a `Place` entity when:** a map view, a "reuse a saved place", or cross-project venue analytics appears — i.e. when dedup matters. The embedded fields are a clean subset of a future `Place`, so promotion is additive.
- **Travel gaps** (`prevGap`/`nextGap` in the prototype): **derived**, computed as the time between consecutive scheduled commitments on the same day, optionally enriched with real travel duration from a routing provider (a [future](#10-future-functionality) integration). Never stored on the commitment.
- Resolves [AD-13] (supplier — same reasoning, embed now) and the modelling half of the location question.

### 8.7 Milestones

- **Verdict:** a **thin optional entity** for user-pinned dates with no other home, plus **derived milestone-like markers** on the timeline.
- **Derived markers (no rows):** project start, project end / "checkout", payment due dates, "T‑minus 30 days" style countdowns — all computed from existing data.
- **`Milestone` rows** only for things like "RSVP deadline" or "final numbers to caterer" that aren't a commitment, payment, or task.
- **Residual:** possible merge with `Task` ([D-4](#11-residual-product-decisions)).

### 8.8 Budget calculations

All figures below are **derived** ([§7.1](#71-budget)); only `Budget` targets are stored.

- **Project roll-up:** Committed, Paid, Outstanding, Remaining — definitions in [§7.1](#71-budget).
- **By category:** group commitment costs by `Commitment.kind`; compare with `BudgetCategoryTarget`.
- **Per-member balance** (reproduces "Owes £70"):
  1. For each non-cancelled commitment, determine each member's **share of cost** from `CostShare` (or equal split across participants if no `CostShare` rows).
  2. Sum each member's shares across all commitments → **owed**.
  3. Sum `Payment.amount` where `status=paid` and `paid_by_member_id = member` → **contributed**.
  4. **Balance = contributed − owed.** Negative → "Owes £X"; positive → "Is owed £X".
- **Settlement suggestions** ("Tom → Mike £40") are [future](#10-future-functionality).
- Resolves [AD-7].

### 8.9 Timeline generation

- **Algorithm (derived, [§7.2](#72-timeline)):**
  1. Collect events: each scheduled `Commitment` (`starts_at`), each `Payment` with a `due_on` (and, optionally, `paid_on`), each `Task` with a `due_on`, each `Milestone` (`on_date`), and `Project.starts_on` / `ends_on`.
  2. Normalise to the **project timezone** (`Project.timezone`) — important because commitments abroad and the organiser's home differ; the prototype ignores this entirely.
  3. Sort ascending; tag each with a `kind` and a `subject_ref`.
  4. Group by calendar day for display. "Upcoming" = the same list filtered to `now .. now + window`.
- **Global Calendar** = run the same algorithm across every project the current `User` is a member of, keyed by project.
- **Progress % note (residual [D-5](#11-residual-product-decisions)):** recommended definition `count(commitments with status ∈ {confirmed,booked,completed}) / count(commitments with status ≠ cancelled)`. Alternatives considered: paid ÷ budget; completed-tasks ÷ tasks; weighted blend. The prototype's number is not derived from anything (Barcelona shows 72%; the five activities imply 80% by the above formula), which confirms it must be defined here, not inherited.

### 8.10 Health / risk detection

- **Engine (derived, [§7.3](#73-health--risk)):** a set of rules evaluated against a project, each yielding zero or more `Finding`s. Rules extracted directly from the prototype's `health[]` and `needsAttention[]`:

| Code | Trigger | Severity | Subject | Suggested action | Depends on |
|------|---------|----------|---------|------------------|-----------|
| `missing_owner` | `Commitment.owner_member_id IS NULL` and status ≥ `researching` | warning | commitment | "Assign an owner" | Commitment |
| `missing_booking_ref` | status ≥ `confirmed` and (`booking.reference IS NULL` or `booking.confirmed = false`) | warning | commitment | "Add the confirmation number" | Commitment |
| `payment_overdue` | `Payment.status=scheduled` and `due_on < today` | blocker | payment | "Record or reschedule this payment" | Payment |
| `payment_due_soon` | `Payment.status=scheduled` and `due_on` within N days | warning | payment | "Payment due in N days" | Payment |
| `commitment_inactive` | status ≤ `researching` and `updated_at` older than N days | warning | commitment | "No update in N days — still happening?" | Commitment.updated_at |
| `unconfirmed_close_to_date` | status ≤ `researching` and `starts_at` within N days | warning | commitment | "Confirm or drop this" | Commitment |
| `schedule_gap` / `tight_connection` | gap between consecutive same-day commitments outside a comfortable band | info | commitment pair | "Only 18 min between X and Y" | Commitment schedule + Location |
| `over_budget` | derived Committed > `Budget.total_target` | warning | project | "£X over budget" | Budget + derived |
| `under_budget` | derived Remaining > 0 near project end | ok | project | "On track, £X under" | Budget + derived |
| `orphaned_commitment` | `owner_member_id` points to a `removed` member | warning | commitment | "Owner left the project" | Commitment + ProjectMember |
| `task_overdue` | `Task.status ≠ done` and `due_on < today` | warning | task | "Overdue task" | Task |

- **Thresholds** (`N days`, gap bands, "close to date") are **configuration**, not magic numbers in code — the prototype hardcodes "9 days", "18 min", "£500". [Residual D-6](#11-residual-product-decisions) sets the defaults.
- **`FindingState`** (optional, [§7.3](#73-health--risk)) lets a user dismiss/snooze a finding.
- **Output routing:** all findings → **Health** tab. Subset (`severity ≥ warning`, actionable subject, not dismissed) → **Needs attention** on Dashboard + project Overview. Count → `attentionCount`.
- Resolves [AD-9].

---

## 9. Persisted vs derived — summary table

| Concept | Persisted entity? | Derived? | Notes |
|---------|-------------------|----------|-------|
| User | ✅ `User` | | |
| Project | ✅ `Project` | | no stored progress/totals |
| Project membership | ✅ `ProjectMember` | | `user_id` nullable |
| Invitation | ✅ `Invitation` | | |
| Commitment | ✅ `Commitment` | | core entity |
| Commitment owner | — (FK on Commitment) | | single link |
| Commitment participants | ✅ `CommitmentParticipant` | count is derived | |
| Cost split | ✅ `CostShare` (only if non-default) | shares derived if absent | |
| Payment | ✅ `Payment` | `due`/`overdue`/`payment_status` derived | |
| Task | ✅ `Task` | | separate from Commitment |
| Milestone | ✅ `Milestone` (thin) | most timeline markers derived instead | |
| Location | ❌ (embedded value object) | travel gaps derived | promote to `Place` later |
| Supplier / booking | ❌ (embedded value object) | | promote to `Supplier` later |
| Budget targets | ✅ `Budget` + `BudgetCategoryTarget` | | |
| Budget actuals (committed/paid/outstanding/remaining) | ❌ | ✅ | from Commitment + Payment |
| Per-member balance ("owes £X") | ❌ | ✅ | from CostShare + Payment |
| Timeline / Upcoming | ❌ | ✅ | from schedules + due dates |
| Calendar (global) | ❌ | ✅ | timeline across all projects |
| Health / risk findings | ❌ (optional `FindingState` only) | ✅ | rules engine |
| "Needs attention" list + count | ❌ | ✅ | subset of findings |
| Progress % | ❌ | ✅ | defined in §8.9 |
| Commitment status flags (payment_status, has_open_issues) | ❌ | ✅ | `status` itself is stored & user-set |

---

## 10. Future functionality

Named so the model leaves room for them. **Not in the first schema.**

| Area | Prototype hint | Shape when built |
|------|----------------|-----------------|
| Comments / activity feed | none, but expected for collaboration | polymorphic `Comment` on Commitment / Task / Payment; `ActivityEvent` log |
| Attachments / documents | none | `Attachment` on Commitment / Task / Project |
| Notifications | Settings: "Email + push" | `Notification` + delivery log; driven by Health findings and Timeline |
| Global contacts / address book | placeholder "People" screen | `Contact` (user-scoped), linkable to many `ProjectMember`s ([AD-15]) |
| Read-only calendar sharing / iCal feed | placeholder "Calendar" screen | derived feed, per-project token |
| Payment collection & settlement | "Owes £70" | settlement graph, payment requests, provider integration ([AD-8] execution half) |
| RSVP collection | — | UI over the existing `CommitmentParticipant.rsvp` column |
| Fine-grained permissions | "Share" / "Project settings" buttons | per-resource ACL beyond the 3 base roles ([AD-6]) |
| Project templates | — | `ProjectTemplate` → clone into a `Project` with commitments/tasks |
| Supplier directory | inline supplier fields | promote `Booking` value object → `Supplier` entity ([AD-13]) |
| Saved places / map | inline location fields | promote `Location` → `Place` entity |
| Real-time presence / co-editing | full re-render prototype | out of model scope; infra concern |
| Multi-currency | hardcoded GBP | per-commitment currency + FX snapshot ([AD-16]) |
| Recurring commitments / tasks | — | recurrence rule value object |
| Travel-time enrichment | `prevGap`/`nextGap` strings | routing-provider integration feeding the derived gap |
| Date-availability polling | — | `Poll` entity pre-project |

---

## 11. Residual product decisions

Decisions the schema does **not** force, but which should be made before or during schema work. Each has a recommended default so implementation is not blocked.

| ID | Decision | Recommended default | Related |
|----|----------|---------------------|---------|
| **D-1** | User-facing label for `Commitment` | Display as **"Activity"** initially (glossary mapping only; model name stays `Commitment`) | §3.5, AD-1/AD-2 |
| **D-2** | Default participants when a commitment is created | All active project members | §8.3 |
| **D-3** | Cost-sharing granularity | Per-commitment `CostShare`, default equal split; "no rows" = simple equal split everywhere | §5.7, AD-8 |
| **D-4** | Keep `Milestone` separate from `Task`, or merge as `Task.is_milestone` | Keep separate for v1; revisit | §5.10, §8.7 |
| **D-5** | Definition of project **progress %** | `confirmed+booked+completed` ÷ `non-cancelled` commitments | §8.9, AD-3 |
| **D-6** | Health thresholds | inactive = 7 days; payment_due_soon = 7 days; tight_connection < 20 min; unconfirmed_close_to_date = 14 days | §8.10, AD-9 |
| **D-7** | `Commitment.kind` / budget category list | `accommodation, transport, food, experience, services, other` | §5.5, AD-11 |
| **D-8** | Commitment status set | `idea, researching, confirmed, booked, completed, cancelled` | §5.5, AD-2 |
| **D-9** | Product name | **Resolved: "Orchestrio".** Does not affect schema | AD-1 |
| **D-10** | Whether `viewer` role ships in v1 or later | Ship it (needed for the "Share" button) | §8.1, AD-6 |

**Decisions considered resolved by this document:** AD-2 (Commitment is the umbrella; §3), AD-4 (single ownership FK; §8.2), AD-5 (User vs ProjectMember; §5.1/§5.3), AD-7 (budget actuals derived; §7.1), AD-8 modelling half (Payment + CostShare entities; §8.4), AD-9 (health is a derived engine; §7.3), AD-10 (structured tz-aware time; §2), AD-11 (kind == budget category; §5.5), AD-13 (embed supplier/location, promote later; §8.6), AD-14 (participants are a set; §5.6), AD-17 (project status enum; §5.2).

---

## 12. Prototype → domain model mapping (traceability)

| Prototype (`DATA` / UI) | Domain model target |
|-------------------------|---------------------|
| `DATA.user` / "James" / "JD" / "James Dawson" | `User` (one) + `ProjectMember.display_name` per project |
| `projects.<id>` | `Project` |
| `project.name` | `Project.name` |
| `project.dates` (free text) | `Project.starts_on` + `Project.ends_on` (+ `timezone`) |
| `project.progress` | derived (§8.9) |
| `project.budget` | `Budget.total_target` |
| `project.committed` / `paid` / `outstanding` / `remaining` | derived (§7.1) |
| `project.attentionCount` | derived (§8.10) |
| `project.cover` | `Project.cover_theme` (optional, cosmetic) |
| `project.activities[]` | `Commitment[]` |
| `activity.name` | `Commitment.title` |
| `activity.date` / `time` | `Commitment.starts_at` / `ends_at` / `is_all_day` / `schedule_note` |
| `activity.owner` (name/null) | `Commitment.owner_member_id → ProjectMember` (nullable) |
| `activity.cost` | `Commitment.estimated_cost` / `confirmed_cost` |
| `activity.deposit` / `paid` | `Payment` rows |
| `activity.dueDate` (overloaded) | `Payment.due_on` (+ `schedule_note` for phrases) |
| `activity.status` | `Commitment.status` (enum, D-8) — "Fully Paid" → derived `payment_status` |
| `activity.location` | `Commitment.location` [value object] |
| `activity.bookingRef` / `supplier` / `contact` | `Commitment.booking` [value object] |
| `activity.missingBooking` / `missingOwner` | derived findings (§8.10) |
| `activity.participants` (int) | `count(CommitmentParticipant)` |
| `activity.category` | `Commitment.kind` (D-7) |
| `activity.notes` | `Commitment.notes` |
| `activity.prevGap` / `nextGap` | derived travel gap (§8.6) |
| `project.people[]` | `ProjectMember[]` |
| `person.name` | `ProjectMember.display_name` |
| `person.role` | `ProjectMember.role` (+ `viewer`) |
| `person.responsibilities[]` | reverse query of `Commitment.owner_member_id` (§8.2) |
| `person.paid` (text) | derived per-member balance (§8.8) |
| `project.budgetBreakdown[]` | `BudgetCategoryTarget[]` |
| `project.timeline[]` | derived `TimelineEntry[]` (§8.9) |
| `project.upcoming[]` | derived (timeline filtered to a window) |
| `timeline item type` (payment/activity/milestone) | `TimelineEntry.kind` |
| `project.health[]` | derived `Finding[]` (§8.10) |
| `project.needsAttention[]` | derived subset of `Finding[]` |
| `needsAttention[].link` | dropped — navigation from `Finding.subject_ref` |
| Wizard "Type": Activity/Booking/Task | Activity/Booking → `Commitment` (`kind`); Task → `Task` |
| Wizard "Type": Payment | `Payment` (attached to a chosen `Commitment`) — not a peer entity |
| Wizard fields (name/date/location/cost/deposit/due/owner) | `Commitment` + first `Payment` + `owner_member_id` |
| Settings screen rows | `User` attributes (`display_name`, `email`, `default_currency`, `notification_prefs`) |
| "Share" button | `Invitation` + `viewer` role |
| "New project" button | `Project` + creating `ProjectMember` (organizer) |
| "Project settings" button | `Project` mutable attributes |
| Calendar screen (placeholder) | derived global timeline (§8.9) |
| People screen (placeholder) | future `Contact` (§10) |

---

## 13. Glossary

| Term | Meaning |
|------|---------|
| **Commitment** | The core entity: one planned line item a project has taken on. Displayed in the UI as "Activity" (D-1). |
| **Kind** | Classification of a commitment (`accommodation`, `transport`, `food`, `experience`, `services`, `other`); doubles as the budget category. |
| **ProjectMember** | A person's identity within one project. May or may not be linked to a `User`. |
| **Owner** | The single `ProjectMember` accountable for a commitment (`owner_member_id`). |
| **Participant** | A `ProjectMember` involved in a specific commitment (`CommitmentParticipant`). |
| **CostShare** | How a commitment's cost is divided among members. Absent ⇒ equal split. |
| **Payment** | One planned or actual movement of money for a commitment. |
| **Balance** | Derived per-member figure: what they've paid minus what they owe. |
| **Task** | A small unit of work; lighter than a commitment; may be a child of one. |
| **Milestone** | A user-pinned significant date not implied by any commitment/payment/task. |
| **Finding** | A single output of the health engine (derived). |
| **Needs attention** | The actionable subset of findings shown on the dashboard. |
| **Timeline** | The derived, ordered merge of every dated thing in a project. |
| **Budget actuals** | Derived committed/paid/outstanding/remaining figures. Only *targets* are stored. |
| **Derived** | Computed from persistent entities; never edited directly; may be cached. |
