# Domain events and system automation

Phase 1 uses PostgreSQL triggers and private `app` tables. Domain writes, event facts,
rule dispatch, existing in-app notifications, and processing receipts share one transaction.
The original Phase 1 introduced no frontend changes, historical backfill or worker. The Phase 2
and Phase 4 extensions below add their authoritative domain operations and a narrow Decision scheduler.

## Repository findings and decision

Activities are `public.commitments`; Categories are `public.project_areas`. Creation uses
`create_activity_in_category` → `save_activity_with_split`; status changes also use direct
RLS-protected updates and trusted completion RPCs. AFTER triggers cover all these paths.
BEFORE triggers validate status transitions, project writability, ownership and financial
settlement. Occurrences have separate completion RPCs and are not parent completion events.

Existing implicit events include audit rows, Activity-created notification inserts,
project activation/cancellation cascades, invitation acceptance/membership updates, and
frontend product analytics. Analytics is not authoritative. Payment and member settlement
RPCs already own their financial transitions; this phase does not alter or emit from them.
Audit captures row changes. The invitation Edge Function sends invitation emails through
its existing flow. Health/deadline findings are computed by SQL read models; there is no
implemented general scheduled event worker. Older architecture documents describe future
notification cron functions, not deployed Phase 1 infrastructure.

Activity-created fan-out was coupled directly to the insert trigger. It is now a system
rule action. Domain integrity cascades and financial guards remain domain logic; audit and
invitation delivery remain unchanged. A database pipeline fits the existing transactional
backend and covers direct updates as well as RPCs without trusting browser events.

## Tables and lifecycle

All five tables live in `app`, outside the exposed PostgREST schemas:

- `domain_event_types`: registered name and resource type. Initially only activity.created/completed.
- `domain_events`: immutable UUID fact, type, project/actor/resource IDs, minimal category payload,
  creation time, and deduplication key.
- `automation_rules`: system-owned enabled flag, event type, priority, known condition/action
  handlers and validated configuration (only empty configuration is needed currently).
- `automation_action_runs`: immutable successful event/rule receipt.
- `domain_event_processing`: immutable event completion receipt, including events with no matching rules.

Lifecycle: validated domain write → `tg_activity_domain_events` → `emit_domain_event` →
persist fact → `process_domain_event` → enabled matching rules in priority/ID order →
known condition → known action → receipts. `activity_live` checks the Activity still exists
and is not soft-deleted; `always` is also supported. There is no dynamic SQL rule language.
Failed actions roll back the whole domain operation. This preserves existing notification
atomicity but means a broken enabled action can block writes; keep external I/O out of this path.

The dispatcher locks an event to serialize retries. Processing receipts make replay a no-op,
including after rule configuration changes. Changing a rule does not retroactively deliver
old events. Skipped/disabled rules have no action receipt, while the event is still processed.

## Emission and idempotency

`app.emit_domain_event(type, project, resource, payload, key)` is internal only. It validates
supported handlers, a live Activity's project relationship, completion state, and an exact
minimal `{category_id}` payload. Actor is derived from `auth.uid()`; for system-created rows,
the existing creator-member fallback is retained. Callers cannot pass an actor.

Creation uses the stable resource ID plus `created`. Updates to an existing row and retries
of the emitter do not recreate the event. A failed insert or later RPC failure rolls back the
fact and notification. This does not deduplicate two separate create requests that generate
two separate Activity IDs; request-level create idempotency is an existing API limitation.

Completion emits only on an UPDATE transition into completed, after financial guards pass.
Repeated saves do nothing. Reopening and completing again is a distinct fact with the next
per-resource completion number; the domain row lock serializes concurrent transitions.
Initial inserts already marked completed emit only created, not a fabricated transition.
Recurring occurrence completion is deliberately not conflated with completing its parent.
No soft-deleted Activity emits events.

Uniqueness on event type/resource/key protects facts; event/rule uniqueness protects action
receipts; the existing recipient/Activity/kind uniqueness protects notifications. A conflicting
retry with different project or payload is rejected. Facts retain identifiers without cascading
foreign keys to mutable domain records; trusted emission validates those references while
records exist. Hard deletion cannot rewrite historical facts.

## Notification compatibility and audit

The old Activity-created trigger/function is atomically replaced by the event trigger and
`activity_created_collaborators` rule. The action preserves active, non-deleted, signed-in
project members, excludes the creator, and retains the exact notification uniqueness key.
Inbox tables, views, read state, RLS and deep links are unchanged. There is one delivery path.

Audit means who changed what, including before/after row snapshots. A domain event means a
meaningful business fact, with minimal context. Existing audit triggers remain independent;
events do not replace audit or copy full rows into a second store.

## Security and types

Every new table enables and forces RLS with no client policies. All table privileges and
internal function execution are revoked from PUBLIC, anon, authenticated and service_role.
Trusted migration-owner SECURITY DEFINER functions use an empty search_path and fully qualified
relations. No broad service-role emitter is provided. All domain authorization remains in the
existing RLS/RPC/BEFORE-trigger paths. UPDATE/DELETE guards also protect facts and receipts from
ordinary owner-level edits; privileged maintenance can still change DDL, as with existing audit.

