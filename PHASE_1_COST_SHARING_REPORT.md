# Phase 1 — Activity cost sharing

Phase 1 is implemented and its migration is applied to develop (`msfkczsoutbeyhjvegnw`). Stopping here as requested. Phases 2, 3 and 4 have not started. No commit, push, merge or production deployment was performed.

## Model and UX

Existing `cost_shares`, `commitment_participants`, `project_members` and commitment costs remain the domain model. No competing expense table or reimbursement engine was introduced. Every Activity type/category can share a known cost, including a known zero. Child Tasks remain nonfinancial.

The reusable Cost sharing editor appears in Activity create/edit when a cost exists, loads existing allocations, and appears alongside final-cost confirmation. Detail displays each person's allocation. Users can select active project members, including supported name-only members; selection does not implicitly change attendance/Activity participants.

| Mode | Behaviour |
| --- | --- |
| No split | Explicitly stores no allocation. Participants do not imply shares. New Activities created through the application default to this mode. |
| Split evenly | Selected member IDs are sorted deterministically. Integer division assigns each remainder minor unit to the earliest IDs. £600 / 3 persists £200 each; £100 / 3 persists £33.34, £33.33, £33.33. |
| Custom split | Explicit amounts must equal effective cost exactly. UI displays allocated/total and remaining/over; invalid submissions are rejected without persisting partial changes. |
| Existing allocation | Historical implicit participant, equal, weight and fixed allocations retain their existing rules until explicitly changed. The UI identifies them and loads their calculated shares. |

All new even/custom allocations persist as existing `basis='fixed'` rows with exact `fixed_amount_minor` values. Mode is recorded separately so even allocations can be explicitly recalculated later. No Payment is created by configuring a split.

## Cost-change reconciliation

Effective cost remains actual, otherwise agreed price, otherwise estimate, using the existing backend helper. Estimates and paid financial history are preserved.

Changing effective cost displays the previous/current amounts and requires review. Users can recalculate evenly, edit custom allocations to the exact new amount, or explicitly choose No split. Managed allocations cannot remain inconsistent with cost, and cannot switch back into the legacy mode. Legacy cost changes with participants/shares also require an explicit reviewed mode. Historical fixed-only allocations may remain as they were; editing those shares requires full allocation.

Activity create/edit plus split and actual-cost/completion plus split are transactional. Failed reconciliation rolls back both parts. Unrelated Activity edits do not automatically replace shares. No automatic redistribution occurs simply because the cost draft changes or a dialog opens.

## Permissions

All writes require an active project membership with the appropriate existing role and a writable project. Split recipients must be active, nondeleted members of the same project. Removed recipients remain visible in historical allocations; to change that split, select an explicit mode and remove/replace inactive recipients.

| Action | Organizer | Assigned Member | Other Member | Viewer |
| --- | --- | --- | --- | --- |
| Configure cost split | Yes | Yes | Yes, existing Activity edit permission | No |
| Add Payment / mark paid | Existing permission | Existing permission | Existing permission | No |
| Set actual cost | Yes, including corrections | While actionable | No | No |
| Start / complete | Existing transition rules | Existing transition rules | Existing transition rules | No |
| Project budget | Yes | No | No | No |

No platform-admin bypass was added. No frontend role or member-ID assertion is trusted for financial writes. Existing Activity estimate, Payment history and archive guards remain authoritative. Phases 2–4 will assess their own UX changes separately.

## Database

Migration: `supabase/migrations/20260911170000_activity_cost_sharing.sql`.

| Object | Change |
| --- | --- |
| `commitments.cost_split_mode` | New nullable text column constrained to none/even/custom. Null preserves historical and legacy API semantics; the new application save RPC explicitly creates none. |
| `cost_shares` | Existing table reused; no new amount column or enum. |
| `set_activity_cost_split(uuid,jsonb)` | Authenticated organizer/member RPC; locks Activity and recipients, validates membership/current cost, saves exact allocations, validates totals. |
| `save_activity_with_split(uuid,uuid,jsonb,jsonb)` | Invoker RPC with an explicit editable-field allowlist; atomically creates/edits Activity and split under existing RLS. |
| `set_actual_cost_with_split(uuid,numeric,boolean,jsonb)` | Invoker wrapper around the existing actual-cost RPC and split RPC, preserving actual-cost authorization and atomic completion. |
| `app.validate_activity_split` | Checks exact totals and deterministic even allocations. |
| `app.tg_validate_activity_split` | Deferred checks across Activity/share mutations, including reconciliation and legacy-mode protection. |
| `app.tg_share_member_guard` | Serializes allocation writes with Activity edits; rejects inactive/wrong-project recipients and moving allocations to another Activity. |
| Triggers | `activity_split_total`, `activity_share_total`, `share_member_guard`. |
| `v_activity_cost_shares` | New security-invoker detail read model, reusing the existing allocation/rounding semantics across Activity statuses. |
| `v_member_balances` | Explicit No split excludes allocations; legacy calculations and payment attribution are preserved. |
| `app._health_findings` | Explicit No split no longer produces an unallocated-cost prompt. Other Health rules preserved. |
| RLS | No policy changes or broadening. Existing policies remain active; triggers protect direct writes too. |
| Grants | Authenticated execute on the three public RPCs and select on the new view; public execution revoked on new functions. |
| Audit | Existing Activity/share audit triggers record mode and allocation changes. |
| Indexes | None added; existing Activity/member/share keys reused. |

