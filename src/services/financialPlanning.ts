import type { Json } from "@/types/database";
import { supabase } from "@/lib/supabase";
import { toAppError } from "@/lib/errors";

export async function setProjectBudget(projectId: string, amount: number | null) {
  const { error } = await supabase.rpc("set_project_budget", { p_project: projectId, p_amount: amount });
  if (error) throw toAppError(error);
}
export async function setActualCost(id: string, amount: number | null, complete: boolean, split?: Json) {
  const { error } = await supabase.rpc("set_actual_cost_with_split", { p_commitment: id, p_amount: amount, p_complete: complete, p_split: split ?? null });
  if (error) throw toAppError(error);
}
