import { supabase } from "@/lib/supabase";
import { toAppError } from "@/lib/errors";
import type { Tables, TablesInsert, TablesUpdate } from "@/types/database";

export type Milestone = Tables<"milestones">;

/**
 * Milestones have no completion state by design (docs/BUSINESS_RULES.md MIL-4/MIL-5) —
 * "upcoming" vs "passed" is derived purely from `on_date` in the UI, never stored.
 */
export async function listMilestones(projectId: string): Promise<Milestone[]> {
  const { data, error } = await supabase
    .from("milestones")
    .select("*")
    .eq("project_id", projectId)
    .order("on_date", { ascending: true });
  if (error) throw toAppError(error);
  return data ?? [];
}

export async function createMilestone(input: TablesInsert<"milestones">): Promise<Milestone> {
  const { data, error } = await supabase.from("milestones").insert(input).select("*").single();
  if (error) throw toAppError(error);
  return data;
}

export async function updateMilestone(id: string, patch: TablesUpdate<"milestones">): Promise<Milestone> {
  const { data, error } = await supabase.from("milestones").update(patch).eq("id", id).select("*").single();
  if (error) throw toAppError(error);
  return data;
}

/** Hard delete — correct for milestones (docs/SECURITY_RLS.md §5.10). */
export async function deleteMilestone(id: string): Promise<void> {
  const { error } = await supabase.from("milestones").delete().eq("id", id);
  if (error) throw toAppError(error);
}
