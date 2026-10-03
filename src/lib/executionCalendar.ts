import { DateTime } from 'luxon';
import { userFacingActivityStatus } from './presentation';
import type { CalendarEntry } from '@/types/calendar';

export function entryDay(entry: CalendarEntry, zone: string): string {
  return entry.start_date ?? DateTime.fromISO(entry.start_at!, { zone }).toISODate()!;
}
export function entryOnDay(entry: CalendarEntry, day: string, zone: string): boolean {
  const start = entryDay(entry, zone);
  if (entry.all_day) return day >= start && day <= (entry.end_date ?? start);
  const end = entry.end_at ? DateTime.fromISO(entry.end_at, { zone }).minus({ milliseconds: 1 }).toISODate()! : start;
  return day >= start && day <= (end < start ? start : end);
}
export function calendarRoute(entry: CalendarEntry) {
  if (entry.source_type === 'decision') return { name: 'project.decision', params: { projectId: entry.project_id, decisionId: entry.source_id } };
  return { name: 'project.commitments', params: { projectId: entry.project_id }, query: {
    commitment: entry.activity_id!,
    ...(entry.source_type === 'payment_schedule' ? { section: 'payments' } : {}),
    ...(entry.occurrence_date ? { occurrence: entry.occurrence_date } : {}),
  } };
}
export function calendarSource(entry: CalendarEntry): string {
  if (entry.source_type === 'decision') return 'Decision deadline';
  if (entry.source_type === 'payment_schedule') return 'Payment due';
  return `Activity · ${entry.activity_type ?? 'other'}`;
}
export function calendarStatus(entry: CalendarEntry): string {
  if (entry.source_type === 'activity') return userFacingActivityStatus(entry.status);
  const labels: Record<string, string> = { completed: 'Complete', cancelled: 'Cancelled', resolved: 'Resolved', voting_closed: 'Voting closed', open: 'Open', paid: 'Paid', part_paid: 'Part paid', upcoming: 'Upcoming', overdue: 'Overdue', skipped: 'Skipped', draft: 'Draft', confirmed: 'Confirmed', in_progress: 'In progress', pending: 'Pending' };
  return labels[entry.status] ?? entry.status.replaceAll('_', ' ');
}
