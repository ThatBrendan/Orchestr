# Phase 8 — Member Payment Links / Provider Abstraction

Verified 30 September 2026. Develop target: **msfkczsoutbeyhjvegnw**.

**Phase 8 complete within its acceptance scope.** Implementation, three-account
browser smoke, cleanup and static gates pass.
Final installed-schema regressions pass within the Phase 8 acceptance scope,
with the two known legacy fixture failures reproduced separately. Production
was not accessed. No Git commit/push/merge, app deployment or Phase 9 work.

## A. Existing architecture audit

Global preferences live in `public.users` and `/app/settings`; project roles and
identity live in `project_members`. Generic profile audits snapshot rows, so adding
personal URLs to that table would broaden exposure. The Phase 7 read model exposes
creditor membership; a reimbursement ID provides the existing authenticated debtor
context. Existing notification, Health and balance links open Activity Reimbursements.
The pre-implementation audit is in [PAYMENT_LINKS.md](PAYMENT_LINKS.md).

## B. Data model

Separate `user_payment_links`: ID, authenticated owner, provider, URL, label,
enabled/default flags, timestamps and soft deletion. Configuration is global per
user and reused across projects. Requests never store copies of URLs. Several
links are supported, including more than one link for a provider.

## C. Provider abstraction

Static registry: Monzo (`monzo.me`), Revolut (`revolut.me`), Other (`custom`).
Named providers use exact host equality and a nonempty destination path. Custom
uses the shared HTTPS policy plus a required label. Official provider guidance was
reviewed; sources and extension contract are in PAYMENT_LINKS.md. Starling Settle Up
was evaluated but not added to the initial named registry. No guessed formats,
dynamic provider definitions, remote logos, API adapters or amount-prefill rules.

## D. URL validation

Trusted backend parsing is mandatory; frontend mirrors it for feedback. Maximum
2048 characters. Trim outer whitespace; lowercase scheme and host; preserve opaque
path/query/fragment. Reject non-HTTPS, malformed host labels, all IP literals and
numeric aliases, IPv6, userinfo, explicit ports, local/special-use suffixes,
backslashes, controls, whitespace and malformed percent escapes. Custom URLs
require ASCII public-shaped DNS names with alphabetic TLDs. Provider host checks
reject suffix and query-string spoofing.

There is no fetch, DNS lookup, HEAD request, scraping, preview or external validation
call. Format acceptance does not verify destination ownership, availability, DNS
resolution, redirects, provider-account validity or payment success. The deliberate
V1 restrictions also reject public IPs, explicit :443 ports and non-ASCII URL text.

## E. Ownership

Only the authenticated owner can save, disable, remove or choose a default. Mutation
RPCs derive `auth.uid()` and accept no owner parameter. Organizer/Member/Viewer roles
do not grant authority over another person's configuration. Direct client writes
and service-role table mutations/RPC execution are revoked.

## F. Visibility

Owner lists only their own undeleted records. No arbitrary-user link lookup exists.
`get_reimbursement_payment_options(request_id)` checks live Phase 7 access, active
participants, current open request, debtor identity and nonarchived project before
returning enabled creditor links. Legitimate Viewer debtors are allowed. Organizer
request visibility alone does not expose a different creditor's payment URLs.

## G. Default provider

Zero or one enabled, undeleted default per user. Owner-row locking serializes writes;
a partial unique index protects the invariant. Switching clears the prior default
atomically. Disabling/removing it leaves no default; no alternative is promoted.
A debtor sees the default first, then stable creation/ID order. Real concurrent
set-default HTTP calls completed with exactly one final default.

## H. Reimbursement integration

A small independently loaded Pay section inside the existing Activity Reimbursements
panel shows the creditor's current enabled links. Settings edits appear on the next
fresh debtor read without changing the request. No new route or top-level section.
Existing Phase 7 notification/Health destinations remain unchanged. Settings writes
invalidate personal-link/payment-option queries only, not project finance caches.

## I. Review-needed / cancelled behavior

The UI hides Pay for Review needed, cancelled or archived requests; the server also
returns no options. Review copy asks for reconciliation before payment. Removed
creditor/debtor and deleted parent contexts cannot resolve links. Personal settings
remain manageable independently of the project/request lifecycle.

## J. Accounting isolation

