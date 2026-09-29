# Reimbursements — Phase 7 design

## Financial audit and decision

1. Responsibility: `v_activity_cost_shares` is authoritative over `cost_shares` / participants and the Activity cost. It handles fixed/equal/weighted shares and integer rounding; Phase 7 does none of that arithmetic.
2. Balances: `v_activity_member_settlements` derives allocated, net paid (outgoing minus incoming), and remaining amounts per Activity/member. `v_project_member_settlements`, `v_item_member_balances` and `v_member_balances` retain their existing scopes and semantics.
3. Transfers: `record_item_settlement` locks the Activity and bounds the transfer by the debtor's positive remaining amount and creditor's negative remaining amount. Two matching `payments` rows share a settlement group. These adjust member balances but not supplier/project spend. There is no persisted or derived canonical pair graph to replace.
4. Attribution: `payments.paid_by_member_id` is the authoritative payer. Member writes are limited to their own attribution; Organizer can attribute another member. Refunds are incoming paid entries. Internal settlement rows cannot be reimbursement sources.
5. Reimbursements are implicit in positive/negative Activity member balances and the existing Balance drill-down. There is no existing explicit request lifecycle.
6. Missing: source-bound immutable request snapshots, controlled creation/cancellation, debtor-only notification and contextual UI. These are added without a second balance calculator.

## Persisted request over derived finance

`reimbursement_requests` persists only explicitly initiated workflows. Its source is an actual outgoing paid, attributed, non-settlement Activity payment. Project, Activity and creditor are derived on the server. Member creation is restricted to that payer; Organizers may act on their behalf; Viewers cannot mutate.

Suggestions consume the existing `v_activity_member_settlements` balances using the same debtor-positive / creditor-negative limits as `record_item_settlement`. Existing open requests reserve workflow capacity only, across all sources in the Activity; these reservations never enter any financial view. Source-payment amount is a further upper bound. A deterministic member-ID order distributes the available suggestion budget among eligible debtors; it is a selection policy, not a recalculation of responsibility or a new pair ledger. No split means no positive debtor balance and therefore no meaningful suggestion. Multiple payers work through their existing net credits, not gross payments divided by headcount.

Core IDs and amount are immutable. Lifecycle is `open` / `cancelled`; cancellation preserves source payment, cost shares, balances and history. Duplicate active source/debtor requests are unique. Exact retry returns the existing row; a conflicting amount is rejected. Activity locks serialize request creation with payment/share/settlement writes.

## Refunds, share changes and existing settlements

The request stores a fingerprint of the authoritative Activity balance rows at creation. Any later change to that financial basis makes an open request **Review needed**. It is then displayed as an original request, not a current assertion that this amount is owed; debtor attention and actionable notification copy are suppressed/replaced with review copy. Creation is blocked until stale open requests are explicitly cancelled and recreated against current suggestions. No refund/share edit/settlement is blocked, no snapshot is silently rewritten, and no paid history is changed.

This deliberately conservative reconciliation policy also applies to existing settlement API calls: they continue unchanged, and a resulting basis change requires request reconciliation. Phase 7 does not automatically claim a request was settled or introduce settlement confirmation. A later explicit request-to-settlement-group link must use the existing transfer RPC and enforce reversal-aware cancellation; no speculative transfer ledger is added now.

Cancelled Activities keep meaningful paid-source requests where the existing balance basis still supports them; no automatic request cancellation occurs. Archived projects remain readable to authorized readers and immutable. Deleted parents hide requests while preserving historical rows/events/audit. Removed members lose project access; historical request relationships remain.

## Access and extensions

RLS is enabled and forced. Reads require live project/Activity/source and active project membership: Organizer reads all; other members (including Viewers) read only requests where they are debtor or creditor. This is narrower than existing general balance visibility. Direct client mutations are denied; trusted RPCs validate actor, source, participants and capacity.

Creation emits `reimbursement.created` with only parent Activity/payment IDs; one debtor notification is produced transactionally. Cancellation emits `reimbursement.cancelled` without a notification. No personal profile or amount payload is needed. Notifications link to Activity Payments/Reimbursements. Valid open requests produce a debtor-only Outstanding attention finding, with no invented due date or Timeline row. No reimbursement share-link policy or comment resource is registered.

Payment links can later attach to the authenticated request resource without changing any accounting. Public links, providers, bank details, “I've paid”, receipt confirmation and Phase 8 are deferred.

## Project cleanup compatibility

During Phase 7 testing, normal project deletion exposed an existing settlement-pair
cleanup defect: the cascade hides memberships before payment guards run. The forward
migration `20260928150000_settlement_project_cleanup.sql` permits only the nested
project cascade's deletion-lifecycle changes. Settlement identity, amounts, direction,
attribution and dates remain protected. The deferred pair guard accepts two equally
soft-deleted matching rows only under a deleted project; it still rejects malformed,
asymmetric or live-project-deleted pairs. The SQL suite forces deferred constraints
immediate after cleanup. No settlement calculation or transfer API is replaced.

## Verification and reproduction

The installed-schema tests are `supabase/tests/37_reimbursements.sql`. The real
three-account HTTP/browser runner is `scripts/reimbursements-live.test.mjs`.
It requires `PAYMENT_FIXTURE_FILE` pointing to the private synthetic-account file
outside the repository and a local Vite app configured for develop. It authenticates
all three existing accounts, derives runtime identities from authentication, allows
only local/develop browser network requests, creates isolated project memberships via
in-app invitations, and always attempts normal domain cleanup. No external email is
sent. Result output excludes fixture values; credentials must never be copied into
reports or committed. See [Phase 7 report](PHASE_7_REIMBURSEMENTS_REPORT.md) for the
actual run evidence and known unrelated baseline failures.
