# Financial settlement milestone — Phase 1 checkpoint

Phase 1 (Activity execution UX) is implemented. Stopping and reporting before Phase 2, as requested. This blocker milestone is not ready for onboarding: per-member settlement, project member balances, strict completion gating, and mandatory Preview E2E remain pending.

## Blocker status

| Blocker | Status | Detail |
| --- | --- | --- |
| Old Activity workflow | PARTIAL | Simplified UI implemented and automated checks pass; Preview/mobile walkthrough remains unverified. |
| Per-member settlement | BLOCKED | Phase 2 intentionally not started at this checkpoint. Existing cost allocation remains available. |
| Member balances | BLOCKED | Phase 3 intentionally not started. Existing backend balances have not been repurposed into the requested settlement UI. |
| Completion gating | BLOCKED | Phase 4 intentionally not started. Current completion does not yet require financial settlement. |

The latest specification supersedes the preceding milestone's optional “Complete anyway” direction. No such override was added. Mandatory settlement enforcement will be implemented in Phase 4 after the settlement model is established.

## Execution model

| Persisted state | Execution label |
| --- | --- |
| idea | Not started |
| researching | In progress |
| confirmed | In progress |
| booked | In progress |
| completed | Completed |
| cancelled | Cancelled |

Confirmed/booked indicate progressed but unfinished work, rather than completion. Their persisted financial and booking meanings remain intact. Booking status is displayed separately so the execution mapping does not erase booking information.

All five Activity Types now default to `idea` in the create form, displaying Not started. Primary actions are Start and Complete. Non-booking Activities can complete directly from Not started or from In progress under the existing backend rules. Completed/cancelled Activities have no primary execution action. Cancel, Reopen and Restore live under More actions and retain the existing legal transitions.

### Booking compatibility

Booking has a dedicated detail section and separate list badge. Its display is Booked for a stored booked/completed state or an explicit booking confirmation; otherwise Ready to book for the historical confirmed stage, or Not booked. Historical booking evidence is not rewritten.

Existing booking transitions require `researching → confirmed → booked → completed`. Those rules remain intact. Confirm booking and Mark booked are secondary controls inside the Booking section, not primary execution actions. A not-started Booking shows Start; an in-progress Booking that has not reached booked explains that booking steps must be finished before completion. Once booked, Complete is available. Reopening a completed Booking retains its booked backend state.

This is a presentation compatibility layer, not a new independent execution-status database field. It deliberately does not invent booking history or silently traverse booking stages during completion. The underlying enum and booking workflow remain available for existing integrations and records.

## Other surfaces and domain audit

- Activity detail/list use the shared execution labels. Booked no longer receives the completed tone in these primary execution badges.
- Calendar Activity status text uses the same presentation labels. Payment and recurring-occurrence statuses retain their existing presentation paths.
- Recurring series actions remain suppressed; occurrence completion/skipping and date semantics are unchanged.
- Timeline/Calendar event selection, overdue detection and dates still use their existing backend states; no date or financial queries changed.
- Overview retains its separate progress and booking metrics. Their underlying counts have not been redefined.
- Health keeps its existing state predicates. No Health functions, findings, or filters were rewritten.
- Activity Type and Category remain independent; all current types and categories remain available.

## Settlement and completion at this checkpoint

Cost sharing remains allocation, while paid amounts remain Payment-derived. Existing actual-cost confirmation and split reconciliation still run when applicable. No new payment attribution, partial-settlement workflow, refund aggregation, member-balance UI, or financially-settled boolean was added in Phase 1.

Current completion remains governed by existing authorization, transition and cost-split rules. It can still complete an unpaid cost-bearing Activity. Therefore this checkpoint must not be represented as satisfying the final financial completion blocker.

## Database and compatibility

No migration was required. No tables, columns, enums, RPCs, functions, views, triggers, RLS policies, grants or indexes changed.

Historical completed Activities retain their status. Historical Payments, actual costs, cost shares and booking states are untouched. The existing organizer/member write policy and viewer read-only policy remain authoritative. Archive protections and platform-admin isolation were not changed.

No production link, migration, deployment, commit, push or merge was performed.

## Verification

| Check | Result |
| --- | --- |
| TypeScript | PASS — `npx vue-tsc --noEmit` |
| Lint | PASS — zero errors; one existing AppIcon v-html warning |
| Build | PASS — `npm run build` |
| diff | PASS — `git diff --check` |
| Execution presentation | PASS — `node scripts/activity-execution.test.mjs` across all five Types and all historical states |
| Phase 1 pgTAP | PASS — 15 assertions from `24_activity_execution.sql` executed on develop in a rollback-only transaction |
| Full local pgTAP suite | NOT RUN — local Docker unavailable |
| Member / Organizer | PASS — database transition assertions; browser walkthrough NOT RUN |
| Viewer | PASS — database mutation denial and unchanged-status assertions; browser walkthrough NOT RUN |
| Booking compatibility | PASS — confirmation, booked, completion, reopen and retained confirmation assertions |
| Per-member / partial settlement | NOT RUN — Phase 2 pending |
| Member balances | NOT RUN — Phase 3 pending |
| Completion blocked / after full settlement | NOT RUN — Phase 4 pending |
| Deposit/balance gating | NOT RUN — Phase 4 pending |
| Mobile | NOT RUN |
| Mandatory Preview E2E | NOT RUN — frontend changes have not been published to dev Preview |

The temporary remote test harness raises an exception for any failing pgTAP assertion. All 15 final assertions passed, and the transaction rolled back all test users/projects/Activities. An initial fixture omission of required Category was corrected before the passing run. No database schema was changed by the test.

Preview E2E remains a mandatory release prerequisite, not replaced by these automated checks. The full settlement/completion scenarios cannot yet pass because Phases 2–4 have intentionally not started.

## Files changed

- `src/lib/activityWorkflows.ts`
- `src/components/commitments/CommitmentDetailDialog.vue`
- `src/views/project/CommitmentsTab.vue`
- `src/views/CalendarView.vue`
- `scripts/activity-execution.test.mjs` (new)
- `supabase/tests/24_activity_execution.sql` (new)
- `FINANCIAL_SETTLEMENT_PHASE_1_REPORT.md` (new)

## Production release after approval of the complete milestone

1. Review every migration created by all phases.
2. Apply tested migrations to production after target verification and dry-run review.
3. Deploy changed Edge Functions if any; Phase 1 has none.
4. Merge dev into main under release authorization.
5. Verify Vercel Production.
6. Run the production settlement/completion smoke test.
7. Relink Supabase CLI back to develop.

No production release action was performed at this Phase 1 checkpoint.
