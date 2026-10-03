# Phase 9 — debtor payment acknowledgement

Verification date: 2026-09-30. Target: **develop `msfkczsoutbeyhjvegnw` only**.

“I've paid” records a debtor claim, not proof of receipt. Request status remains open;
no acknowledgement/undo path records settlement or changes the financial ledger.

## A. Existing architecture audit

Before implementation, inspected Phase 7 immutable reimbursement requests, the existing
Activity settlement fingerprint and read permissions, Phase 8 debtor payment options,
request cancellation, notification/event/audit pipeline, Health, member balances,
archive/delete behavior and the existing `record_item_settlement` mechanism.
The architecture map and decisions are in [Payment acknowledgements](PAYMENT_ACKNOWLEDGEMENTS.md).
No alternative “who owes whom” calculation was introduced.

## B. Acknowledgement model

Separate `reimbursement_payment_acknowledgements` rows reference the stable request,
project and debtor. Authenticated creator and `clock_timestamp()` are server-derived.
Acknowledgement applies to the full immutable request amount; no editable amount,
provider, payment URL, client timestamp, note or partial-payment allocation is stored.
A sanitized, separately queried status view exposes active ID, allowed actions and history.

## C. Lifecycle

Outstanding → Payment sent / Awaiting confirmation is a workflow presentation change.
The request remains open, and its amount/basis is unchanged. An active row has no
withdrawn timestamp. Undo returns to Outstanding when the request is still eligible.
There is no Paid, Settled, Received or Complete acknowledgement state.

## D. Authority

Only the actual active debtor can acknowledge or undo, including a Viewer debtor.
Organizer/creditor authority cannot impersonate a debtor. Anonymous, unrelated,
cross-project, pending and removed callers are denied. Both participants must be active,
parents live, project writable, and request open/current. Removed-creditor history is
retained, but no new transition is permitted while that creditor is inactive.

## E. Idempotency

Activity → project → request → ordered participant locks serialize state checks with
cancellation, financial changes and membership changes. One partial unique index permits
at most one active claim. Repeated/concurrent acknowledgement returns that same ID;
no duplicate fact or notification. Live concurrent retry and undo checks passed.

Concurrent acknowledge/undo has a valid serial order, not a predetermined network winner:
retry before undo ends withdrawn; undo before acknowledge creates a fresh active row.
The live runner verifies the outcome against the returned identity and retained history.

## F. Withdrawal

Undo targets an **acknowledgement ID**, not just its parent request. It stamps withdrawal
once and retains the original row; exact repeat is harmless while otherwise eligible.
Re-acknowledgement creates a new row. A delayed retry against an older withdrawn ID cannot
withdraw the newer active claim. Immutability guards reject identity/timestamp edits and
hard deletion, including accidental privileged writes.

## G. Review-needed behavior

Existing settlement-basis comparison is reused. A refund, share edit or independent
existing settlement may make a request Review needed. Claim history remains; normal
acknowledge/undo/payment actions are suppressed server-side. UI gives Review needed
precedence and says payment was previously marked as sent. Refund behavior was verified
in the real browser; SQL additionally covers share edits and an independent settlement.

## H. Cancellation behavior

Phase 7 cancellation authority remains unchanged. The UI warns that the debtor marked
payment sent and cancellation will not record settlement. Cancellation retains claim
history and removes actionable notification/payment state. Browser financial snapshots
excluding the intentionally cancelled request stayed identical.

## I. Payment-link interaction

Active claims hide the normal payment-link CTA and return zero options from
`get_reimbursement_payment_options`. The renamed earlier implementation is not executable
by clients. Undo restores options only when otherwise eligible. The live browser verified
link restoration and that clicking an external link does not create an acknowledgement.
Provider navigation was blocked before transmission. A claim was also made successfully
without any configured payment link.

## J. Financial isolation

