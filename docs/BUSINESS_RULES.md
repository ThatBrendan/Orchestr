# Business Rules — MVP

**Status:** Draft for review

**Date:** 2026-09-04

**Source material:** [`docs/DOMAIN_MODEL.md`](./DOMAIN_MODEL.md), [`docs/PROTOTYPE_ANALYSIS.md`](./PROTOTYPE_ANALYSIS.md)

**Scope:** the complete rule set for the first shippable version. Defines behaviour, constraints, calculations, and the initial health engine.

**Non-goals:** no schema, no code, no API contracts, no UI copy beyond message templates.

---

## 0. Conventions

**Priority tags** (applied to every rule):

| Tag | Meaning |

|-----|---------|

| **[MUST]** | Required for MVP. The product does not ship without it. |

| **[SHOULD]** | Wanted in MVP; may slip to a fast-follow without blocking launch. |

| **[FUTURE]** | Explicitly out of scope. Listed so the MVP does not design against it. |

**Global conventions:**

- **GC-1 [MUST]** Every entity has `created_at` and `updated_at`. Mutations update `updated_at`.

- **GC-2 [MUST]** Deletion is **soft** for Project, ProjectMember, Commitment, Payment, Task (sets `deleted_at`). Milestone and Invitation may hard-delete.

- **GC-3 [MUST]** Money is stored as an integer number of minor units plus an ISO‑4217 currency code. All money in a project is in that project's single currency.

- **GC-4 [MUST]** Date‑only fields (`due_on`, `on_date`, `starts_on`, `ends_on`) are compared against "today" **in the project's timezone**.

- **GC-5 [MUST]** Timed fields (`starts_at`, `ends_at`) are absolute instants; they are displayed in the project's timezone.

- **GC-6 [MUST]** Concurrency is last‑write‑wins at field granularity. **[SHOULD]** carry an optimistic‑concurrency version token to reject stale writes. Real‑time co‑editing is **[FUTURE]**.

- **GC-7 [MUST]** Budget, per‑member balances, timeline, health findings, project progress, and commitment payment status are **derived** — computed on read, never stored as editable fields (a read‑through cache is allowed). This document defines each formula exactly once. There are **no redundant sources of truth**.

- **GC-8 [MUST]** All derived operational figures ignore soft‑deleted rows and `cancelled` commitments unless a rule says otherwise. **Financial-history metrics are the exception:** actual paid, refunded, and net actual spend preserve real money movements on cancelled commitments as defined in §8.

---

## 1. Projects

### 1.1 Creation

- **PRJ-1 [MUST]** Any authenticated `User` can create a `Project`. No limit on projects per user in MVP.

- **PRJ-2 [MUST]** On creation the system creates one `ProjectMember` for the creator with `role = organizer`, `status = active`, `user_id` set.

- **PRJ-3 [MUST]** Required at creation: `name`. Optional: `description`, `starts_on`, `ends_on`, `timezone`, `currency`.

- **PRJ-4 [MUST]** `timezone` defaults to the creator's `User.timezone`. `currency` defaults to the creator's `User.default_currency`.

- **PRJ-5 [MUST]** A new project starts with `status = draft`.

### 1.2 Ownership

- **PRJ-6 [MUST]** There is **no single "project owner" field**. A project is owned collectively by its members with `role = organizer`.

- **PRJ-7 [MUST]** A project must always have **at least one `active` organizer**. Any rule that would remove the last organizer is rejected (see PRJ‑23, MEM‑16, MEM‑20).

- **PRJ-8 [MUST]** Transfer of control = promoting another member to `organizer` (MEM‑12). Demoting yourself is allowed only if another active organizer remains.

### 1.3 Status

- **PRJ-9 [MUST]** `status ∈ {draft, active, completed, archived}`.

- **PRJ-10 [MUST]** `draft → active` happens automatically when **any** of: the first `Commitment` is created; a second member becomes `active`; or an organizer sets it manually.

- **PRJ-11 [SHOULD]** `active → completed` is manual. The system **[SHOULD]** suggest it once `ends_on` is in the past, but never sets it automatically.

- **PRJ-12 [MUST]** `completed` is not read‑only. It is a label indicating the event has happened. `completed → active` is allowed (reopen).

- **PRJ-13 [MUST]** `archived` is reached from any status via PRJ‑16 and is read‑only (PRJ‑17).

- **PRJ-14 [MUST]** `draft` behaves exactly like `active` for all other rules (budget, health, timeline all apply). It only changes labelling and can be hidden from some list views.

### 1.4 Dates

- **PRJ-15 [MUST]** `starts_on` and `ends_on` are independently optional. If both are set, `starts_on ≤ ends_on` (VAL‑1).

- Project dates are **advisory**: commitments and tasks may fall outside them (HLT‑15 raises an `info` finding, never a block).

### 1.5 Currency

- **PRJ-16a [MUST]** `currency` is immutable once the project has **any** `Commitment` or `Payment` (including soft‑deleted). While the project has none, an organizer **[SHOULD]** be able to change it.

- **PRJ-16b [MUST]** Multi‑currency projects, per‑commitment currency, and FX are **[FUTURE]**.

### 1.6 Archiving

- **PRJ-16 [MUST]** An organizer can archive a project. Sets `archived_at`, `status = archived`.

- **PRJ-17 [MUST]** An archived project is fully read‑only: no create/edit/delete of any child entity, no member or invitation changes. Only **un‑archive** and **delete** are permitted.

- **PRJ-18 [MUST]** Un‑archiving restores the previous `status` (`active` or `completed`).

- **PRJ-19 [SHOULD]** Archived projects are excluded from the dashboard and from global timeline/health computation, and appear in a separate "Archived" list.

### 1.7 Deletion

- **PRJ-20 [MUST]** Only an organizer can delete a project. Deletion is soft (`deleted_at`).

- **PRJ-21 [MUST]** Deleting a project soft‑deletes **all** child entities (members, invitations, commitments, participants, cost shares, payments, tasks, milestones, budget).

- **PRJ-22 [MUST] Soft-deleted projects have a 30-day recovery window measured from deleted_at.

- **PRJ-23 [MUST]** A deleted project is invisible everywhere and excluded from all computation.


PRJ-24 [MUST]
A soft-deleted project is excluded from all ordinary SELECT policies and
derived computation.

PRJ-25 [MUST]
Restoration is only available through a dedicated restore_project RPC.

PRJ-26 [MUST]
restore_project may be executed only by an authenticated user who was an
active organizer of the project immediately before deletion.

PRJ-27 [MUST]
restore_project rejects restoration when:
- deleted_at is null;
- deleted_at is older than 30 days;
- the caller was not an organizer at deletion;
- restoration would violate current integrity constraints.

PRJ-28 [MUST]
A successful restoration clears deleted_at on the Project and on child rows
soft-deleted as part of that project deletion operation.

PRJ-29 [FUTURE]
Permanent purge after the recovery window and administrative restoration
outside the recovery window.

---

## 2. Project Members

A `ProjectMember` is the project‑scoped identity. Owners, participants, payers, and assignees are always `ProjectMember` references — never `User` references, never free‑text names.

### 2.1 Joining