Exact real-backend snapshots compare project financials, Activity member settlements,
legacy member balances, schedules, payments, cost shares and reimbursement requests.
Adding/editing/defaulting/disabling/removing configuration changes none of them.
External navigation additionally preserves Health and notification state. The
reimbursement remains Outstanding and no payment or settlement row is inserted.

## K. Settlement compatibility

Existing `record_item_settlement`, transfer guards, pair ledger and all financial
views are untouched. No link-click handler invokes a financial mutation. Phase 8
adds no payment-started, paid, confirmed or other reimbursement lifecycle state.

## L. Privacy

URLs are present only in owner configuration and authorized debtor option responses.
They are absent from profile/member-directory models, notification bodies, Health,
domain-event payloads, project exports and audit snapshots. The dedicated audit
trigger omits both URL and free-text label, retaining record/owner/provider and
lifecycle/default metadata. Existing project CSV export inputs remain unchanged.

Option queries are keyed by user and reimbursement, use no persistence, refresh on
focus/30-second intervals and are garbage-collected when inactive. Previously
delivered URLs cannot be made unknown to a former recipient; subsequent authorized
reads enforce current access/configuration. External anchors use no-referrer policy.

## M. Events / analytics

No Phase 8 domain events or analytics were added. There is no identified automation
consumer. `DOMAIN_EVENTS.md` and the event registry remain unchanged. Configuration
metadata audit is sufficient; no payment URL or click is an authoritative fact.

## N. RLS / security

ENABLE and FORCE RLS. Owner-only direct SELECT on undeleted records; no direct
INSERT/UPDATE/DELETE. Trusted functions use an empty search path and explicit owner
or request checks. Anonymous execution is denied. Unknown/inaccessible reimbursement
IDs return an empty set without identity enumeration. URL validation also runs in a
table trigger, and immutable owner/ID/creation time are guarded.

## O. UX

Settings has a compact Payment links section, labelled provider selector, URL field,
custom label, enabled checkbox, edit/remove and one-click default controls. Removal
has a simple confirmation. Named-provider help explains where to obtain a personal
link. No provider account verification is claimed. Browser coverage includes saved
state after refresh, changing provider/URL, validation errors and removing a
non-default link.

## P. Provider-less fallback

The debtor sees that no payment link is available for this reimbursement. The request
remains usable and Outstanding. This neutral wording also covers a creditor whose
membership no longer permits sharing. Query failure shows “Payment link unavailable”
with retry, independently of the Activity financial detail.

## Q. Database

Applied to develop: `20260930120000_user_payment_links.sql`.
Before apply, target check and migration list were verified; dry run showed only this
migration. Existing applied migrations were not edited. Final migration list confirms
**53 local/remote migrations aligned**, latest `20260930120000`. Final dry run
reports up to date with zero pending migrations, seeds or roles.
Production untouched; no application deployment.

## R. SQL tests

New `supabase/tests/38_payment_links.sql`: **89 assertion statements**. Draft rollback
run passed together with the unchanged Phase 7 suite. Coverage includes owner/RLS,
spoofed URLs and local targets, atomic default behavior, debtor/Viewer/Organizer
isolation, active-member checks, pending requesters, archived/stale/cancelled/deleted
contexts, metadata audit privacy, financial invariance and soft-deleted history.

Final installed-schema run: **17 suites PASS, 927 assertion statements**. Two
legacy fixture suites failed as documented in section W. The SQL runner rejects failing TAP assertions
and checks finish(); every fixture is rolled back. Frontend URL-policy suite:
**30 cases PASS**, no network calls (`scripts/payment-links.test.mjs`).


| Installed-schema suite | Assertions | Result |
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
| 38 Payment links | 89 | PASS |

Counts are assertion statements in passing source files. Credential-free runner
output: /tmp/phase8-final-sql.log. Phase 7 covers suggestions, multiple payers,
no self-request, refund/share-change review, cancellation, debtor notifications,
Health, scoped visibility, financial invariance and project cleanup.

## S. Browser verification

**PASS — 15 recorded checkpoints**, including both project cleanup checkpoints.
Actual run: **2026-09-30T12:41:33.635Z–12:41:56.207Z**.
Runner: `scripts/payment-links-live.test.mjs`.
Credential-free evidence: `/tmp/orchestrio-payment-links-live-result.json`.