SQL and real HTTP snapshots compare `payments`, `cost_shares`, reimbursement rows,
`v_project_financials`, `v_activity_member_settlements`, `v_member_balances` and
`v_activity_payment_schedule_financials`. Acknowledge, retry, undo, re-acknowledge and
concurrent operations leave these unchanged. No application/acknowledgement RPC invokes
`record_item_settlement`, writes paired transfers or alters spending, schedules or shares.
The SQL regression invokes the pre-existing settlement API only as an independent
mutation to test stale history; this is not a Phase 9 settlement implementation.

## K. Domain events

Two private-pipeline events: `reimbursement.payment_acknowledged` and
`reimbursement.payment_acknowledgement_withdrawn`. Resource is the acknowledgement ID;
keys are `acknowledged` / `withdrawn`. Payload is exactly Activity ID plus request ID.
No amount, URL, provider or profile payload. Processing/action receipts and notifications
share the mutation transaction. Retry emits no duplicate; re-acknowledgement is a new fact.

## L. Notifications

Only the actual creditor receives acknowledgement/withdrawal notifications. There is no
debtor self-notice, project broadcast, Organizer fallback or external email. Notifications
resolve current authorized request data, retain neutral review copy when stale, and hide
cancelled/deleted or superseded states. Deep links open Activity `section=reimbursements`;
real-browser routing, read marking and section focus passed. Original debtor request
notifications are hidden while an active claim exists to avoid encouraging duplicate payment.

## M. Health

An active claim suppresses the debtor's Outstanding finding. Undo restores it where
eligible. No creditor Needs Attention is added: Phase 9 has no confirmation action to
complete. Creditor status is communicated in Activity and notifications. No Timeline row
or due date is invented. Query invalidation targets workflow/options/notifications/Health/
Overview/attention; accounting and settlement caches are not invalidated.

## N. Security / RLS

Acknowledgement table has ENABLE and FORCE RLS. Authorized reads reuse Phase 7 access;
no anonymous/public/share-token access or direct client insert/update/delete. Mutations
have narrow authenticated-only RPCs with server identity and eligibility checks under locks.
Private emitters/processors and the old payment-options implementation are not client APIs.
Deleted parents hide history; soft deletion retains rows privately. Audit stores creation
and withdrawal with IDs/timestamps, without provider metadata or amount duplication.

## O. UX

Debtors see an explicit “I've paid” action and full-amount confirmation; undo also requires
confirmation. Active claim copy is Payment sent / Awaiting confirmation. Creditors see
“[Debtor] says they've paid”; observing Organizers can read but cannot impersonate either
party. History lists server acknowledgement/withdrawal times. Member-balance context uses
the same separate status query. No Confirm received or Reject payment control exists.

A status-query failure keeps the request/amount visible with “Payment status unavailable.”
and hides payment actions. This was verified by aborting only that read request, followed
by real-server recovery; no successful backend response was mocked. AppModal now exposes
an after-close event so the nested confirmation can explicitly restore focus to its opener
(or the request card after a successful transition removes that opener).

## P. Database

Applied forward migration:
`20260930160000_reimbursement_payment_acknowledgements.sql`.
Target check, migration comparison and dry-run identified it as the sole pending migration.
After authorized develop apply: **54 local/remote histories aligned; zero pending migrations**.
Applied migrations were not edited. Production was not accessed or modified.

## Q. SQL tests

Final installed-schema regression result: **18 suites PASS, 1,011 assertion statements**.
The 17 earlier suites passed together; the final scoped Phase 9 rerun passed separately.
Evidence: `/tmp/orchestrio-phase9-final-sql.log` and `/tmp/orchestrio-phase9-sql39.log`.
New `39_reimbursement_payment_acknowledgements.sql` contains **84 assertion statements**.
Coverage: debtor/Viewer authority, isolation, exact retry, immutability, full-request and
server identity/timestamp rules, financial invariance, claim/undo/re-claim history,
notifications/events/receipts/audit, Health/link suppression, archive/pending/removed/
deleted/cancelled/stale eligibility, refund/share/settlement basis changes and retention.
Concurrent calls are additionally exercised through real develop HTTP in the browser runner.
Every SQL fixture is rolled back; the runner rejects failing TAP results and validates finish().