- **MEM-1 [MUST]** A person enters a project one of two ways:

1. **Named directly** by an organizer — creates a `ProjectMember` with `display_name`, optional `email`, `user_id = null`, `status = active`. This person cannot log in but can be an owner, participant, payer, or assignee.

2. **By accepting an `Invitation`** — links or creates a `ProjectMember` with `user_id` set, `status = active`.

- **MEM-2 [MUST]** Exactly one `ProjectMember` per `(project, user_id)`. A user accepting a second invitation to the same project is a no‑op returning the existing membership.

- **MEM-3 [MUST]** When an invitation is accepted and a name‑only `ProjectMember` already exists with a matching `email`, that row is claimed (its `user_id` is set) rather than creating a duplicate. **[SHOULD]** allow an organizer to manually link/merge a name‑only member with an invited user.

- **MEM-4 [MUST]** `display_name` is always required (1–80 chars, trimmed, non‑blank), even for `user_id`‑linked members. It defaults from `User.display_name` on link but is project‑local thereafter.

### 2.2 Invitations

- **MEM-5 [MUST]** An organizer can create an `Invitation` (`email`, `role ∈ {member, viewer}`). **[SHOULD]** allow `member`s to invite (organizer‑configurable); never `viewer`s.

- **MEM-6 [MUST]** `role = organizer` cannot be granted by invitation — promote after joining (MEM‑12).

- **MEM-7 [MUST]** At most one `pending` invitation per `(project, email)`. Re‑inviting the same email replaces/refreshes the pending invitation.

- **MEM-8 [MUST]** Inviting an email that is already an `active` member returns the existing membership and creates no invitation.

- **MEM-9 [SHOULD]** Invitations expire after 14 days (`status = expired`). An organizer can revoke a `pending` invitation (`status = revoked`).

- **MEM-10 [MUST]** Accepting requires the invitee to be authenticated (sign up or log in first). Acceptance is idempotent.

- **MEM-11 [FUTURE]** Invite links (no named email), bulk invites, join requests / approval queues, domain‑based auto‑join.

### 2.3 Roles

- **MEM-12 [MUST]** `role ∈ {organizer, member, viewer}`. Only an organizer can change roles. Promotion to / demotion from `organizer` is subject to PRJ‑7.

- **MEM-13 [MUST]** Default role for a directly‑named member is `member`. Default from an invitation is whatever the invitation specifies.

### 2.4 Permissions

- **MEM-14 [MUST]** Permission matrix for MVP:

| Action | organizer | member | viewer |

|--------|:---:|:---:|:---:|

| View everything in the project | ✅ | ✅ | ✅ |

| Create / edit / delete commitments, payments, tasks, milestones | ✅ | ✅ | ❌ |

| Be a commitment **owner** / task **assignee** | ✅ | ✅ | ❌ |

| Be a commitment **participant** / cost‑share target / payer | ✅ | ✅ | ✅¹ |

| Edit project settings (name, dates, timezone, budget, cover) | ✅ | ❌ | ❌ |

| Change currency (while permitted by PRJ‑16a) | ✅ | ❌ | ❌ |

| Invite members | ✅ | ✅² | ❌ |

| Change roles / remove members | ✅ | ❌ | ❌ |

| Archive / un‑archive / delete project | ✅ | ❌ | ❌ |

| Dismiss / snooze health findings | ✅ | ✅ | ❌ |

¹ A viewer can be listed as a participant (they are attending) and can carry a cost share and be recorded as a payer by someone else, but cannot act in the app.

² Organizer‑configurable; default on.

- **MEM-15 [MUST]** Any `member` may edit any commitment/task/payment regardless of who created or owns it. **[FUTURE]** per‑resource or per‑field restrictions ([AD‑6]).

- **MEM-15a [MUST]** Deleting a commitment/task/payment requires being an `organizer`, its `created_by`, or (for a commitment) its `owner`. **[SHOULD]** allow any member to delete.

### 2.5 Removing members

- **MEM-16 [MUST]** An organizer can remove any member except the last active organizer (PRJ‑7). Removal is soft: `status = removed`, `removed_at` set.

- **MEM-17 [MUST]** Removal **preserves all references**. Commitments they owned keep `owner_member_id`; the "orphaned owner" finding (HLT‑2) surfaces them. Payments they made stay attributed. Participation and cost‑share rows remain but are excluded from *default equal‑split recalculation* going forward (a removed member keeps any explicitly fixed share; an equal‑split share is dropped on the next recalculation — VAL‑24).

- **MEM-18 [SHOULD]** On removal the UI prompts the organizer to reassign that member's owned commitments and open tasks; reassignment is never forced.

- **MEM-19 [SHOULD]** Re‑adding a previously removed person (same `email` or same `user_id`) reactivates the existing row (`status = active`) rather than creating a new one.

### 2.6 Leaving projects

- **MEM-20 [MUST]** A `member` or `viewer` can leave at any time (self‑removal, `status = removed`). An `organizer` can leave only if another active organizer remains; otherwise they must first promote someone or delete the project.

- **MEM-21 [MUST]** Leaving follows the same reference‑preservation rules as removal (MEM‑17).

- **MEM-22 [SHOULD]** A user who has left can be re‑invited normally (MEM‑19 applies).

---

## 3. Commitments

Domain entity `Commitment`; displayed in the UI as **"Activity"** for MVP ([DOMAIN_MODEL D‑1]).

### 3.1 Creation

- **COM-1 [MUST]** Any `organizer`/`member` can create a commitment in a non‑archived project.

- **COM-2 [MUST]** Required: `title` (1–120 chars, trimmed, non‑blank), `kind`. Everything else is optional.

- **COM-3 [MUST]** New commitments start at `status = researching`. **[SHOULD]** allow the creator to pick `idea` instead at creation.

- **COM-4 [MUST]** On creation, participants default to **all currently `active` project members** ([DOMAIN_MODEL D‑2]). **[SHOULD]** let the creator start with an empty participant set.

- **COM-5 [MUST]** `created_by` is recorded. `owner_member_id` is **not** defaulted to the creator — a new commitment is unowned unless an owner is chosen (this is intentional; it makes "who's doing this?" an explicit decision and feeds HLT‑1).

### 3.2 Types (`kind`)

- **COM-6 [MUST]** `kind ∈ {accommodation, transport, food, experience, services, other}` ([DOMAIN_MODEL D‑7]). Exactly one per commitment. This value is also the **budget category** — there is no separate category field.

- **COM-7 [MUST]** Prototype mapping: "Activities" → `experience`; Hotel → `accommodation`; Airport Transfer → `transport`; Restaurant → `food`.

- **COM-8 [FUTURE]** Custom/user‑defined kinds, tags, multiple kinds per commitment.

- **COM-9 [MUST]** The "Add" wizard's four choices resolve as: *Activity* and *Booking* → a `Commitment` (with the appropriate `kind`); *Task* → a `Task`; *Payment* → a `Payment` attached to a chosen commitment. There is no "Booking" or "Payment" commitment type.

### 3.3 Status lifecycle

- **COM-10 [MUST]** `status ∈ {idea, researching, confirmed, booked, completed, cancelled}`.

- **COM-11 [MUST]** Allowed forward transitions: `idea → researching → confirmed → booked → completed`.

