# Payment links — Phase 8

## Architecture audit (before schema implementation)

1. Global preferences live in `public.users`, the auth-profile mirror (name, timezone,
   currency, notifications), managed at `/app/settings` by SettingsView/useMyProfile.
   Profile updates have generic full-row audit snapshots.
2. Project identity/roles live in `project_members`; project settings are separate.
   Organizer authority is project-bound and must not grant personal-link management.
3. Use a separate user-owned `user_payment_links` table: reuse one configuration
   across projects, support several providers, avoid expanding broad profile views.
4. Phase 7 exposes creditor_member_id through `v_reimbursements`; project membership
   maps this to the creditor user. Its immutable requests remain untouched.
5. Debtor reaches Activity Payments/Reimbursements from notifications, Health and
   existing balance links. Viewer parties already have scoped request read access.
6. A reimbursement-ID RPC needs only the live creditor's enabled provider/label/URL,
   default flag and link ID. No arbitrary user-ID lookup endpoint is needed.
7. URLs/labels are private personal routing preferences. Keep them out of public
   users, member directory, exports, Health, notifications, domain facts and audit.

There is no payment provider integration or reusable external payment-URL validator.
Existing URL helpers concern auth redirects, environment targets and analytics.
Share-link Vault encryption protects bearer sharing tokens; payment preferences are
not bearer access tokens. Use narrow RLS/RPCs, not a new encryption/key subsystem.
Project CSV exports read explicit Activity/Category/member models, not these links.
The existing settlement API and all financial views remain unchanged.

## Chosen contract

Several links per user; optional one enabled, undeleted default. Owner mutations
serialize on their user row; a partial unique index enforces the default invariant.
Disabling/removing the default clears it without promoting another. Soft deletion
retains metadata history. Reimbursements use current configuration, never URL copies.

Owner-only direct read, RPC-only writes. Authenticated debtor options require live
Phase 7 access, open/current request, nonarchived project and active debtor/creditor
memberships. Viewer debtors are allowed; Organizer privilege alone is insufficient.
Archived requests remain readable under Phase 7 but Phase 8 offers no payment action.
Removed/deleted parents or participants, cancelled requests and changed balance
snapshots return no options. Global owner settings still work independently.

URL validation parses a deliberately restricted HTTPS URI grammar on the server,
with matching frontend feedback. Maximum 2048 characters, ASCII URI syntax, valid
percent escapes, DNS host labels and an alphabetic TLD. No userinfo, explicit ports,
IP literals (including public IPs), numeric/hex IPv4 aliases, IPv6, local/special-use
suffixes, backslashes, controls or embedded whitespace. Scheme/host are lowercased;
outer whitespace is trimmed. Path/query/fragment semantics are preserved. No amount
prefill, URL fetching, DNS resolution, metadata previews or provider API calls.
DNS names can resolve or redirect elsewhere: format checks do not verify ownership,
reachability, provider account existence, DNS destinations or payment success.

## Static provider registry

| Key | Label | Accepted hosts | Validation / guidance |
| --- | --- | --- | --- |
| monzo | Monzo | exactly monzo.me | HTTPS, nonempty destination path; paste personal Monzo.me link |
| revolut | Revolut | exactly revolut.me | HTTPS, nonempty destination path; paste generic Revolut.me link |
| custom | Other | public-shaped DNS name under the common parser policy | HTTPS; custom label required, maximum 60 characters |

Reviewed 30 September 2026 against [Monzo help](https://monzo.com/help/monzo-with-friends/monzo-me-how-to)
and [Revolut help](https://help.revolut.com/help/adding-money/with-money-from-friends-or-relatives/requesting-money/).
These sources confirm the named payment-link domains; no provider API or amount
parameter contract is assumed. [Starling Settle Up](https://www.starlingbank.com/features/settle-up/)
exists but is not a named adapter in this minimal release. No guessed Starling URL
format is enabled. Named-host equality is never substring matching.

To add a provider: review official documentation, define a static key/name/host and
help text, extend trusted server validation and frontend registry together, add URL
spoofing/normalization tests, then a forward migration. Never add dynamic regex/code
in the database. Store only routing preferences, never bank/card data or provider
credentials. Unknown provider keys fail closed.

## Privacy, accounting and future work

A dedicated audit trigger records only link ID, owner ID, provider, enabled/default
state and deletion metadata. It omits URL and free-text label. No domain events or
click analytics are added. External navigation is a plain HTTPS anchor with
`target=_blank`, `rel=noopener noreferrer` and no mutation handler. It cannot create
payments, settle requests, clear Health or complete a notification. Notification
read behavior remains the existing independent Phase 7 navigation behavior.

Options load separately; failure does not block Activity details. Owner writes
invalidate only personal-link and payment-option queries. Options refresh on focus
and periodically, and are cleared from cache when their component unmounts; they
are not persisted. A future debtor acknowledgement must be an explicit audited
workflow, independent of link clicks, before any later creditor confirmation and
existing settlement transfer. Phase 9/10, public sharing and payment initiation
are not part of Phase 8.

## Phase 9 integration

An active debtor acknowledgement now suppresses both the normal payment CTA and the
server `get_reimbursement_payment_options` response, preventing encouragement to pay
twice. The renamed prior implementation has no client execution grant. Explicit undo
restores options only when the request is otherwise current, open and accessible.
Opening an external link still performs no mutation and is never evidence of payment.
See [Payment acknowledgements](PAYMENT_ACKNOWLEDGEMENTS.md).