| Installed-schema suite | Assertion statements | Result |
| --- | ---: | --- |
| 03_financials.sql | 13 | PASS |
| 23_activity_cost_sharing.sql | 32 | PASS |
| 24_activity_execution.sql | 15 | PASS |
| 25_member_settlement.sql | 9 | PASS |
| 26_project_member_settlement.sql | 15 | PASS |
| 27_financial_completion_gating.sql | 8 | PASS |
| 29_project_completion_notifications.sql | 46 | PASS |
| 30_beta_ux_correctness.sql | 55 | PASS |
| 31_area_item_correctness.sql | 46 | PASS |
| 32_domain_events.sql | 47 | PASS |
| 33_payment_schedules.sql | 78 | PASS |
| 33_project_join_links.sql | 103 | PASS |
| 34_resource_share_links.sql | 89 | PASS |
| 35_decisions.sql | 109 | PASS |
| 36_resource_comments.sql | 87 | PASS |
| 37_reimbursements.sql | 86 | PASS |
| 38_payment_links.sql | 89 | PASS |
| 39_reimbursement_payment_acknowledgements.sql | 84 | PASS |

## R. Browser smoke

**22/22 checkpoints PASS**, including cleanup. Real local Vite app at port 5174 and actual
develop Supabase; three independent authenticated browser contexts, no simulated successful
backend responses. Final run: `2026-09-30T18:49:46.120Z`–`2026-09-30T18:50:24.586Z`.
Credential-free machine evidence: `/tmp/orchestrio-payment-acknowledgements-live-result.json`.
Reproducible runner: `scripts/payment-acknowledgements-live.test.mjs`, using the private
fixture via `PAYMENT_FIXTURE_FILE` outside the repository and `AUTH_TEST_ORIGIN` for local Vite.

| Live checkpoint | Result |
| --- | --- |
| Three independent real browser logins; develop-only network | PASS |
| Creditor Organizer and cross-project Organizer cannot acknowledge; isolation enforced | PASS |
| Outstanding debtor card without payment link responsive | PASS |
| Explicit claim confirmation modal responsive | PASS |
| Payment sent and awaiting confirmation responsive | PASS |
| Explicit no-link claim and refresh financial snapshots unchanged | PASS |
| Creditor claim copy and notification destination responsive | PASS |
| Creditor-only deduplicated notification; Activity deep link; no confirmation action | PASS |
| Undo confirmation modal responsive | PASS |
| Payment-link click does not acknowledge or contact the provider | PASS |
| Undo and restored payment options financial snapshots unchanged | PASS |
| Concurrent acknowledge/undo and old-ID retry financial snapshots unchanged | PASS |
| Concurrent retries one claim/event/notice; undo one transition; race follows serialized order | PASS |
| Status-only network failure stays local, fails closed, recovers against real backend | PASS |
| Viewer debtor browser claim; observing Organizer cannot impersonate; removed parties isolated; ledger unchanged | PASS |
| Review needed with retained payment-sent history responsive | PASS |
| Archived read-only; refund makes Review needed, retains history and suppresses actions | PASS |
| Cancelled historical claim responsive | PASS |
| Cancellation warning, retained claim, no settlement, no actionable notification | PASS |
| Full actual develop Phase9 smoke complete | PASS |
| Soft-delete and authenticated visibility cleanup | PASS |
| Soft-delete and authenticated visibility cleanup | PASS |

## S. Three-account develop verification