- **COM-12 [MUST]** `cancelled` is reachable from any non‑`completed` status. `completed → cancelled` is **not** allowed (it already happened).

- **COM-13 [SHOULD]** Backward transitions (`confirmed → researching`, `booked → confirmed`, `completed → booked`) are allowed.

- **COM-14 [MUST]** `cancelled → researching` ("reactivate") is the only way out of `cancelled`. Direct `cancelled → confirmed/booked` is rejected.

- **COM-15 [MUST]** Status is **always user‑set**. The system may surface a suggestion (e.g. "all payments settled — mark as booked?", or "this happened yesterday — mark completed?") but never changes status automatically. **[FUTURE]** opt‑in auto‑advance.

- **COM-16 [MUST]** No status transition is *blocked* by missing data in MVP. Missing owner, cost, or booking reference produce **health findings**, not hard gates. **[SHOULD]** show a soft confirmation dialog when advancing to `confirmed`/`booked` with gaps.

- **COM-17 [MUST]** `cancelled` commitments are excluded from budget math, timeline events, project progress, and health findings (they cannot themselves be the subject of a finding). They remain visible in the commitment list with a "Cancelled" treatment.

- **COM-18 [SHOULD]** When a commitment is cancelled, its `scheduled` outgoing payments are automatically set to `cancelled`; its open tasks are left as‑is but surface via HLT‑13 if overdue. **[MUST]** Historical `paid` payments and `paid` refunds are preserved and remain part of actual financial-history metrics (§8); cancellation must never erase money that actually moved.

**Derived, not stored** (GC‑7):

- **COM-19 [MUST]** `payment_status ∈ {unpaid, deposit_paid, part_paid, paid_in_full}` — computed from the commitment's payments (§5.4).

- **COM-20 [MUST]** `has_open_issues` — true if any non‑dismissed health finding has this commitment as its subject.

- **COM-21 [MUST]** `effective_cost` = `confirmed_cost` if not null, else `estimated_cost`, else `0`.

### 3.4 Ownership

- **COM-22 [MUST]** A commitment has **exactly one** owner reference, `owner_member_id`, which is nullable. Null renders as "Unassigned".

- **COM-23 [MUST]** The owner must be an `active` `ProjectMember` with `role ∈ {organizer, member}`. Assigning a `viewer` or a `removed` member is rejected at write time (a member removed *after* assignment triggers HLT‑2 instead).

- **COM-24 [MUST]** Owner can be set, changed, or cleared at any time by any `organizer`/`member`.

- **COM-25 [MUST]** "A person's responsibilities" is the query `commitments where owner_member_id = that member` — it is **not** stored on the member. The prototype's `responsibilities[]` array does not exist.

- **COM-26 [FUTURE]** Co‑owners / helpers (a `CommitmentCollaborator` join).

### 3.5 Participants

- **COM-27 [MUST]** Participants are an explicit set of `ProjectMember` references via `CommitmentParticipant`. There is no participant *count* field — the count is `count(participants)`. The prototype's `participants: 12` does not exist.

- **COM-28 [MUST]** Any `active` member (including `viewer`) can be added/removed as a participant by any `organizer`/`member`. Unique per `(commitment, member)`.

- **COM-29 [MUST]** `rsvp ∈ {going, maybe, not_going, unknown}`, default `unknown`. The field is stored from MVP; **participant‑facing RSVP UI is [FUTURE]**.

- **COM-30 [MUST]** Adding/removing a participant recalculates any **equal‑split** cost shares for that commitment (§5, VAL‑24). Explicitly fixed/weighted shares are untouched.

- **COM-31 [MUST]** A commitment may have zero participants. If it also has `effective_cost > 0` and no cost shares, its cost is "unallocated" (HLT‑16).

### 3.6 Dates

- **COM-32 [MUST]** `starts_at`, `ends_at`, `is_all_day` are optional. A commitment with no `starts_at` is "unscheduled" and does not appear on the timeline.

- **COM-33 [MUST]** If both are set, `ends_at ≥ starts_at` (VAL‑10). Cross‑midnight is allowed.

- **COM-34 [MUST]** `schedule_note` is free text for nuances the fields can't hold ("check‑in from 15:00", "flexible"). It never participates in computation.

- **COM-35 [SHOULD]** If `starts_at`'s date falls outside the project's `[starts_on, ends_on]`, raise HLT‑15 (`info`).

### 3.7 Locations

- **COM-36 [MUST]** Location is an **embedded value object** on the commitment: `label` (free text), optional `address`, optional `latitude`/`longitude`, optional `external_place_id`. All fields optional; `label` alone is a valid location.

- **COM-37 [MUST]** There is no `Location`/`Place` entity in MVP. No geocoding, no map, no reuse across commitments.

- **COM-38 [FUTURE]** Promote to a shared `Place` entity; geocoding; map view; saved places.

### 3.8 Suppliers & booking information

- **COM-39 [MUST]** Supplier + booking data is an **embedded value object** on the commitment: `supplier_name`, `supplier_contact`, `reference`, `confirmed` (bool, default `false`). All optional.

- **COM-40 [MUST]** There is no `Supplier` entity in MVP. No supplier directory, no reuse.

- **COM-41 [MUST]** "Booking incomplete" is derived: a commitment with `status ∈ {confirmed, booked, completed}` and (`reference` null **or** `confirmed = false`) raises HLT‑5. The prototype's `missingBooking` flag does not exist.

- **COM-42 [FUTURE]** Promote to a `Supplier` entity; attach documents/contracts; multiple suppliers per commitment.

### 3.9 Deletion

- **COM-43 [MUST]** Soft‑delete cascades to the commitment's participants, cost shares, payments, and child tasks. All are immediately excluded from budget, timeline, and health.

- **COM-44 [MUST]** Linked milestones are **not** deleted; their `commitment_id` is cleared (contrast COM‑43 for tasks) because a milestone is a project‑level date marker.

---

## 4. Payments

A `Payment` always belongs to a `Commitment`. It represents one planned or actual movement of money.

### 4.1 Payment creation

- **PAY-1 [MUST]** A new outgoing charge/payment can only be created against an existing, non‑cancelled, non‑deleted commitment. A refund may be recorded against a cancelled commitment when it represents money returned after cancellation; no payment may be created against a soft‑deleted commitment.

- **PAY-2 [MUST]** Required: `amount` (integer minor units, **> 0**), `type ∈ {deposit, balance, installment, full, refund}`, `direction ∈ {outgoing, incoming}` (default `outgoing`; `refund` defaults `direction = incoming`).

- **PAY-3 [MUST]** `currency` is the project currency (implicit; not separately editable).

- **PAY-4 [MUST]** `status` defaults to `scheduled`. A payment may also be created directly as `paid` (with `paid_on`).

- **PAY-5 [MUST]** `due_on` is optional and may be in the past (recording a payment that is already overdue is valid).

- **PAY-6 [SHOULD]** `paid_by_member_id` should be provided when `status = paid`; **[MUST]** allow null ("who paid is unknown").

- **PAY-7 [SHOULD]** Warn (never block) if creating a second `full` payment, or a `deposit` when a `full` already exists.

