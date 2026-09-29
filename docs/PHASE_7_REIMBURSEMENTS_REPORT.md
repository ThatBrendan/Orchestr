# Phase 7 — Reimbursements verification report

Date: 29 September 2026. Develop: **msfkczsoutbeyhjvegnw**.

**Phase 7 complete within its acceptance scope.** Implementation and live browser
verification are complete. Final installed-schema
regressions passed within the Phase 7 acceptance scope, with two known legacy
fixture failures reproduced separately. Production was
not accessed. No Git commit/push/merge, app deployment, external email or Phase 8 work.

## A. Existing financial architecture

`v_activity_cost_shares` computes responsibility and rounding. The existing
`v_activity_member_settlements` supplies each member's allocated, net paid and
remaining amounts. `record_item_settlement` bounds transfers by positive debtor
remaining and negative creditor remaining, recording paired ledger movements.
Project/member views and financial completion rules remain authoritative.
There is no existing canonical debtor-to-creditor pair graph. The audit and
selected design are in [REIMBURSEMENTS.md](REIMBURSEMENTS.md).

## B. Reimbursement model

`reimbursement_requests` persists only explicitly initiated workflow snapshots.
Balances remain derived. The model is project-, Activity- and paid-payment-bound,
with immutable parties/amount/source and an open/cancelled lifecycle.

## C. Cost share relationship

A cost share assigns ultimate responsibility. A reimbursement request records an
explicit claim against an existing positive/negative settlement position. Creating
or cancelling a request never changes cost shares or member balance arithmetic.

## D. Source payment

Only an attributed, outgoing, paid, non-settlement Activity payment is eligible.
The server derives creditor, Activity and project from that payment. Planned
payments, refunds and settlement transfers are rejected as sources. The UI shows
source amount, payer and payment date alongside the request.

## E. Amount derivation

Suggestions read the existing settlement view; they do not recalculate shares or
net payments. The same debtor/creditor bounds as the existing transfer API apply,
less open workflow reservations across all payment sources in the Activity. Gross
source amount is an additional cap. Deterministic member ordering distributes the
available suggestion budget; it is a selection rule, not another accounting engine.

Live single-payer example: £900 paid, three £300 responsibilities, two £300
requests. Live multiple-payer example: Organizer £600, Member £300, three £300
responsibilities; the sole suggestion matches the existing £300 creditor/debtor
bounds. A payer who covered only their own share gets no suggestion. Partial
payments and incoming refunds are tested against current authoritative credit.

## F. No self-obligation

Enforced by table constraint, RPC member checks and suggestion exclusion. Positive
amount, active same-project debtor and creditor, source eligibility and capacity
are server-validated. Frontend input is not trusted.

## G. Lifecycle

Only open and cancelled. Exact active-source/member retries return the same ID;
a conflicting amount requires cancellation/recreation. Cancellation is repeat-safe.
No settled state, payment confirmation or speculative transfer linkage is added.
Future settlement must attach to the existing paired-transfer semantics.

## H. Immutability

Amount, source, project, Activity, debtor and creditor cannot be edited. Direct
client insert/update/delete is revoked; a trigger protects immutable core fields
and history even under a trusted table update. Cancellation retains all records.

## I. Refund behavior

Snapshots fingerprint the existing Activity settlement rows. A later refund that
changes those balances marks an open request Review needed, retains its original
amount and suppresses the stale owed claim in Health. Notification copy changes to
review. New suggestions are blocked until stale requests are cancelled/recreated.
The live £100 refund reduced current request capacity from £600 to £500.

## J. Cost-share edits

Share edits and existing settlement transfers remain available. Their balance
changes similarly require explicit request reconciliation. No historical request
amount is silently rewritten, and existing settlement records are not reinterpreted
as a request confirmation. SQL verifies both share-change and transfer behavior.

## K. Financial integrity

Live snapshots before and after request creation/cancellation are identical for
project financials, Activity settlement balances, legacy member balances, cost
shares, payment-schedule financials and payments. The £600 workflow does not add
to £900 spend. SQL additionally checks an existing nonzero schedule is unchanged.

## L. Member balance reconciliation

The existing balance drill-down now links to individual Activity requests. It
adds contextual rows, not new aggregate debt totals. Read access remains scoped
to the caller. Original request amounts are labelled when review is required.

## M. UX