`src/types/domain-events.ts` describes the private table rows and separates implemented names
from reserved future vocabulary. `src/types/database.ts` describes only the public API schema,
which is unchanged. These types do not grant an API for writing events.

## Extension contract and scheduling

Do not manually attach unrelated side effects to domain writes when they belong in this
pipeline. Add a registry entry, typed payload contract, validated emitter handler and an
authoritative transition hook. Add only named, reviewed SQL conditions/actions with strict
configuration validation. Add security, rollback and idempotency tests for each extension.
Registry text avoids an ever-growing PostgreSQL enum; registration alone never enables an
unvalidated emission handler. Reserved names in `FutureDomainEventType` cover unimplemented Activity deadlines and payment
vocabulary. Implemented project, Decision and Comment events are described below.

A future trusted scheduled evaluator should query canonical health/deadline/domain records
and emit through the same pipeline. Use a stable key containing the resource, deadline version,
and threshold/window so repeated scans deduplicate while rescheduling can produce a new fact.
Introduce narrowly granted worker entry points and pending/retry/error scheduling state in a
forward migration when needed. Existing processing receipts distinguish processed facts from
pending ones. External actions will require an outbox and per-action delivery retries; synchronous
receipts must not be treated as proof of exactly-once external delivery. Do not build independent
notification-specific cron systems per feature.

Phase 6 payment schedules do not emit a new event yet. Their due dates remain ordinary derived
financial data until the trusted evaluator is extended with schedule-aware, project-timezone
conditions and organizer recipient rules. The reserved `payment.due_soon` vocabulary remains
available; no duplicate payment event name is introduced.

## Phase 2 extension: project access requests

`20260920120000_project_join_links.sql` extends this foundation with
`project.join_requested` and `project.member_approved`. Both reference a private join-request
resource, use an empty supplemental payload, derive actor from the authoritative requester or
reviewer, and deduplicate on request plus `requested`/`approved`. Approval emits only when a
membership was actually activated; a no-op review of an already-active member emits nothing.

The `join_project_live` condition and named `notify_join_organizers` / `notify_approved_requester`
actions feed the existing notification store and processing/action receipts. New request/review
RPCs call the central internal emitter; there are no notification inserts in those mutations.
[Join Links](JOIN_LINKS.md) documents authorization, payload validation, token privacy and lifecycle.
The Phase 1 Activity paths and historical facts remain unchanged.

## Phase 4 Decision events and scheduler

`20260920150000_decisions.sql` registers decision.created, decision.vote_cast,
decision.deadline_reached and decision.resolved with validated transition handlers.
Creation/resolution use stable keys; genuine vote changes use a monotonic revision; exact retries
emit nothing. Vote payloads exclude option preferences. Deadline events use deadline version keys
and a null actor from one private pg_cron evaluator, bounded to 100 due Decisions per minute.
Project/Decision locks and rechecks prevent obsolete deadline emission. Server voting closure
is independent of evaluator timing. Deadline/resolution actions use the existing notification
store and immutable processing/action receipts. See [Decisions](DECISIONS.md) for permissions,
monitoring and retries. No external delivery or generic scheduler was added.

## Phase 5: contextual Comments without notifications

`20260921120000_resource_comments.sql` registers `comment.created` with event resource type
`comment`. The trusted creation operation derives author and parent/project; the central emitter
validates those bindings and the stable `created` key. Payload contains only parent_resource_type
and parent_resource_id, never body. A matching request-ID retry returns the original live row;
reads and deletion emit nothing. The fact and processing receipt share the comment transaction.

No default comment automation rule, action or notification is added. Future mentions/followers/
subscriptions can establish deliberate recipients without changing creation. Existing processed
facts are not replayed automatically when rules change. Comments also omit body from audit
snapshots and add no analytics. See [Comments](COMMENTS.md) for lifecycle and authorization.

## Phase 7: reimbursement requests

`20260928160000_reimbursement_requests.sql` registers `reimbursement.created` and
`reimbursement.cancelled` with resource type `reimbursement`. The internal emitter
validates project, parent source, actor authority, lifecycle and stable `created` /
`cancelled` keys. Payload contains only `activity_id` and `payment_id`; amounts and
member profiles stay in the authorized resource read model. Exact create/cancel
retries emit no duplicate facts. Both facts receive the existing processing receipt.

The `notify_reimbursement_debtor` action targets only the active debtor, once per
created request, using the existing notification store and action receipt. Cancellation
has no notification rule. The inbox hides cancelled/deleted requests and changes stale
financial snapshots to review copy. Notifications open the existing Activity route with
`section=reimbursements`. No external delivery, public share resource or scheduled event
is introduced. Existing event handlers are retained behind delegating private wrappers,
with client execution revoked. See [Reimbursements](REIMBURSEMENTS.md).
