import { supabase } from "@/lib/supabase";
import { AppError, toAppError } from "@/lib/errors";
import type { Database } from "@/types/database";
export type ActivityNotification = Database["public"]["Views"]["v_my_activity_notifications"]["Row"];

/** An unread inbox. Opening items removes them; older unread items then fill the page. */
export async function listActivityNotifications() {
  const { data, count, error } = await supabase.from("v_my_activity_notifications")
    .select("*", { count: "exact" }).is("read_at", null)
    .order("created_at", { ascending: false }).order("id", { ascending: false }).limit(50);
  if (error) throw toAppError(error);
  return { items: data ?? [], unreadCount: count ?? 0 };
}

export async function markNotificationRead(id: string) {
  const { data, error } = await supabase.rpc("mark_notification_read", { p_notification: id });
  if (error) throw toAppError(error);
  if (!data) throw new AppError("not_found", "This notification is no longer available.");
}

export function activityNotificationRoute(item: ActivityNotification) {
  return { name: "project.commitments", params: { projectId: item.project_id }, query: { commitment: item.commitment_id } };
}

export type JoinNotification = Database["public"]["Views"]["v_my_join_notifications"]["Row"];
export async function listJoinNotifications() {
  const { data, count, error } = await supabase.from("v_my_join_notifications")
    .select("*", { count: "exact" }).is("read_at", null)
    .order("created_at", { ascending: false }).order("id", { ascending: false }).limit(50);
  if (error) throw toAppError(error);
  return { items: data ?? [], unreadCount: count ?? 0 };
}
export function joinNotificationRoute(item: JoinNotification) {
  return { name: "project.overview", params: { projectId: item.project_id },
    query: item.kind === "project_join_requested" ? { settings: "1" } : {} };
}

export type DecisionNotification = Database["public"]["Views"]["v_my_decision_notifications"]["Row"];
export async function listDecisionNotifications() {
  const { data, count, error } = await supabase.from("v_my_decision_notifications").select("*", { count: "exact" }).is("read_at", null).order("created_at", { ascending: false }).order("id", { ascending: false }).limit(50);
  if (error) throw toAppError(error);
  return { items: data ?? [], unreadCount: count ?? 0 };
}
export function decisionNotificationRoute(item: DecisionNotification) {
  return { name: "project.decision", params: { projectId: item.project_id, decisionId: item.decision_id } };
}
