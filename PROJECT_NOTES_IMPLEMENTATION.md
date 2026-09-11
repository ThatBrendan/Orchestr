# Multi-note project Notes

## Notes model

- Table: `public.project_notes`.
- Limit: 20 active notes per project, enforced by `create_project_note` while holding a project row lock. Soft-deleted notes do not count. All client writes must use RPCs; direct table writes are not granted.
- Title: required, maximum 120 characters.
- Body: required, maximum 10,000 characters.
- New/edited content is trimmed; all-whitespace content is rejected by database constraints.
- Sort: updated_at descending, then id ascending for deterministic ties.
- Soft deletion: deleted_at; normal reads exclude deleted notes. Deleting a project hides notes via parent visibility without resetting a note's own deletion state. Hard project deletion cascades by FK.

## Legacy migration

`20260911130000_multi_project_notes.sql` copies every non-empty `projects.notes` value into one `Project note`. Legacy body text is preserved exactly, including surrounding whitespace. Blank/null values are skipped. Archived and deleted projects' content is preserved; deleted projects' imported notes carry deleted_at.

The author of the old shared field cannot reliably be inferred from the project's creator. Imported notes have null created_by (displayed as Unknown author) and import timestamps, rather than invented historical dates. The legacy column remains intact and unused by the new frontend. It is not synchronized with the new table; coordinate the frontend release with migration so old clients do not continue writing the legacy field.

## Permissions

| Role | Create | Edit own | Edit others | Delete own | Delete others | Read |
|---|---|---|---|---|---|---|
| Organizer | Yes | Yes | Yes | Yes | Yes | Yes |
| Member | Yes | Yes | No | Yes | No | Yes |
| Viewer | No | No | No | No | No | Yes |
| Nonmember/anonymous | No | No | No | No | No | No |

Archived projects retain reads and reject all note writes. Null-author legacy notes can be managed only by organizers. This follows the repository's content ownership model; existing task/activity/project authorization is unchanged. Platform-admin status grants no additional note access.

## Database

- Migration: `supabase/migrations/20260911130000_multi_project_notes.sql`.
- Table: project_notes (id, project_id, created_by, title, body, created_at, updated_at, deleted_at).
- Cross-project integrity: composite creator FK to project_members(project_id,id). Member hard deletion clears attribution only; project deletion cascades notes.
- RPCs: create_project_note, update_project_note, soft_delete_project_note. SECURITY DEFINER with empty search_path and explicit membership/ownership/archive checks. Creation stamps the caller's member ID.
- View: v_project_notes, security_invoker, joined creator display name without N+1 requests.
- RLS: project_notes_read permits active members to see non-deleted notes in non-deleted projects, including archived projects.
- Indexes: active (project_id, updated_at DESC, id); creator (project_id, created_by); primary key.
- Grants: authenticated SELECT on table/view and EXECUTE on the three RPCs. PUBLIC/anon RPC execution revoked; authenticated/anon direct writes revoked. service_role has table access.
- Triggers: existing updated_at and audit helpers record create/update/soft-delete events. Backfill is performed before these triggers are attached.

## UI

Add/edit dialog uses existing modal primitives, required fields, Unicode character counts, validation, busy guards, and mutation invalidation. The refreshed list appears without a page reload. Delete uses confirmation and soft deletion. At the cap, Add is disabled and the required limit message appears; the server also enforces it for stale/concurrent clients.

Cards show title, creator, created date, edited date where applicable, and plain-text body. Long content wraps and offers expand/collapse with a bounded scroll area. Header/actions wrap on small screens and the existing modal has a scrollable body. The current Notes module/profile configuration is unchanged.

## Verification

- TypeScript: passed (`npx vue-tsc --noEmit`).
- Lint: passed, zero errors; 1,511 warnings repository-wide.
- Build: passed (`npm run build`).
- Diff whitespace check: passed.
- pgTAP: added `18_multi_project_notes.sql` and `19_project_notes_legacy_migration.sql`; not run because the local Docker daemon is unavailable. Suite 19 replays the actual migration in a rolled-back transaction against fixtures; use only in a local test database.
- Create/edit/delete, limit, permissions: implemented and covered by added SQL tests, not runtime-verified.
- Live E2E, persistence across refresh, Viewer session, mobile session: not performed; no authenticated test session was used and the migration is not deployed.

Required deployment command (not run):

```sh
supabase db push
```

Apply the database migration before releasing the frontend. Once the local stack is available, apply migrations locally and run `supabase test db`. Then run the requested live add-two/edit/delete/refresh/Viewer/mobile flow before release. No Edge Function deployment is needed for Notes. No commits or pushes were made.
