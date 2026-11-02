import { DateTime } from 'luxon';
import type { GlobalTimelineEvent } from '@/types/derived';
import type { IconName } from '@/components/ui/icons';
import { presentLabel } from '@/lib/presentation';
import { executionStatusLabel } from '@/lib/activityWorkflows';

// Global Calendar retains its own projection and canonical destinations.
export function globalEventRoute(event: GlobalTimelineEvent) {
  if (event.subject_type === 'commitment') return {
    name: 'project.commitments', params: { projectId: event.project_id },
    query: { commitment: event.subject_id, ...(event.occurrence_date ? { occurrence: event.occurrence_date } : {}) },
  };
  if (event.subject_type === 'payment_schedule') return { name: 'project.commitments', params: { projectId: event.project_id }, query: { commitment: event.subject_id, section: 'payments' } };
  if (event.subject_type === 'payment') return { name: 'project.budget', params: { projectId: event.project_id } };
  if (event.subject_type === 'task') return { name: 'project.commitments', params: { projectId: event.project_id }, query: { item: event.subject_id } };
  if (event.subject_type === 'milestone') return { name: 'project.timeline', params: { projectId: event.project_id } };
  return { name: 'project.overview', params: { projectId: event.project_id } };
}

export function globalEventDay(event: GlobalTimelineEvent): string {
  return DateTime.fromISO(event.occurs_at, { zone: event.project_timezone }).toISODate() ?? '';
}
export function globalEventKey(event: GlobalTimelineEvent): string {
  return [event.project_id, event.event_type, event.subject_id, event.occurs_at, event.occurrence_date ?? ''].join(':');
}
export function globalEventOverdue(event: GlobalTimelineEvent): boolean {
  if (event.is_recurring_occurrence) return event.status === 'overdue';
  return DateTime.fromISO(event.occurs_at) < DateTime.now() && !['completed', 'paid', 'booked'].includes(event.status ?? '');
}
export function globalEventStatus(event: GlobalTimelineEvent): string {
  if (globalEventOverdue(event)) return 'Overdue';
  return event.status ? event.subject_type === 'commitment' && !event.is_recurring_occurrence ? executionStatusLabel(event.status) : presentLabel(event.status) : '';
}
export function globalEventSource(subject: string): { label: string; icon: IconName; tone: string; text: string } {
  if (subject === 'decision') return { label: 'Decision', icon: 'flag', tone: 'bg-accent-soft text-accent', text: 'text-accent' };
  if (subject === 'payment' || subject === 'payment_schedule') return { label: 'Payment', icon: 'coins', tone: 'bg-warning-soft text-warning', text: 'text-warning' };
  if (subject === 'commitment' || subject === 'task') return { label: 'Activity', icon: 'checkCircle', tone: 'bg-brand-soft text-brand', text: 'text-brand' };
  return { label: subject === 'milestone' ? 'Milestone' : 'Project', icon: subject === 'milestone' ? 'diamond' : 'projects', tone: 'bg-surface-subtle text-ink-soft', text: 'text-ink-soft' };
}
export function globalEventTypeLabel(type: string): string {
  const labels: Record<string, string> = {
    commitment_start: 'Activity starts', commitment_end: 'Activity ends', task_due: 'Activity due',
    recurring_commitment_due: 'Recurring Activity due', recurring_task_due: 'Recurring task due',
    decision_deadline: 'Decision deadline', decision_resolved: 'Decision resolved',
    payment_schedule_due: 'Payment schedule due', payment_due: 'Payment due', payment_made: 'Payment made',
    project_start: 'Project starts', project_end: 'Project ends', milestone: 'Milestone',
  };
  return labels[type] ?? presentLabel(type);
}