No historical records were rewritten. Activities, Tasks, Payments, status enums and booking behaviour remain compatible. The previous implicit participant splitting is preserved for legacy records and clients, rather than silently removed. New application No split is explicit and honoured by both detail and member-balance views.

## Verification

| Check | Result |
| --- | --- |
| TypeScript | PASS — `npx vue-tsc --noEmit` |
| Lint | PASS — zero errors; one existing intentional AppIcon v-html warning |
| Build | PASS — `npm run build` |
| diff | PASS — `git diff --check` |
| Integer allocation tests | PASS — `node scripts/cost-sharing.test.mjs` |
| Phase 1 pgTAP | PASS — 32 assertions from `23_activity_cost_sharing.sql`, executed with the migration inside a rollback-only develop transaction |
| Existing financial regression | PASS — 13 assertions from `03_financials.sql` in a rollback-only develop transaction |
| Full local pgTAP suite | NOT RUN — Docker is unavailable |
| Develop migration | PASS — verified target, reviewed dry run, successful push, matching migration history |
| Phase 1 browser E2E | NOT RUN — frontend changes are not deployed to Preview |
| Member / Viewer | PASS for Phase 1 database permission assertions; browser role walkthrough NOT RUN |
| Mobile | NOT RUN — responsive form markup implemented, no browser visual assertion |
| Preview | NOT RUN |
| Phases 2–4 E2E | NOT RUN — phases intentionally not started |

For remote SQL validation, a temporary harness converted failing pgTAP results into exceptions, so a successful query meant every assertion passed. Each transaction ended in rollback: test users, projects, allocations and test schema changes did not persist. The separately reviewed migration push then applied the schema. Initial test setup was corrected to create authenticated-member fixtures under the database role, respecting existing RLS; the final 32-assertion run passed.

Coverage includes £600 / 3, uneven pennies, custom £100/£50/£30, under/over rejection, rollback of partial creation, cost/actual reconciliation, legacy allocation preservation, no-split semantics, wrong-project and removed members, Viewer/nonmember denial, active Member editing, archive protection, exact view totals, and no invented Payments. The existing financial test confirms legacy balances and paid/cancelled financial history remain unchanged.

## Files changed

- `src/components/commitments/CostSplitEditor.vue` (new)
- `src/components/commitments/CommitmentFormDialog.vue`
- `src/components/commitments/CommitmentDetailDialog.vue`
- `src/components/commitments/ActualCostDialog.vue`
- `src/composables/useCostShares.ts` (new)
- `src/composables/useCommitments.ts`
- `src/composables/useFinancialPlanning.ts`
- `src/services/commitments.ts`
- `src/services/financialPlanning.ts`
- `src/lib/costSharing.ts` (new)
- `src/types/database.ts`
- `scripts/cost-sharing.test.mjs` (new)
- `supabase/migrations/20260911170000_activity_cost_sharing.sql` (new)
- `supabase/tests/23_activity_cost_sharing.sql` (new)
- `PHASE_1_COST_SHARING_REPORT.md` (new)

## Next phase and release

Phase 1 is the requested stopping point. Preview verification should cover the three-member £600 Airbnb and £180 custom transfer scenarios, refresh persistence, changed-cost reconciliation and mobile before proceeding through the remaining phases.

After all phases are approved in dev, production requires: review every phase migration; apply tested migrations to production; deploy changed Edge Functions if any; merge dev into main; verify Vercel Production; smoke-test production; relink the CLI to develop. Phase 1 has no Edge Function changes. None of those production actions were performed; the CLI remains linked to develop.
