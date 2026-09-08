import { supabase } from "@/lib/supabase";
import { toAppError } from "@/lib/errors";
import type { GlobalTimelineEvent } from "@/types/derived";

/** Global calendar read model — one bounded query, no client-side timeline derivation. */
export async function listMyTimelineEvents(startIso: string, endIso: string): Promise<GlobalTimelineEvent[]> {
  const { data, error } = await supabase
    .from("v_my_timeline_events")
    .select("*")
    .gte("occurs_at", startIso)
    .lte("occurs_at", endIso)
    .order("occurs_at", { ascending: true });
  if (error) throw toAppError(error);
  return data ?? [];
}