All three fixture accounts authenticated successfully before project setup. Runtime auth
identities were used in memory; fixture values were never printed/copied to reports or changed.
Isolated memberships were created via existing in-app invitation/acceptance APIs, with no
external email. Roles exercised: creditor Organizer, debtor Member, cross-project Organizer,
Viewer debtor, removed debtor/creditor and observing Organizer between other parties.

## T. Responsive/accessibility

PASS at **375, 430, 768 and 1280px** for Outstanding/no-link card, explicit confirmation,
Payment sent, creditor view, undo, Review needed and cancelled history. No document,
Activity Payments or modal-panel horizontal overflow. Keyboard Enter opens confirmation;
Tab remains trapped, Escape dismisses and focus returns. Dialog title/description are
associated. Notification deep link focuses the existing Reimbursements section.

## U. Phase 1–8 regressions

Phase 7 and Phase 8 SQL suites passed against the draft migration before apply.
Final installed-schema gate: **18 suites PASS** (927 earlier assertions plus 84 Phase 9).
Frontend payment URL policy: **30 cases PASS**, with no network requests.
Prior settlement mathematics, paid-source suggestions, share/refund reconciliation,
reimbursement cancellation, provider validation and owner-only payment preferences are reused.

## V. Known baseline failures

Legacy suites `21_budget_actual_cost.sql` and `22_categories_budget_ux.sql` previously failed
during membership-fixture setup (project_members RLS, SQLSTATE 42501).
Final reproduction: **both FAIL unchanged with SQLSTATE 42501, project_members RLS**,
before their feature assertions. Evidence: `/tmp/orchestrio-phase9-legacy-sql.log`.
No RLS weakening or unrelated fixture rewrite. These are the only outstanding baseline
failures; no Phase 9 verification checkpoint remains blocked.

## W. Static checks

Typecheck, build, SEO, environment policy and diff whitespace checks PASS.
Lint: **0 errors, 3 existing warnings, 0 Phase 9 warnings**. Unchanged warnings are one
`vue/no-v-html` in AppIcon.vue and two `vue/max-attributes-per-line` in CommitmentsTab.vue.
No lint rule change or higher baseline was adopted.

## X. Cleanup

PASS through normal domain APIs: temporary personal link soft-deleted, both final smoke
projects soft-deleted, all three users see no live project/Activity/request/acknowledgement/
notification data from those fixtures. All earlier stopped attempts also cleaned up their
isolated projects. Final read-only SQL verification across all **10 smoke-attempt projects**
found **0 live projects and 0 live Activities**. Auth accounts/fixture were not changed.
The local Phase 9 Vite test server was stopped after verification.

Final project IDs (synthetic resources only):
`1e9d49eb-46ba-49af-a4e8-850bb78bd765`, `ec3d0065-fd23-4555-a3f0-3e6a1faffadb`.
Primary project retained counts before → after cleanup:
5 → 5 acknowledgement rows; 14 → 14 events; 3 → 3 payments; 2 → 2 requests;
42 → 51 audit rows (cleanup adds audit). No historical records were hard-deleted.

## Y. Files changed

- New migration, SQL suite, real-browser runner and acknowledgement design/report documents.
- New acknowledgement types/service/query composable and reimbursement card/status-label components.
- ReimbursementsPanel and MemberBalances integrate the separate workflow status.
- Notification service/composable/inbox and database/domain-event types add creditor updates.
- AppModal adds the after-close focus-restoration hook.
- DOMAIN_EVENTS, REIMBURSEMENTS and PAYMENT_LINKS document the extension; `.gitignore` narrowly permits the two new documents.

## Z. Phase 10 readiness

A future creditor-confirmation object can reference the immutable active acknowledgement ID,
revalidate parties/current basis under the same locks, prevent undo after confirmation and
use the existing authoritative settlement mechanism. Reconciliation is required for stale
requests. No confirmation schema, API, button, provider call, webhook or automatic settlement
was implemented. Phase 10 has not begun. No commit, push, merge or application deploy.