Settings: add Monzo/Revolut/custom; default; refresh; invalid host feedback; valid
edit; long URL; remove non-default; persistence; concurrent default calls. Debtor:
notification destination, default-first options, keyboard external action,
no-link fallback, live configuration changes, Review needed and cancellation.
Actual HTTP verifies unsafe URLs and ownership denial as well as UI affordances.

## T. Three-account develop smoke

All three existing private synthetic accounts authenticated in independent browser
contexts. Fixture credentials were not printed, copied into reports or committed.
Memberships came from normal in-app invitation/acceptance APIs; no external emails.

Organizer/creditor and Member/debtor exercised the primary request. Third account
first proved outsider isolation, then became debtor to a Member creditor. Organizer
could inspect that request but could not resolve or edit the Member's payment URL.
A legitimate Viewer debtor retained scoped link access. HTTP/browser responses came
from the real develop backend; no Supabase responses were mocked.

External navigation was intercepted and aborted **before transmission**. A keyboard
Enter opened a new tab with null opener; noreferrer/noopener/target attributes were
checked. No provider page was fetched, no provider login/form was used and no money
was sent. Financial/Health/notification snapshots were identical after navigation.

## U. Responsive / accessibility

**PASS:** 375, 430, 768 and 1280 pixels with no horizontal overflow, covering Settings
list, add/edit provider selector, long URLs, default indicator, Pay section/action,
no-link fallback and Review-needed state. Provider/URL/custom-label controls have
explicit labels; errors are associated with fields using aria-describedby and
aria-invalid. Native buttons/selects support keyboard use. External links announce
a new tab, have meaningful provider-specific accessible names and were exercised
with keyboard focus/Enter. No remote images or icon-only unlabeled actions.

## V. Regression result

Final installed-schema Phase 1–7 and financial regressions **PASS**. Phase 7 read models,
mutation RPCs, accounting, event rules and notifications were not changed. Only the
Activity panel includes the new independently loaded debtor payment options.

## W. Known baseline failures

The final run reproduced `21_budget_actual_cost.sql` and
`22_categories_budget_ux.sql` failing during membership-fixture setup with
SQLSTATE 42501, project_members RLS, unchanged from the documented baseline.
Overall invocation: **17/19 files passed**; the full legacy suite is not claimed
green. No RLS, test expectation or legacy fixture was weakened.

## X. Static checks

| Check | Result |
| --- | --- |
| Typecheck | PASS |
| Lint | PASS: 0 errors, 3 existing warnings, 0 Phase 8 warnings |
| Build | PASS |
| SEO | PASS |
| Environment policy | PASS |
| Frontend URL validation | PASS: 30 cases |
| git diff --check | PASS |

Existing lint warnings: AppIcon.vue `vue/no-v-html` once; CommitmentsTab.vue
`vue/max-attributes-per-line` twice. No lint configuration or dependency changes.

## Y. Cleanup

Normal owner APIs removed all test payment links; both tested owners' live lists
are empty. Normal `soft_delete_project` removed:

- Main: `44a8b524-95ca-4c17-bb3a-75f41a4b25af`
- Isolation: `71650e3e-65ce-4803-890b-630b1cf19c13`

All three sessions verify no visible projects/Activities, active undeleted
memberships or reimbursements. History before → after: requests 2 → 2, payments
3 → 3, domain events 5 → 5, project audit 33 → 42 (normal cleanup audit). Synthetic
auth accounts remain. Soft-deleted preference rows retain private history; URL/label
copies are not retained in audit. A separate database check confirms zero live
test links and five soft-deleted preference records. A separate project-table
check confirms both projects are deleted, with zero live Activities, active
undeleted memberships or payments and two retained historical requests.
SQL fixtures rolled back.

## Z. Phase 9 readiness

The request ID and live payment-options endpoint can support a later explicit debtor
acknowledgement. A click provides no evidence of payment; future acknowledgement and
creditor confirmation need their own authorization and history, then must use the
existing settlement mechanism. No acknowledgement state/schema, provider API,
webhook, bank/card storage, public payment page or Phase 9 implementation was added.

Implementation files: migration/test above; payment-link types, static registry,
service/composable, Settings component, debtor options component; small Settings,
reimbursement-panel and Database type additions; browser/URL-policy runners and
[PAYMENT_LINKS.md](PAYMENT_LINKS.md). Narrow .gitignore exceptions include the docs.
