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
