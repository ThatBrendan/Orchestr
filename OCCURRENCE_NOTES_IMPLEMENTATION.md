# Recurring activity occurrence notes

## Occurrence data model

- Series note: existing `commitments.notes`, displayed as Instructions; never copied to occurrences.
- Occurrence note: optional `commitment_occurrences.note`, trimmed, up to 10,000 characters; whitespace-only saves clear it.
- Skip status: existing `status = skipped` and skipped_at.
- Skip reason: optional storage for historical compatibility, but all new skips require 1–500 non-whitespace characters through the RPC and trigger. Old skipped rows display No reason recorded.
- Unique key: existing `(commitment_id, occurrence_date)`. Note/status mutations upsert only their relevant fields, preserving concurrent changes to other fields.
- Upcoming note-only rows use NULL status with no completed/skipped timestamp. Upcoming/overdue remains date-derived; no new status enum or competing entity is introduced.
- Persistence remains lazy: read queries do not insert rows. Clearing a note without an existing row inserts nothing; clearing an existing row preserves status/history.

## UX

Calendar's `?commitment=<id>&occurrence=<date>` is now passed to the activity dialog. The occurrence panel queries that exact date, including dates outside the previous fixed window. Without a supplied date it selects the first pending occurrence in the existing window, or the last returned occurrence. A date input permits selecting other dates and reports dates outside the series.

- Add/edit/save/clear occurrence note; a note is optional for completion.
- Complete affects only the selected date and preserves its note. The selection stays fixed after mutation rather than moving to the next date.
- Skip this occurrence opens a required Reason for skipping dialog, maximum 500 characters, and affects only that date.
- Stop recurrence remains the separate series operation and preserves existing state rows and text. Stored rows after a newly chosen cutoff remain in the database but are no longer derived/displayed as scheduled occurrences.
- Series status transition buttons are hidden in recurring detail to avoid completing the whole activity when intending to complete one date. Series editing remains available.
- Existing recurrence had no reopen operation; none was added. Completion of a previously skipped date preserves the note and clears the now-inapplicable skip reason; the audit retains the previous state.
- No recent-history summary was added. Individual historical dates remain accessible through the date selector and Timeline/Calendar, within their existing range bounds.

## Calendar and Timeline

The project timeline function no longer filters skipped recurring activities. The global Calendar delegates to this function and retains its membership scope. Calendar shows recurring status in the day agenda/accessibility label, mutes skipped items, and avoids overdue styling for skipped/completed dates. Month-grid event-type icons remain unchanged.

Timeline renders explicit recurring status badges and links recurring activities to the exact occurrence date. It uses the backend's overdue status for recurrence rather than comparing an all-day midnight timestamp to the current time.

Skip reasons and occurrence text are shown in detail, not copied into global event payloads or month markers. Recurring tasks keep their existing behavior; this change concerns recurring Activities.

## Health

Existing recurrence Health rules select rows with NULL completion/skip status. Completed/skipped occurrences therefore do not generate overdue findings. A note-only row still has NULL status, so writing a note does not falsely resolve an overdue date. No Health function changes were needed.

## Database

Migration: `supabase/migrations/20260911140000_occurrence_notes.sql`.

- Table: existing commitment_occurrences; adds note and skip_reason, permits NULL status, updates timestamp/state check constraints.
- New RPC: save_commitment_occurrence_note(uuid,date,text).
- Updated RPCs: get_commitment_occurrences returns note/reason; complete_commitment_occurrence preserves note and clears skip reason; skip_commitment_occurrence now takes required p_reason; get_project_timeline_events retains skipped activities.
- Trigger/function: app.require_occurrence_skip_reason enforces reasons for new skips while permitting edits on unchanged legacy skipped rows.
- Views: none added or replaced. Existing Calendar/Timeline views use the updated timeline function.
- RLS: unchanged; security-invoker RPCs retain Organizer/Member write access, Viewer read-only and nonmember isolation. Archived writes are blocked by existing policies. Recurrence-date and composite project FKs remain enforced.
- Indexes: unchanged; existing unique key and project/series/date lookup index reused.
- Grants: new RPC execution only to authenticated; PUBLIC execution revoked. Existing audit triggers record note/status/reason changes using the repository's full-row audit convention.

## Verification

- TypeScript: passed (`npx vue-tsc --noEmit`).
- Lint: passed, 0 errors; 1,351 repository warnings.
- Build: passed (`npm run build`).
- Whitespace/diff check: passed.
- pgTAP: suite 20 added; suite 14 updated for required reasons and visible skipped state. Not run: local Docker daemon unavailable.
- Occurrence note, different notes, completion, clear, skip, reason, next date, uniqueness, Health, Calendar/Timeline output, stop preservation, Viewer/Member/Organizer/isolation/archive rules: SQL coverage added, runtime unverified.
- Live E2E: not performed; migration not deployed and no authenticated live test session used.

Required deployment command, not run:

```sh
supabase db push
```

Apply the migration before releasing the frontend. The old two-argument skip RPC is removed, so coordinate deployment with the updated client. No Edge Function deployment is needed. Once local Supabase is available, apply migrations locally and run `supabase test db`; then exercise the requested weekly-activity flow through two distinct notes, completion, skip reason, Calendar/Timeline, and stop recurrence. No commits or pushes were made.