### 4.2 Partial payments

- **PAY-8 [MUST]** A commitment may have any number of payments. "Paid so far" for a commitment = **Σ `amount` of its `paid` `outgoing` payments − Σ `amount` of its `paid` `incoming` payments (refunds)**.

- **PAY-9 [MUST]** `payment_status` (derived, COM‑19):

- `unpaid` — paid so far = 0

- `deposit_paid` — paid so far > 0, and every `paid` payment is `type = deposit`

- `part_paid` — 0 < paid so far < `effective_cost`

- `paid_in_full` — paid so far ≥ `effective_cost` **and** `effective_cost > 0`

- (if `effective_cost = 0` and paid so far = 0 → `unpaid`; if `effective_cost = 0` and paid so far > 0 → `paid_in_full`)

### 4.3 Full payments

- **PAY-10 [MUST]** Reaching `paid_in_full` **does not** change the commitment's `status`. The prototype's "Fully Paid" status value does not exist; it was a payment state, and it is derived.

- **PAY-11 [SHOULD]** When a commitment becomes `paid_in_full`, the system may suggest advancing its status to `booked`/`completed`.

### 4.4 Outstanding balances

- **PAY-12 [MUST]** **Commitment outstanding** = `max(effective_cost − paid so far, 0)` for display. The raw value (which can be negative when overpaid) is retained for PAY‑13.

- **PAY-13 [SHOULD]** If `paid so far > effective_cost`, surface "overpaid by X" as an `info` note on the commitment.

- **PAY-14 [MUST]** **Scheduled outstanding** (cash‑flow view) = Σ `amount` of `scheduled` payments (not `paid`/`waived`/`cancelled`) on non‑cancelled commitments. This is distinct from cost‑basis outstanding (§6) and is used only for due‑date / "what's coming up" views.

### 4.5 Due dates

- **PAY-15 [MUST]** `due_on` is a date, no time. Compared using project‑timezone "today" (GC‑4).

- **PAY-16 [MUST]** A `scheduled` payment with a `due_on` contributes a timeline event (§7).

### 4.6 Overdue payments

- **PAY-17 [MUST]** A payment is **overdue** (derived) when `status = scheduled` **and** `due_on` is set **and** `due_on < today` (project timezone). Not stored.

- **PAY-18 [MUST]** Overdue payments raise HLT‑3 (`blocker`).

- **PAY-19 [SHOULD]** A `scheduled` payment with `today ≤ due_on ≤ today + 7 days` is "due soon" and raises HLT‑4 (`warning`).

### 4.7 Cancellations

- **PAY-20 [MUST]** `status` transitions: `scheduled → {paid, waived, cancelled}`; `paid → scheduled` (undo, **[SHOULD]**); `waived`/`cancelled → scheduled` (reopen, **[SHOULD]**).

- **PAY-21 [MUST]** `cancelled` = "this planned payment will not happen as recorded." `waived` = "this charge no longer applies" (e.g. the supplier dropped a fee). **Both are excluded from every sum** (paid, outstanding, scheduled outstanding).

- **PAY-22 [MUST]** Prefer `cancelled`/`waived` over deletion. A `paid` payment **[SHOULD]** not be hard‑deletable — cancel it instead. Soft‑deleted payments are excluded from all sums.

### 4.8 Refunds

- **PAY-23 [MUST — minimal]** A refund is a `Payment` with `type = refund`, `direction = incoming`, positive `amount`, `status ∈ {scheduled, paid}`. A `paid` refund contributes to **Refunded amount** and reduces **Net actual spend** (PAY‑8, §8). Refunds remain recordable after the related commitment is cancelled because cancellation must not erase subsequent money returned.

- **PAY-24 [SHOULD]** Warn if total refunds on a commitment exceed total outgoing payments.

- **PAY-25 [FUTURE]** Linking a refund to the original payment; partial‑refund workflows; refund reason codes.

---

PAYMENT HISTORY HARDENING

PAY-26 [MUST]
Once a Payment has status = paid, the following fields are immutable:
amount, direction, type, commitment_id, paid_by_member_id, paid_on.

PAY-27 [MUST]
A paid Payment may only be corrected by explicitly transitioning
paid → scheduled. This transition is audited. Once reopened,
financially material fields may be edited and the Payment may then
be marked paid again.

PAY-28 [MUST]
A paid Payment cannot be soft-deleted or hard-deleted.
Cancellation is not a substitute for correcting a paid Payment.
Refunds remain separate incoming Payment rows.

AUD-XX [MUST]
Every transition into or out of status = paid and every subsequent
financial-field modification must be represented in the audit log.

## 5. Tasks

### 5.1 Creation

- **TSK-1 [MUST]** Any `organizer`/`member` can create a `Task` in a non‑archived project.

- **TSK-2 [MUST]** Required: `title` (1–120), `project_id`. Optional: `commitment_id`, `assignee_member_id`, `due_on`, `notes`.

- **TSK-3 [MUST]** `status` defaults to `open`.

### 5.2 Assignment

- **TSK-4 [MUST]** `assignee_member_id` is optional; if set, must be an `active` member with `role ∈ {organizer, member}` (not `viewer`, not `removed`).

- **TSK-5 [MUST]** Reassignment is allowed at any time by any `organizer`/`member`.

### 5.3 Due dates

- **TSK-6 [MUST]** `due_on` is an optional date (no time). May be in the past.

- **TSK-7 [MUST]** A task with `due_on` and `status ∈ {open, in_progress}` contributes a timeline event (§7).

### 5.4 Completion

- **TSK-8 [MUST]** `status ∈ {open, in_progress, done, cancelled}`. `open ↔ in_progress` freely; either → `done`; any → `cancelled`.

- **TSK-9 [MUST]** Setting `done` sets `completed_at = now`. Reopening (`done → open/in_progress`) clears `completed_at`.

- **TSK-10 [MUST]** `cancelled` tasks are excluded from health findings and timeline.

### 5.5 Relationship to commitments

- **TSK-11 [MUST]** `commitment_id` is optional. If set, the commitment must be in the same project (VAL‑30).

- **TSK-12 [MUST]** Tasks never carry cost, participants, or payments and never affect the budget.

- **TSK-13 [MUST]** Soft‑deleting a commitment soft‑deletes its child tasks (COM‑43); they are restorable if the commitment is restored. **[SHOULD]** offer "keep as project task" instead.

- **TSK-14 [FUTURE]** Subtasks, checklists, dependencies, recurrence, comments, attachments.

---

## 6. Milestones

A thin, manual date marker for something significant that is **not** already a commitment, payment, or task.

### 6.1 Creation

- **MIL-1 [MUST]** An `organizer` can create a `Milestone`. **[SHOULD]** allow `member`s.

- **MIL-2 [MUST]** Required: `title` (1–120), `on_date`. Optional: `commitment_id` (same project — VAL‑30), `notes`.

- **MIL-3 [MUST]** Derived milestone‑like markers (project start/end, payment due dates, "checkout") are **not** `Milestone` rows — they come from other entities (§7). A `Milestone` row is only for user‑pinned dates with no other home.

### 6.2 Completion

