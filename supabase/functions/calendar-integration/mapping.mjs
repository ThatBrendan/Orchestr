/** Whitelist-based projection: no provider payload can mutate a domain resource. */
export function mapEvent(entry, appUrl) {
  const base = new URL(appUrl).origin;
  const decision = entry.source_type === 'decision';
  const payment = entry.source_type === 'payment_schedule';
  // Explicit product policy: do not invent a timed Activity duration.
  if (!entry.all_day && !entry.end_at && !decision) return null;
  const url = new URL(decision ? `/app/projects/${entry.project_id}/decisions/${entry.source_id}` : `/app/projects/${entry.project_id}/areas`, base);
  if (!decision) url.searchParams.set('commitment', entry.activity_id);
  if (payment) url.searchParams.set('section', 'payments');
  if (entry.occurrence_date) url.searchParams.set('occurrence', entry.occurrence_date);
  const event = {
    summary: `${decision ? 'Decision deadline — ' : payment ? 'Payment due — ' : ''}${entry.title}`,
    description: `Managed by Orchestrio.\nStatus: ${entry.status}\nOpen in Orchestrio: ${url.href}`,
    source: { title: 'Orchestrio', url: url.href },
    extendedProperties: { private: { orchestrio_source: entry.entry_id } },
    status: 'confirmed', visibility: 'private', transparency: 'transparent', reminders: { useDefault: false },
  };
  if (entry.all_day) {
    event.start = { date: entry.start_date };
    event.end = { date: new Date(Date.parse((entry.end_date ?? entry.start_date) + 'T00:00:00Z') + 86400000).toISOString().slice(0, 10) };
  } else {
    event.start = { dateTime: entry.start_at, timeZone: entry.timezone };
    event.end = { dateTime: entry.end_at ?? new Date(Date.parse(entry.start_at) + 1800000).toISOString(), timeZone: entry.timezone };
  }
  return event;
}
