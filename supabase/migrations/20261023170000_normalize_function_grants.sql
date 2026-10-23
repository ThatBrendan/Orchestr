-- Normalize the 43 release-candidate RPC ACLs; no function bodies or domain writes.
-- 41 authenticated-only client RPCs; two admin RPCs retain service_role.
-- PUBLIC must be revoked explicitly even where observed drift is a direct grant.

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.accept_invitation(p_token text) from public, anon, authenticated, service_role;
grant execute on function public.accept_invitation(p_token text) to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.cancel_item_settlement(p_group uuid) from public, anon, authenticated, service_role;
grant execute on function public.cancel_item_settlement(p_group uuid) to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.complete_assigned_item(p_item uuid, p_occurrence_date date) from public, anon, authenticated, service_role;
grant execute on function public.complete_assigned_item(p_item uuid, p_occurrence_date date) to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.complete_assigned_task(p_task uuid, p_occurrence_date date) from public, anon, authenticated, service_role;
grant execute on function public.complete_assigned_task(p_task uuid, p_occurrence_date date) to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.complete_commitment_occurrence(p_commitment uuid, p_occurrence_date date) from public, anon, authenticated, service_role;
grant execute on function public.complete_commitment_occurrence(p_commitment uuid, p_occurrence_date date) to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.complete_task_occurrence(p_task uuid, p_occurrence_date date) from public, anon, authenticated, service_role;
grant execute on function public.complete_task_occurrence(p_task uuid, p_occurrence_date date) to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.create_activity_in_category(p_project uuid, p_category uuid, p_fields jsonb, p_split jsonb) from public, anon, authenticated, service_role;
grant execute on function public.create_activity_in_category(p_project uuid, p_category uuid, p_fields jsonb, p_split jsonb) to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.create_invitation(p_project_id uuid, p_email text, p_role public.member_role) from public, anon, authenticated, service_role;
grant execute on function public.create_invitation(p_project_id uuid, p_email text, p_role public.member_role) to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.create_project(p_name text, p_timezone text, p_currency text, p_starts_on date, p_ends_on date, p_profile public.project_profile) from public, anon, authenticated, service_role;
grant execute on function public.create_project(p_name text, p_timezone text, p_currency text, p_starts_on date, p_ends_on date, p_profile public.project_profile) to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.create_project_note(p_project uuid, p_title text, p_body text) from public, anon, authenticated, service_role;
grant execute on function public.create_project_note(p_project uuid, p_title text, p_body text) to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.create_task_with_cost(p_project uuid, p_fields jsonb, p_cost numeric) from public, anon, authenticated, service_role;
grant execute on function public.create_task_with_cost(p_project uuid, p_fields jsonb, p_cost numeric) to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.decline_invitation(p_token text) from public, anon, authenticated, service_role;
grant execute on function public.decline_invitation(p_token text) to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.delete_project_category(p_category uuid) from public, anon, authenticated, service_role;
grant execute on function public.delete_project_category(p_category uuid) to authenticated;

-- AUTHENTICATED CLIENT RPC + SERVICE-ROLE BACKEND RPC
revoke execute on function public.get_admin_overview() from public, anon, authenticated, service_role;
grant execute on function public.get_admin_overview() to authenticated, service_role;