- **MIL-4 [MUST]** MVP milestones have **no completion state**. A milestone is `upcoming` if `on_date ≥ today` and `passed` if `on_date < today` — both derived, purely from the date.

- **MIL-5 [MUST]** If a user needs "done/not done" semantics for a dated thing, they use a `Task`. The UI **[SHOULD]** guide this.

- **MIL-5a [MUST]** This separation is deliberate for MVP: a `Milestone` represents an important date; a `Task` represents work that can be completed. Do not add task-style completion fields to milestones in the MVP schema.

- **MIL-6 [FUTURE]** Optional manual "acknowledged/handled" flag on milestones.

### 6.3 Dates

- **MIL-7 [MUST]** `on_date` is a single date — no range, no time. Compared using project‑timezone "today" (GC‑4).

- **MIL-8 [MUST]** A milestone contributes exactly one timeline event, at `on_date` (§7).

- **MIL-9 [MUST]** Deleting a linked commitment clears `commitment_id` (COM‑44); the milestone itself is unaffected.

---

## 7. Timeline

The timeline is **fully derived** ([DOMAIN_MODEL §7.2]). There is no timeline entity and no stored `upcoming[]` list.

### 7.1 Contributing events

- **TML-1 [MUST]** The following entities contribute events, all within one project:

| Source | Condition | Event time | Event type | Title |

|--------|-----------|------------|-----------|-------|

| `Commitment` | `starts_at` set, not `cancelled`/deleted | `starts_at` (and a paired end event at `ends_at` if set) | `commitment` | commitment `title` |

| `Payment` | `status = scheduled`, `due_on` set, commitment not cancelled | `due_on` (start of day, project tz) | `payment_due` | "{amount} due — {commitment title}" |

| `Payment` | `status = paid`, `paid_on` set | `paid_on` | `payment_made` | "{amount} paid — {commitment title}" **[SHOULD]** |

| `Task` | `status ∈ {open, in_progress}`, `due_on` set | `due_on` (start of day) | `task_due` | "Task: {title}" |

| `Milestone` | always | `on_date` (start of day) | `milestone` | milestone `title` |

| `Project` | `starts_on` set | `starts_on` | `project_start` | "{project name} starts" |

| `Project` | `ends_on` set | `ends_on` | `project_end` | "{project name} ends" |

- **TML-2 [MUST]** Ordering: ascending by event time. Date‑only events sort at 00:00 in the project timezone. Ties broken by event type priority (`project_start` < `commitment` < `payment_due` < `task_due` < `milestone` < `project_end`) then title.

- **TML-3 [MUST]** Grouping by calendar day is a presentation concern; the derivation returns a flat ordered list with each event's `subject_ref`.

- **TML-4 [MUST]** Past and future events are both included. Default view position is "today".

- **TML-5 [SHOULD]** "Upcoming" (dashboard / project Overview) = timeline filtered to `[now, now + 14 days]`. Window is configurable.

- **TML-6 [SHOULD]** Global **Calendar** = the same derivation unioned across every non‑archived project where the current user is an `active` member, tagged by project.

- **TML-7 [MUST]** `cancelled` and soft‑deleted sources contribute nothing.

- **TML-8 [FUTURE]** iCal export feed, external calendar sync, per‑event reminders, travel‑time blocks between consecutive commitments.

---

## 8. Budget

**Single source of truth (GC‑7):** the only persisted budget data is **targets** — `Budget.total_target` and `BudgetCategoryTarget.amount` per `kind`. Every other figure below is derived from `Commitment` + `Payment` + `CostShare`. No aggregate is stored as an editable field.

### 8.1 Inputs

- **BUD-1 [MUST]** `Budget` is optional. A project with no `Budget` shows "no budget set" wherever a target‑relative figure would appear; **Total cost**, **Committed spend**, **Gross paid amount**, **Refunded amount**, **Net actual spend**, and **Outstanding** are still computed and shown.

- **BUD-2 [MUST]** `total_target ≥ 0`. Each `BudgetCategoryTarget` is one row per `kind`, `amount ≥ 0`.

- **BUD-3 [MUST]** The sum of category targets **need not** equal `total_target`. **[SHOULD]** surface the difference ("categories total X of your Y budget").

### 8.2 Definitions

Let a commitment's **effective cost** be `confirmed_cost ?? estimated_cost ?? 0` (COM‑21). All sums below exclude soft‑deleted rows and `cancelled` commitments (GC‑8).

- **BUD-4 [MUST] — Total cost (projected)**

`Σ effective_cost` over **all non‑cancelled commitments** (any status, including `idea` and `researching`).

*Rationale:* this is the full projected spend the group is contemplating.

- **BUD-5 [MUST] — Committed spend**

`Σ effective_cost` over commitments with `status ∈ {confirmed, booked, completed}`.

*Rationale:* money the group is realistically on the hook for. This is the prototype's "committed".

- **BUD-6 [MUST] — Financial-history metrics**

- **Gross paid amount** = `Σ amount` of all `paid` `outgoing` payments, including those attached to commitments later cancelled.

- **Refunded amount** = `Σ amount` of all `paid` `incoming` refund payments, including refunds recorded after commitment cancellation.

- **Net actual spend** = `Gross paid amount − Refunded amount`.

Exclude `cancelled`/`waived`/soft‑deleted payment rows. Commitment cancellation does **not** remove historical paid/refunded money from these metrics. In UI copy, do not label net actual spend simply "Paid" where that could imply gross cash paid.

- **BUD-7 [MUST] — Outstanding amount** (active commitment cost basis — the headline figure)

For each non‑cancelled commitment with `status ∈ {confirmed, booked, completed}`, compute `max(effective_cost − net paid so far for that commitment, 0)` and sum the results. Payments/refunds attached to cancelled commitments remain in financial history (BUD‑6) but do not create negative or misleading outstanding balances for active commitments. If an active commitment's net paid exceeds its effective cost, surface "overpaid by X" on that commitment (PAY‑13).

- **BUD-8 [MUST] — Remaining budget**

Requires a `Budget`. `total_target − Total cost` (uses **Total cost**, BUD‑4, not Committed — remaining budget must account for everything currently planned).

May be negative → project is projected over budget.

- **BUD-9 [MUST] — Budget variance**

- **Projected variance** = `total_target − Total cost` (identical value to Remaining budget, framed as over/under: positive = under budget, negative = over).

- **Settled variance** (meaningful near/after `completed`) = `total_target − Net actual spend`.

- **Per‑category variance** = `BudgetCategoryTarget.amount − (Σ effective_cost of non‑cancelled commitments of that kind)`. Only computed for kinds that have a target.

- **BUD-10 [MUST] — Category actuals**

