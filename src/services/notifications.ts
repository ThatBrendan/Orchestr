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
