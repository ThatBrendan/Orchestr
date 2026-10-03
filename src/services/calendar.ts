import { supabase } from "@/lib/supabase";
import { toAppError } from "@/lib/errors";
import type { GlobalTimelineEvent } from "@/types/derived";

/** Global calendar read model — one bounded query, no client-side timeline derivation. */
export async function listMyTimelineEvents(startIso: string, endIso: string): Promise<GlobalTimelineEvent[]> {
  const { data, error } = await supabase.rpc("get_my_timeline_events", {
    p_start: startIso,
    p_end: endIso,
  });
  if (error) throw toAppError(error);
  return (data ?? []).sort((a, b) => a.occurs_at.localeCompare(b.occurs_at));
}

/** Source-authoritative execution projection; range is [start,end) in project dates. */
export async function listProjectCalendar(project: string, start: string, end: string) {
  const { data, error } = await supabase.rpc('get_project_calendar', {
    p_project: project, p_range_start: start, p_range_end: end,
  });
  if (error) throw toAppError(error);
  return data ?? [];
}