For each `kind`: `Σ effective_cost` of non‑cancelled commitments of that kind. (The prototype's `budgetBreakdown` becomes target + actual per kind.)

### 8.3 Per‑member balances ("who owes what")

- **BUD-11 [MUST]** A member's **share** of a commitment:

- If the commitment has `CostShare` rows: use them (`basis = equal` → equal among the listed members; `weight` → proportional; `fixed` → the fixed amount, with any unfixed remainder split equally among the rest).

- Else: **equal split among the commitment's current participants**.

- Else (no participants): the cost is **unallocated** — it appears in no member's balance and raises HLT‑16.

- **BUD-12 [MUST]** Member shares are computed only over commitments with `status ∈ {confirmed, booked, completed}` (same basis as Committed spend — you do not "owe" for an `idea`).

- **BUD-13 [MUST]** **Member owed** = Σ that member's share across those commitments.

- **BUD-14 [MUST]** **Member contributed** = Σ `amount` of `paid` `outgoing` payments where `paid_by_member_id` = that member − Σ `paid` incoming refunds attributed back to that member. Contributions preserve historical money movement even if the associated commitment is later cancelled.

- **BUD-15 [MUST]** **Member balance** = `Member contributed − Member owed`. Negative → "Owes £X"; positive → "Is owed £X"; zero → "Settled".

- **BUD-16 [MUST]** Rounding: equal splits distribute remainder minor units deterministically (the first *r* members by a stable order each get +1 minor unit) so that shares always sum **exactly** to the commitment cost.

- **BUD-17 [FUTURE]** Settlement suggestions ("Tom pays Mike £40"), settlement tracking, in‑app payment collection.

### 8.4 Priority

- **[MUST]** BUD‑4, BUD‑5, BUD‑6, BUD‑7, BUD‑8, BUD‑9 (projected variance), BUD‑10, BUD‑11–BUD‑16.

- **[SHOULD]** BUD‑3, BUD‑9 (settled + per‑category variance), scheduled‑outstanding view.

- **[FUTURE]** BUD‑17.

---

## 9. Health

The health engine is **deterministic and derived** ([DOMAIN_MODEL §7.3]). Findings are computed on read. The only persisted health data is optional `FindingState` (dismiss/snooze).

### 9.1 Finding model

- **HLT-A [MUST]** Each rule evaluates to zero or more `Finding`s: `{ code, severity, subject_ref, message, resolution, affects_health }`.

- **HLT-B [MUST]** `severity ∈ {blocker, warning, info, ok}`.

- **HLT-C [MUST]** **Project health status** (derived rollup):

- **Needs attention** — at least one non‑dismissed `blocker` finding.

- **At risk** — at least one non‑dismissed `warning` finding and no blockers.

- **Healthy** — only `info`/`ok` findings (or none).

- **HLT-D [MUST]** `affects_health = true` means the finding's severity feeds HLT‑C. `info` and `ok` findings never change the rollup (`affects_health = false`), but `ok` findings are still shown as positive signals.

- **HLT-E [MUST]** **"Needs attention" list** (dashboard + project Overview) = non‑dismissed findings with `severity ∈ {blocker, warning}`, sorted by severity (blocker first) then by the subject's relevant date. **`attentionCount`** = length of that list.

- **HLT-F [SHOULD]** A `warning` or `info` finding can be **dismissed** (hidden permanently for that subject+code) or **snoozed** (hidden until a date, default +7 days) by any `organizer`/`member`. **[MUST]** `blocker` findings **cannot** be dismissed or snoozed — only resolved by fixing the trigger.

- **HLT-G [MUST]** Findings are recomputed on every read. No background evaluation in MVP. **[FUTURE]** scheduled evaluation to drive notifications.

- **HLT-H [MUST]** `cancelled` and soft‑deleted entities are never the subject of a finding.

- **HLT-I [MUST]** All thresholds below are **configuration values with the defaults given**, not literals ([DOMAIN_MODEL D‑6]).

### 9.2 Initial rule set

| Code | Priority | Severity | Affects health | Trigger | Message template | Resolution |

|------|----------|----------|:---:|---------|------------------|-----------|

| **HLT-1** `missing_owner` | MUST | warning | ✅ | Commitment `status ∈ {researching, confirmed, booked}` and `owner_member_id IS NULL` | "{title} has no owner" | Assign an owner |

| **HLT-2** `orphaned_owner` | MUST | warning | ✅ | `owner_member_id` points to a member with `status = removed` | "{title}'s owner ({name}) has left the project" | Assign a new owner |

| **HLT-3** `payment_overdue` | MUST | blocker | ✅ | Payment `status = scheduled`, `due_on < today` (project tz) | "{amount} for {commitment title} was due on {due_on}" | Record it as paid, or reschedule / cancel it |

| **HLT-4** `payment_due_soon` | SHOULD | warning | ✅ | Payment `status = scheduled`, `today ≤ due_on ≤ today + 7d` | "{amount} for {commitment title} is due {due_on}" | Pay it, or snooze if on track |

| **HLT-5** `missing_booking_reference` | MUST | warning | ✅ | Commitment `status ∈ {confirmed, booked, completed}` and (`booking.reference IS NULL` or `booking.confirmed = false`) | "{title} is {status} but has no confirmed booking reference" | Add the reference and mark the booking confirmed |

| **HLT-6** `unconfirmed_near_date` | SHOULD | warning | ✅ | Commitment `status ∈ {idea, researching}`, `starts_at` set, `starts_at ≤ now + 14d` | "{title} is still {status} but happens in {n} days" | Confirm it or cancel it |

| **HLT-7** `commitment_inactive` | SHOULD | warning | ✅ | Commitment `status ∈ {idea, researching}`, `updated_at < now − 7d` | "{title} hasn't been updated in {n} days" | Update it, advance its status, or cancel it |

| **HLT-8** `missing_cost` | SHOULD | warning | ✅ | Commitment `status ∈ {confirmed, booked, completed}` and `effective_cost = 0` | "{title} is {status} but has no cost recorded" | Add the cost, or note that it's free |

| **HLT-9** `budget_exceeded` | MUST | warning | ✅ | `Budget.total_target` set and **Total cost** > `total_target` | "Projected spend ({total}) is {overage} over the {target} budget" | Raise the budget, cut costs, or cancel commitments |

| **HLT-10** `category_over_target` | SHOULD | info | ❌ | A `BudgetCategoryTarget` exists for kind K and category actual (BUD‑10) > that target | "{kind} spend ({actual}) is over its {target} target" | Adjust the target or the commitments |

| **HLT-11** `schedule_conflict` | SHOULD | warning | ✅ | Two non‑cancelled commitments with `starts_at`/`ends_at` intervals that overlap | "{title A} overlaps {title B} on {date}" | Adjust the times, or snooze if intentional |

| **HLT-12** `tight_connection` | SHOULD | info | ❌ | Two non‑cancelled scheduled commitments same day, `0 ≤ gap < 20 min` | "Only {gap} between {title A} and {title B}" | Adjust times or acknowledge |

| **HLT-13** `task_overdue` | MUST | warning | ✅ | Task `status ∈ {open, in_progress}`, `due_on < today` | "Task '{title}' was due {due_on}" | Complete it, reschedule it, or cancel it |

| **HLT-14** `task_unassigned_due_soon` | SHOULD | info | ❌ | Task `status ∈ {open, in_progress}`, `assignee IS NULL`, `due_on ≤ today + 7d` | "Task '{title}' is due soon with no assignee" | Assign it |

| **HLT-15** `outside_project_dates` | SHOULD | info | ❌ | Project dates set and a commitment's `starts_at` date outside `[starts_on, ends_on]` | "{title} is scheduled outside the project dates" | Adjust the commitment or project dates |

| **HLT-16** `unallocated_cost` | SHOULD | info | ❌ | Non‑cancelled commitment, `effective_cost > 0`, no participants and no cost shares | "{title}'s cost isn't split between anyone" | Add participants or set a cost split |

| **HLT-17** `on_budget` | SHOULD | ok | ❌ | `Budget.total_target` set, **Total cost** ≤ `total_target`, and (within 30d of `ends_on` **or** ≥ 50% of commitments are `confirmed`+) | "Projected spend is {variance} under budget — on track" | — (positive signal) |

### 9.3 Prototype coverage check

The prototype's hand‑authored lists map cleanly onto the rules:

| Prototype item | Rule |

|----------------|------|

| "Payment due — Boat Party — £800 due 12 May" | HLT‑4 (or HLT‑3 if past due) |

| "Missing owner — Airport Transfer" | HLT‑1 |

| "Booking incomplete — Restaurant — confirmation number missing" | HLT‑5 |

| "Timeline risk — 18 min gap" | HLT‑12 |

| "Budget risk — tracking £320 under budget — on course" | HLT‑17 |

| "Inactive item — Airport Transfer — no update for 9 days" | HLT‑7 |

### 9.4 Priority

- **[MUST]** HLT‑1, HLT‑2, HLT‑3, HLT‑5, HLT‑9, HLT‑13; the rollup (HLT‑C), the needs‑attention list (HLT‑E), non‑dismissable blockers (HLT‑F).

- **[SHOULD]** HLT‑4, HLT‑6, HLT‑7, HLT‑8, HLT‑10, HLT‑11, HLT‑12, HLT‑14, HLT‑15, HLT‑16, HLT‑17; dismiss/snooze; `FindingState` persistence.

- **[FUTURE]** scheduled evaluation, notification delivery, per‑user finding preferences, ML/predictive risk, custom rules.

---

## 10. Edge cases & validation rules

### 10.1 Field validation

| ID | Rule | Priority |

|----|------|----------|

| VAL-1 | Project `starts_on ≤ ends_on` when both set | MUST |

| VAL-2 | Project `name`: 1–120 chars, trimmed, non‑blank | MUST |

| VAL-3 | Project `currency`: valid ISO‑4217; immutable once any commitment/payment exists (PRJ‑16a) | MUST |

| VAL-4 | Project `timezone`: valid IANA name | MUST |

| VAL-5 | `ProjectMember.display_name`: 1–80 chars, trimmed, non‑blank | MUST |

| VAL-6 | `ProjectMember.email`: valid email format when present | MUST |

| VAL-7 | One `ProjectMember` per `(project, user_id)`; one per `(project, email)` among non‑removed rows | MUST |

| VAL-8 | One `pending` `Invitation` per `(project, email)` | MUST |

| VAL-9 | `Commitment.title`: 1–120, trimmed, non‑blank; `kind` ∈ enum | MUST |

| VAL-10 | `Commitment.ends_at ≥ starts_at` when both set | MUST |

| VAL-11 | `Commitment.estimated_cost`, `confirmed_cost` ≥ 0 when set | MUST |

| VAL-12 | `Commitment.owner_member_id`: active member, role ∈ {organizer, member} | MUST |

| VAL-13 | `CommitmentParticipant`: member is active; unique per `(commitment, member)` | MUST |

| VAL-14 | `CostShare`: `basis ∈ {equal, weight, fixed}`; `weight > 0` when `basis = weight`; `fixed_amount ≥ 0` when `basis = fixed`; unique per `(commitment, member)` | MUST |

| VAL-15 | `Payment.amount` > 0 (strictly); integer minor units | MUST |

| VAL-16 | `Payment.paid_on` required iff `status = paid`; `paid_on ≤ today` | MUST |

| VAL-17 | `Payment` cannot be created on a `cancelled` or soft‑deleted commitment | MUST |

| VAL-18 | `Payment.paid_by_member_id`: active or removed member of the same project (not another project) | MUST |

| VAL-19 | `Task.title`: 1–120; `assignee_member_id` active, role ∈ {organizer, member}; `commitment_id` (if set) same project | MUST |

| VAL-20 | `Milestone.title`: 1–120; `on_date` required; `commitment_id` (if set) same project | MUST |

| VAL-21 | `Budget.total_target ≥ 0`; one `BudgetCategoryTarget` per `kind`; each `amount ≥ 0` | MUST |

| VAL-22 | All money writes must match the project currency | MUST |

| VAL-23 | Enum writes rejected if value not in the defined set | MUST |

### 10.2 Behavioural edge cases

| ID | Situation | Defined behaviour | Priority |

|----|-----------|-------------------|----------|

| VAL-24 | Participant removed from an equal‑split commitment | Equal‑split `CostShare` recalculated over remaining participants; fixed/weighted shares untouched; if participants hit zero, cost becomes unallocated (HLT‑16) | MUST |

| VAL-25 | Commitment cost changed after payments recorded | `payment_status`, outstanding, and member balances all recompute; `paid_in_full` may flip to `part_paid` and vice versa; no data loss | MUST |

| VAL-26 | Commitment cancelled with `paid` payments on it | Payments retained but excluded from all sums; money already spent is **not** reflected in "Paid amount" (it belongs to a cancelled commitment). **[SHOULD]** surface "£X spent on cancelled commitments" as an `info` note | MUST / SHOULD |

| VAL-27 | Commitment un‑cancelled (`cancelled → researching`) | Its payments re‑enter all sums as they were; auto‑cancelled payments (COM‑18) are **not** auto‑restored — user re‑activates them | MUST |

| VAL-28 | Owner removed from project | HLT‑2; commitment stays owned by the removed member until reassigned | MUST |

| VAL-29 | Member with a negative balance leaves | Balance still computed and shown ("former member owes £X"); no settlement enforcement in MVP | SHOULD |

| VAL-30 | `commitment_id` on a task/milestone points to a commitment in another project | Rejected at write time | MUST |

| VAL-31 | Two payments both marked `full` on one commitment | Allowed; both count; likely produces "overpaid" (PAY‑13). **[SHOULD]** warn at entry | SHOULD |

| VAL-32 | Refunds exceed payments on a commitment | Allowed; "paid so far" goes negative; **[SHOULD]** warn; project "Paid amount" can be reduced accordingly | SHOULD |

| VAL-33 | Budget removed after category targets exist | Category targets are retained but inert; all target‑relative figures show "no budget set" | SHOULD |

| VAL-34 | Project has no dates; commitment has a date | Fine. HLT‑15 cannot fire (no range to be outside of) | MUST |

| VAL-35 | Commitment `starts_at` with no `ends_at` | Valid; contributes a single point event to the timeline; no overlap/gap analysis with it as the "end" side | MUST |

| VAL-36 | All‑day commitment overlapping a timed one | Overlap detection uses the all‑day span = the project‑tz calendar day; HLT‑11 may fire | SHOULD |

| VAL-37 | DST transition inside a commitment's span | Duration computed from absolute instants; display uses project tz; no special handling | MUST (rely on tz library) |

| VAL-38 | Equal split with indivisible amount (e.g. £10 / 3) | Deterministic remainder distribution (BUD‑16): shares are £3.34, £3.33, £3.33 | MUST |

| VAL-39 | Last organizer tries to leave / be removed / be demoted / delete their account | Blocked with a clear reason; must promote another organizer or delete the project first | MUST |

| VAL-40 | Invitation accepted after the inviter left the project | Still valid; membership created; role as specified | SHOULD |

| VAL-41 | Invitation email later differs in case / whitespace from a member's email | Email matching is case‑insensitive and trimmed | MUST |

| VAL-42 | Archived project: any write attempt | Rejected (PRJ‑17) except un‑archive / delete | MUST |

| VAL-43 | Health finding whose subject is edited so the trigger no longer holds | Finding simply disappears on next read; any `FindingState` for it is left dormant (reactivates if the same code+subject recurs) | SHOULD |

| VAL-44 | Same real person added twice as two name‑only members | Allowed (system can't know); **[SHOULD]** offer a merge action; balances/ownership stay separate until merged | SHOULD |

| VAL-45 | Payment due date in the past at creation, status `scheduled` | Valid; immediately counts as overdue (HLT‑3) | MUST |

| VAL-46 | Commitment with `effective_cost = 0` and status `confirmed` | Counts as £0 everywhere; HLT‑8 fires | SHOULD |

| VAL-47 | Deleting a commitment that a milestone links to | Milestone survives, link cleared (COM‑44) | MUST |

| VAL-48 | Project progress with zero non‑cancelled commitments | Progress = 0% (define 0/0 → 0) | MUST |

### 10.3 Project progress (derived)

- **VAL-49 [MUST]** **Progress %** = `round( count(commitments with status ∈ {confirmed, booked, completed}) / count(commitments with status ≠ cancelled) × 100 )`. Zero commitments → 0% ([DOMAIN_MODEL D‑5]). This is the single definition; the prototype's stored `progress` does not carry over.

---

## 11. MVP scope summary

### 11.1 MUST support in MVP

- Projects: create, draft→active, complete, archive, un‑archive, soft‑delete with cascade; single currency; collective organizer ownership; last‑organizer protection.

- Members: name‑only and invited; three roles; the permission matrix (MEM‑14); soft removal with reference preservation; leaving.

- Invitations: single pending per email; accept (authenticated); claim matching name‑only member.

- Commitments: create with `title`+`kind`; six `kind`s; six‑state lifecycle with user‑set status; single nullable owner (by reference); explicit participant set; optional structured dates; embedded location; embedded supplier/booking; soft‑delete with cascade.

- Payments: attached to commitments; `scheduled`/`paid`/`waived`/`cancelled`; partial payments; derived `payment_status`; overdue detection; minimal refunds.

- Tasks: create; optional assignee/commitment/due date; open→in_progress→done→cancelled; cascade with commitment.

- Milestones: create with `title`+`on_date`; no completion state; timeline contribution.

- Budget: optional targets only; derived Total cost, Committed spend, Paid amount, Outstanding, Remaining, projected variance, category actuals; derived per‑member balances with deterministic rounding.

- Timeline: fully derived from the seven sources (TML‑1); per‑project view; "today"‑anchored.

- Health: rules HLT‑1/2/3/5/9/13; blocker/warning/info/ok; project‑health rollup; needs‑attention list + count; non‑dismissable blockers.

- All validation rules tagged MUST in §10.

- Derived progress % (VAL‑49).

### 11.2 SHOULD support in MVP

- Draft status niceties; archived‑project exclusion from dashboards; typed‑name delete confirmation; 30‑day project recovery.

- Member‑initiated invitations (configurable); invitation expiry/revoke; name‑only↔user merge.

- `idea` as a creation‑time status choice; empty initial participant set; soft confirmation dialogs on status advance; auto‑cancel scheduled payments when a commitment is cancelled.

- Overpaid / "spent on cancelled" info notes; refund > payment warnings; scheduled‑outstanding cash‑flow view.

- "Keep as project task" when deleting a commitment.

- Health rules HLT‑4/6/7/8/10/11/12/14/15/16/17; dismiss/snooze with `FindingState`.

- Settled variance and per‑category variance; category‑vs‑total reconciliation hint.

- Global Calendar view; "upcoming" window; `payment_made` timeline events.

- Optimistic‑concurrency version token.

- Duplicate‑member merge action.

### 11.3 FUTURE (explicitly out of scope)

- Multi‑currency, per‑commitment currency, FX.

- `Supplier` and `Place` as first‑class entities; supplier directory; geocoding; maps; saved places; travel‑time enrichment.

- Co‑owners / commitment collaborators; per‑resource and per‑field permissions.

- Global `Contact` / address book; the standalone "People" screen; cross‑project person identity.

- Payment collection through the platform; settlement graph ("who pays whom"); payment reminders/automation; refund linking and reason codes.

- Participant‑facing RSVP; date‑availability polls.

- Comments, activity feed, attachments/documents, notifications (email/push) and scheduled health evaluation.

- Project templates; recurring commitments/tasks; subtasks, checklists, task dependencies.

- iCal export/sync; per‑event reminders.

- Real‑time collaboration / presence.

- Custom health rules; predictive/ML risk scoring; per‑user finding preferences.

- Invite links, bulk invites, join‑request approval, domain auto‑join.

- Manual milestone acknowledgement.

---

## 12. Single‑source‑of‑truth register

To guarantee no redundant sources of truth, every derived concept and its one authoritative input set:

| Derived concept | Computed from (only) | Never stored as |

|-----------------|----------------------|-----------------|

| Total cost / Committed spend | `Commitment.confirmed_cost / estimated_cost` + `status` | a project column |

| Paid amount | `Payment.amount` + `status` + `direction` | a project or commitment column |

| Outstanding (cost basis) | Committed spend − Paid amount | stored |

| Scheduled outstanding | `Payment.amount` where `status = scheduled` | stored |

| Remaining budget / variance | `Budget.total_target` − Total cost | stored |

| Category actuals / variance | `Commitment.effective_cost` grouped by `kind`, vs `BudgetCategoryTarget` | stored |

| Per‑member balance | `CostShare` (or participant equal split) + `Payment.paid_by_member_id` | a member column |

| Commitment `payment_status`, outstanding | that commitment's `Payment` rows + `effective_cost` | a commitment column |

| Commitment `has_open_issues` | health findings for that commitment | a commitment column |

| A member's "responsibilities" | `Commitment.owner_member_id` reverse lookup | a member column / array |

| Participant count | `count(CommitmentParticipant)` | `Commitment.participants` |

| Project progress % | `Commitment.status` counts (VAL‑49) | `Project.progress` |

| Timeline / Upcoming / Calendar | the seven sources in TML‑1 | a timeline table |

| Health findings / needs‑attention / attentionCount | the rule set in §9.2 over live entities | a findings table (only `FindingState` for dismiss/snooze) |

| Project health status | rollup of current findings (HLT‑C) | `Project.health` |

| Payment overdue / due‑soon | `Payment.status` + `due_on` vs today | a payment column |

| Milestone upcoming / passed | `Milestone.on_date` vs today | a milestone column |

| "Unassigned" / "missing" labels | null checks on the relevant field | boolean flags (`missingOwner`, `missingBooking`) |