-- AUTHENTICATED CLIENT RPC + SERVICE-ROLE BACKEND RPC
revoke execute on function public.get_admin_project_health_summary(p_project uuid) from public, anon, authenticated, service_role;
grant execute on function public.get_admin_project_health_summary(p_project uuid) to authenticated, service_role;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.get_commitment_occurrences(p_commitment uuid, p_start date, p_end date) from public, anon, authenticated, service_role;
grant execute on function public.get_commitment_occurrences(p_commitment uuid, p_start date, p_end date) to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.get_invitation(p_token text) from public, anon, authenticated, service_role;
grant execute on function public.get_invitation(p_token text) to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.get_my_attention() from public, anon, authenticated, service_role;
grant execute on function public.get_my_attention() to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.get_my_timeline_events(p_start timestamp with time zone, p_end timestamp with time zone) from public, anon, authenticated, service_role;
grant execute on function public.get_my_timeline_events(p_start timestamp with time zone, p_end timestamp with time zone) to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.get_project_health(p_project uuid) from public, anon, authenticated, service_role;
grant execute on function public.get_project_health(p_project uuid) to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.get_project_health_summary(p_project uuid) from public, anon, authenticated, service_role;
grant execute on function public.get_project_health_summary(p_project uuid) to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.get_project_timeline_events(p_project uuid, p_start timestamp with time zone, p_end timestamp with time zone) from public, anon, authenticated, service_role;
grant execute on function public.get_project_timeline_events(p_project uuid, p_start timestamp with time zone, p_end timestamp with time zone) to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.get_task_occurrences(p_task uuid, p_start date, p_end date) from public, anon, authenticated, service_role;
grant execute on function public.get_task_occurrences(p_task uuid, p_start date, p_end date) to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.list_my_invitations() from public, anon, authenticated, service_role;
grant execute on function public.list_my_invitations() to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.mark_notification_read(p_notification uuid) from public, anon, authenticated, service_role;
grant execute on function public.mark_notification_read(p_notification uuid) to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.record_item_settlement(p_item uuid, p_from uuid, p_to uuid, p_amount bigint, p_date date) from public, anon, authenticated, service_role;
grant execute on function public.record_item_settlement(p_item uuid, p_from uuid, p_to uuid, p_amount bigint, p_date date) to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.record_member_payment(p_commitment uuid, p_member uuid, p_amount bigint, p_type public.payment_type, p_paid_now boolean, p_date date) from public, anon, authenticated, service_role;
grant execute on function public.record_member_payment(p_commitment uuid, p_member uuid, p_amount bigint, p_type public.payment_type, p_paid_now boolean, p_date date) to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.save_activity_with_split(p_project uuid, p_commitment uuid, p_fields jsonb, p_split jsonb) from public, anon, authenticated, service_role;
grant execute on function public.save_activity_with_split(p_project uuid, p_commitment uuid, p_fields jsonb, p_split jsonb) to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.save_commitment_occurrence_note(p_commitment uuid, p_occurrence_date date, p_note text) from public, anon, authenticated, service_role;
grant execute on function public.save_commitment_occurrence_note(p_commitment uuid, p_occurrence_date date, p_note text) to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.set_activity_cost_split(p_commitment uuid, p_split jsonb) from public, anon, authenticated, service_role;
grant execute on function public.set_activity_cost_split(p_commitment uuid, p_split jsonb) to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.set_actual_cost_with_split(p_commitment uuid, p_amount numeric, p_complete boolean, p_split jsonb) from public, anon, authenticated, service_role;
grant execute on function public.set_actual_cost_with_split(p_commitment uuid, p_amount numeric, p_complete boolean, p_split jsonb) to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.set_commitment_actual_cost(p_commitment uuid, p_amount numeric, p_complete boolean) from public, anon, authenticated, service_role;
grant execute on function public.set_commitment_actual_cost(p_commitment uuid, p_amount numeric, p_complete boolean) to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.set_project_budget(p_project uuid, p_amount numeric) from public, anon, authenticated, service_role;
grant execute on function public.set_project_budget(p_project uuid, p_amount numeric) to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.skip_commitment_occurrence(p_commitment uuid, p_occurrence_date date, p_reason text) from public, anon, authenticated, service_role;
grant execute on function public.skip_commitment_occurrence(p_commitment uuid, p_occurrence_date date, p_reason text) to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.skip_task_occurrence(p_task uuid, p_occurrence_date date) from public, anon, authenticated, service_role;
grant execute on function public.skip_task_occurrence(p_task uuid, p_occurrence_date date) to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.soft_delete_commitment(p_commitment uuid) from public, anon, authenticated, service_role;
grant execute on function public.soft_delete_commitment(p_commitment uuid) to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.soft_delete_project(p_project uuid) from public, anon, authenticated, service_role;
grant execute on function public.soft_delete_project(p_project uuid) to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.soft_delete_project_note(p_note uuid) from public, anon, authenticated, service_role;
grant execute on function public.soft_delete_project_note(p_note uuid) to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.soft_delete_task(p_task uuid) from public, anon, authenticated, service_role;
grant execute on function public.soft_delete_task(p_task uuid) to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.stop_commitment_recurrence(p_commitment uuid, p_stop_after date) from public, anon, authenticated, service_role;
grant execute on function public.stop_commitment_recurrence(p_commitment uuid, p_stop_after date) to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.stop_task_recurrence(p_task uuid, p_stop_after date) from public, anon, authenticated, service_role;
grant execute on function public.stop_task_recurrence(p_task uuid, p_stop_after date) to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.transfer_and_leave(p_project uuid, p_new_organizer_member uuid) from public, anon, authenticated, service_role;
grant execute on function public.transfer_and_leave(p_project uuid, p_new_organizer_member uuid) to authenticated;

-- AUTHENTICATED CLIENT RPC
revoke execute on function public.update_project_note(p_note uuid, p_title text, p_body text) from public, anon, authenticated, service_role;
grant execute on function public.update_project_note(p_note uuid, p_title text, p_body text) to authenticated;

-- Only postgres-created functions in public: match DEVELOP's schema defaults.
-- Do not change global PUBLIC defaults or platform-owned roles/schemas.
-- Future function migrations must still explicitly revoke PUBLIC and grant callers.
alter default privileges for role postgres in schema public
  revoke execute on functions from anon, authenticated, service_role;
