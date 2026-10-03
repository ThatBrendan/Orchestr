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

export type PaymentNotification = Database["public"]["Views"]["v_my_payment_notifications"]["Row"];
export async function listPaymentNotifications() {
  const { data, count, error } = await supabase.from("v_my_payment_notifications").select("*", { count: "exact" }).is("read_at", null).order("created_at", { ascending: false }).order("id", { ascending: false }).limit(50);
  if (error) throw toAppError(error);
  return { items: data ?? [], unreadCount: count ?? 0 };
}
export function paymentNotificationRoute(item: PaymentNotification) {
  return { name: "project.commitments", params: { projectId: item.project_id }, query: { commitment: item.commitment_id, section: "payments" } };
}

export type ReimbursementNotification = Database["public"]["Views"]["v_my_reimbursement_notifications"]["Row"];
export async function listReimbursementNotifications() {
  const { data, count, error } = await supabase.from("v_my_reimbursement_notifications").select("*", { count: "exact" }).is("read_at", null).order("created_at", { ascending: false }).order("id", { ascending: false }).limit(50);
  if (error) throw toAppError(error);
  return { items: data ?? [], unreadCount: count ?? 0 };
}
export function reimbursementNotificationRoute(item: Pick<ReimbursementNotification, 'project_id' | 'commitment_id'>) {
  return { name: "project.commitments", params: { projectId: item.project_id }, query: { commitment: item.commitment_id, section: "reimbursements" } };
}

export type PaymentAcknowledgementNotification = Database['public']['Views']['v_my_payment_acknowledgement_notifications']['Row'];
export async function listPaymentAcknowledgementNotifications() {
  const { data, count, error } = await supabase.from('v_my_payment_acknowledgement_notifications').select('*', { count: 'exact' }).is('read_at', null).order('created_at', { ascending: false }).order('id', { ascending: false }).limit(50);
  if (error) throw toAppError(error);
  return { items: data ?? [], unreadCount: count ?? 0 };
}

export type ReceiptConfirmationNotification = Database['public']['Views']['v_my_receipt_confirmation_notifications']['Row'];
export async function listReceiptConfirmationNotifications() {
 const { data, count, error } = await supabase.from('v_my_receipt_confirmation_notifications').select('*', { count: 'exact' }).is('read_at', null).order('created_at', { ascending: false }).order('id', { ascending: false }).limit(50);
 if (error) throw toAppError(error);
 return { items: data ?? [], unreadCount: count ?? 0 };
}

export type InboxNotification = Database['public']['Views']['v_my_notification_inbox']['Row'];
export type NotificationCursor = Pick<InboxNotification, 'created_at' | 'id'>;
export async function listNotificationInbox(cursor?: NotificationCursor) {
  let query = supabase.from('v_my_notification_inbox').select('*').order('created_at', { ascending: false }).order('id', { ascending: false }).limit(21);
  if (cursor) query = query.or(`created_at.lt.${cursor.created_at},and(created_at.eq.${cursor.created_at},id.lt.${cursor.id})`);
  const { data, error } = await query;
  if (error) throw toAppError(error);
  const items = (data ?? []).slice(0, 20);
  return { items, next: (data?.length ?? 0) > 20 ? items.at(-1) : undefined };
}
export async function notificationUnreadCount() {
  const { count, error } = await supabase.from('v_my_notification_inbox').select('id', { count: 'exact', head: true }).is('read_at', null);
  if (error) throw toAppError(error);
  return count ?? 0;
}
export async function markAllNotificationsRead() {
  const { data, error } = await supabase.rpc('mark_all_notifications_read');
  if (error) throw toAppError(error);
  return data;
}
export function notificationRoute(item: InboxNotification) {
  if (item.resource_type === 'activity') return { name: 'project.commitments', params: { projectId: item.project_id }, query: { commitment: item.resource_id, ...(item.section === 'payments' || item.section === 'reimbursements' ? { section: item.section } : {}) } };
  if (item.resource_type === 'decision') return { name: 'project.decision', params: { projectId: item.project_id, decisionId: item.resource_id } };
  if (item.resource_type === 'project') return { name: 'project.overview', params: { projectId: item.project_id }, query: item.section === 'people' ? { settings: '1' } : {} };
  throw new AppError('not_found', 'This notification is no longer available.');
}
