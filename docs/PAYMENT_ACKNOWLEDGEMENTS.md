# Payment acknowledgements — Phase 9

## Architecture audit before implementation

- Phase 7 `reimbursement_requests` is an immutable source/amount snapshot, open or
  cancelled. `app.reimbursement_needs_review` compares the existing Activity balance
  fingerprint; `app.can_read_reimbursement` controls Organizer/party visibility.
- Activity Reimbursements and the existing member-balance drill-down show request
  context. Phase 8 resolves current creditor links only for an authorized debtor.
- Debtor notifications/Health already link to Activity `section=reimbursements`.
  Domain facts, automation action receipts and notifications are transactional;
  private emitter/processor wrappers retain prior handlers and revoke client access.
- `record_item_settlement` and paired payments are the sole existing transfer
  accounting; they must not be invoked by an unverified debtor claim.
- Existing request creation/cancellation locks the Activity before checking project
  writability. Archive is read-only; deleted parents/removed callers lose visibility.
  Paid history, audit and events survive project soft deletion.
- No acknowledgement/receipt object exists. Generic project audit can safely retain
  acknowledgement IDs/timestamps because no URL/provider/note/amount payload is needed.

## Decision and lifecycle

Add `reimbursement_payment_acknowledgements`, separate from the stable request.
Request, project, debtor, authenticated creator and server timestamp are immutable.
An active acknowledgement has null withdrawn_at; withdrawal sets it once. One active
row per request is enforced by a partial unique index. Retry returns the same active
ID. Withdrawal targets the acknowledgement ID so a delayed retry cannot withdraw a
newer claim. Re-acknowledgement creates a new row; old timestamps/history remain.

Only the active actual debtor may act, including a Viewer debtor. Both participants
must remain active, the request must be open/current, and parents live/nonarchived.
Activity/request/member locks serialize claims, undo, cancellation and financial
changes. An acknowledgement says the full request was sent, without asserting money
arrived. No partial claims, notes, provider selection or client timestamps.

Outstanding → Payment sent / Awaiting confirmation is presentation only; the request
stays open and all financial balances remain unchanged. Undo returns Outstanding if
otherwise valid. Stale/cancelled/archive/removed-participant states reject new claims
and undo; existing records remain historical. Cancellation remains allowed under the
Phase 7 authority, with a UI warning that the debtor previously marked payment sent
and no settlement will be recorded. No automatic acknowledgement withdrawal occurs.

## Read model and privacy

A separate status read model lets acknowledgement loading/error remain local to a
request card; request details still render. Its history contains acknowledgement IDs
and timestamps only. Table/view visibility inherits Phase 7, with ENABLE/FORCE RLS,
no direct mutations, no anonymous/share-token access. No new share policy or comments.

## Events and attention

`reimbursement.payment_acknowledged` and
`reimbursement.payment_acknowledgement_withdrawn` use acknowledgement resource IDs and
minimal Activity/request IDs in payload. Each transition has one stable fact/action/
processing receipt and creditor-only notification, with no fallback or self-notice.
Inbox projections follow current authorized state; superseded claims/withdrawals
are hidden, while immutable event/audit history remains. Stale requests use review
copy rather than a current payment claim. Cancelled/deleted requests hide inbox items.

Active claims suppress the debtor's Outstanding Health finding and Phase 8 payment
options, server-side. Undo restores both where current. No creditor Needs Attention
is added because Phase 9 has no creditor action; notifications and Activity status
communicate the claim. No Timeline/due-date change. The old debtor request notification
is hidden while a claim is active so it does not keep encouraging payment.

## Accounting and Phase 10

No claim/undo operation writes payments, shares, schedules, balances, request amount/
lifecycle or settlements. Link clicks remain navigation only, and no link is required
for an explicit claim. UI says Payment sent / Awaiting confirmation, never verified
Paid/Settled. Phase 10 may attach receipt confirmation to the immutable active claim
ID, revalidate current request/participants under these same locks, prevent withdrawal
of confirmed claims, and then use the existing settlement semantics. No confirmation
schema, button, API, rejection workflow or settlement implementation is added now.
