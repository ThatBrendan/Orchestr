import { supabase } from "@/lib/supabase";
import { AppError, toAppError } from "@/lib/errors";
import type { Tables, TablesInsert, TablesUpdate } from "@/types/database";

export type Milestone = Tables<"milestones">;

/**
 * Milestones have no completion state by design (docs/PRODUCT_ARCHITECTURE.md) —
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

/** Hard delete — correct for milestones (docs/BACKEND_SECURITY_AND_DATA.md). */
export async function deleteMilestone(id: string): Promise<void> {
  const { error, count } = await supabase.from("milestones").delete({ count: "exact" }).eq("id", id);
  if (error) throw toAppError(error);
  if (count !== 1) throw new AppError("not_found", "Not found or cannot be removed.");
}