Compact Reimbursements section inside Activity Payments. Select an eligible paid
payment, review server-derived members/amounts, choose recipients and create.
Perspective-aware You owe / owes you copy, source provenance, Outstanding,
Cancelled and Review needed states. Authorized cancellation has inline confirmation.
No top-level tab or second financial dashboard. Focused notification/balance links
use the existing Activity route with `section=reimbursements`.

## N. Notifications

One in-app notification to the active debtor for each creation. No creditor or
project-wide fan-out; cancelled/deleted resources disappear from the inbox.
Opening marks read and opens the correct Activity section. No external email.
Live evidence: four creations, four notifications, one per corresponding debtor.

## O. Health

Valid open requests give the debtor an Outstanding finding. No overdue/due-soon
language, invented due date, Timeline entry or project Health-score penalty.
Creditor/Organizer does not get a duplicate personal alert. Cancellation and stale
balance snapshots remove the owed finding. Overview and Health route into the
Activity section; member names are preserved without status-word normalization.

## P. Domain events

`reimbursement.created` and `reimbursement.cancelled`, with payload containing
only Activity/payment IDs. Actor and source are server-validated. Stable keys,
immutable processing receipts and deduplicated actions use the existing pipeline.
Existing handlers are delegated unchanged. Cancellation emits no notification.
The final live run recorded four creation and three cancellation facts, each with
one processing receipt; only creations have an action and notification.

## Q. RLS and security

ENABLE/FORCE RLS. Active Organizer reads project requests; Member/Viewer reads
only requests where they are a party. Organizer or authoritative payer Member
may create/cancel; Viewer cannot mutate. Anonymous, pending requester, removed
member, unrelated Member and cross-project Organizer cannot gain request access.
Deleted parents hide requests; archived projects are read-only. No share-link
resource policy or reimbursement comments are registered.

## R. Database

Develop applied:

- `20260928150000_settlement_project_cleanup.sql`
- `20260928160000_reimbursement_requests.sql`

Target check, migration list and dry run showed exactly these two pending files
before apply. The cleanup migration fixes an existing project-cascade failure for
settlement pairs without altering settlement mathematics, identity or amounts.
Post-apply history alignment: **PASS**, all 52 local/remote migrations align
through `20260928160000`. Final `supabase db push --dry-run`: up to date,
zero pending migrations, seeds or roles. Production untouched.

## S. Test evidence

| Check | Result / evidence |
| --- | --- |
| Create / single payer | PASS SQL and real browser: £900, 2 × £300 requests |
| Multiple payer | PASS SQL and browser, compared with existing settlement view |
| No self-request / positive amounts / caps | PASS SQL and real suggestions |
| Duplicate prevention | PASS SQL and concurrent real HTTP exact retries |
| Immutable core fields | PASS SQL, direct mutation denied |
| Refund interaction | PASS SQL and browser; explicit review/cancellation |
| Cost-share changes / existing settlements | PASS SQL, snapshots retained |
| Cancellation | PASS Organizer and payer Member browser flows; SQL repeat-safe |
| No double counting / balance reconciliation | PASS exact before/after financial snapshots |
| Authorization / cross-project isolation | PASS SQL and real outsider/Member/Viewer sessions |
| Notifications / Health | PASS SQL and real debtor browsers; correct targeting/deep links |
| Phase 1–6 and financial regressions | PASS: 15 existing suites plus Phase 7; 838 assertion statements total |
| Real develop browser E2E | PASS, 22 recorded checkpoints including cleanup |
| Responsive | PASS 375, 430, 768, 1280; no horizontal overflow |
| Typecheck | PASS |
| Lint | PASS: 0 errors, 3 existing warnings, 0 Phase 7 warnings |
| Build | PASS |
| SEO | PASS |
| Environment policy | PASS |
| `git diff --check` | PASS |

Final live run: **2026-09-29T18:54:30.167Z–18:54:56.824Z**.
Runner: `scripts/reimbursements-live.test.mjs`.
Credential-free result: `/tmp/orchestrio-reimbursements-live-result.json`.
All three private accounts authenticated before the smoke. Credentials were not
printed, committed or copied into this report. Browser traffic was restricted to
local Vite and the specified actual develop backend; no mocked server responses.

