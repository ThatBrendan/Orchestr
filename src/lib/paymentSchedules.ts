import { DateTime } from "luxon";

/** Date-only schedules follow the project's local calendar, including DST. */
export function paymentScheduleStatus(schedule: { outstanding_minor: number; net_paid_minor: number; due_on: string }, timezone: string) {
  const today = DateTime.now().setZone(timezone).toISODate()!;
  if (schedule.outstanding_minor <= 0) return "Paid";
  if (schedule.due_on < today) return "Overdue";
  if (schedule.net_paid_minor > 0) return "Part paid";
  if (schedule.due_on === today) return "Due today";
  if (schedule.due_on <= DateTime.fromISO(today).plus({ days: 7 }).toISODate()!) return "Due soon";
  return "Upcoming";
}
export function paymentScheduleTone(status: string): "success" | "danger" | "amber" | "neutral" {
  return status === "Paid" ? "success" : status === "Overdue" ? "danger" : ["Part paid", "Due soon", "Due today"].includes(status) ? "amber" : "neutral";
}
export const paymentScheduleLabels: Record<string, string> = { paid: "Paid", overdue: "Overdue", part_paid: "Part paid", due_today: "Due today", due_soon: "Due soon", upcoming: "Upcoming" };