Responsive checks cover suggestion selection, amounts, creditor/debtor lists,
source provenance, notification destination, Needs Attention, member drill-down
and cancellation confirmation. Earlier attempts found an ambiguous hidden-element
selector and an insufficiently explicit select label; both are corrected. Their
isolated projects were also cleaned up before the successful final run.

### Cleanup

Normal `soft_delete_project` API used for both final isolated projects:

- Main: `f63902be-bbb9-4649-a6cf-65cbbe4a8628`
- Isolation: `9b3d65b9-979e-4ae5-915a-142aabde90a5`

All three sessions verify no visible live projects, Activities, active nondeleted
memberships or reimbursements. Historical counts before → after: requests 4 → 4,
payments 6 → 6, domain events 10 → 10, audit 43 → 56. Audit grows from normal
cleanup. Auth accounts are retained. SQL fixtures are rolled back.

A separate read-only database check covered all six project IDs from the three
smoke attempts: every project has deleted_at set, and every project has zero live
Activities, active nondeleted memberships and live payments. Historical request
counts remain 2, 2 and 4 in the three main smoke projects (zero in isolation projects).


### Final installed-schema SQL run

All fixtures transactionally rolled back. The runner fails on any failed TAP
assertion and checks finish(). Counts are assertion statements in the source.

| Suite | Assertions | Result |
| --- | ---: | --- |
| 03 Financials | 13 | PASS |
| 23 Cost sharing | 32 | PASS |
| 24 Activity execution | 15 | PASS |
| 25 Member settlement | 9 | PASS |
| 26 Project settlement | 15 | PASS |
| 27 Financial completion gating | 8 | PASS |
| 29 Completion / notifications | 46 | PASS |
| 30 Beta UX correctness | 55 | PASS |
| 31 Area/item correctness | 46 | PASS |
| 32 Domain events | 47 | PASS |
| 33 Join links | 103 | PASS |
| 33 Payment schedules | 78 | PASS |
| 34 Share links | 89 | PASS |
| 35 Decisions | 109 | PASS |
| 36 Comments | 87 | PASS |
| 37 Reimbursements | 86 | PASS |
| 21 Budget actual cost | Setup failed | Known FAIL: membership RLS |
| 22 Categories / budget UX | Setup failed | Known FAIL: membership RLS |

Reimbursement tests include deferred settlement-pair constraints forced immediate
after project deletion, history retention, pending/removed/Viewer access, actual
source restrictions, refunds, share edits, transfer compatibility, immutability,
notification/event receipts, archive behavior and financial snapshot comparisons.

## T. Known baseline failures and lint classification

The final installed-schema run reproduced FAIL for `21_budget_actual_cost.sql`
and `22_categories_budget_ux.sql` in membership-fixture setup (project_members
RLS, SQLSTATE 42501), exactly as documented before Phase 7. No test or protection
was weakened. Overall invocation: 16/18 files passed; the full legacy suite is
not claimed green.

Lint is 3 warnings: AppIcon.vue `vue/no-v-html` once and CommitmentsTab.vue
`vue/max-attributes-per-line` twice. No generated-type warnings and no new Phase 7
warnings. Lint rules/configuration and dependency files are unchanged. The old
unreproduced 41-warning output is not adopted as a baseline.

## U. Documentation

[REIMBURSEMENTS.md](REIMBURSEMENTS.md): audit, accounting distinction, source and
capacity rules, permissions, reconciliation, cleanup and future extension point.
[DOMAIN_EVENTS.md](DOMAIN_EVENTS.md): Phase 7 facts/actions/notification contract.
This report records implementation and actual verification evidence.

## V. Files changed

- Two forward migrations and `supabase/tests/37_reimbursements.sql`.
- `scripts/reimbursements-live.test.mjs`.
- Reimbursement types, service, query composable and Activity panel.
- Database/event contracts, payment panel, member balance drill-down, notification
  service/composable/dialog, Health/Overview links and labels, query invalidation.
- Reimbursement/Phase 7/domain-event documentation and narrow `.gitignore`
  exceptions so these reports can be reviewed with the source.

## W. Phase 8 readiness

A stable authenticated request ID can later carry member-configured payment-link
metadata/provider selection without affecting accounting. A future settlement
relationship must use the existing transfer ledger and reversal-aware rules.
No provider, payment profile, bank details, public request link, “I've paid”,
recipient confirmation, automatic settlement or Phase 8 implementation is included.
