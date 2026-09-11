import { supabase } from "@/lib/supabase";
import { toAppError } from "@/lib/errors";

export async function setProjectBudget(projectId: string, amount: number | null) {
  const { error } = await supabase.rpc("set_project_budget", { p_project: projectId, p_amount: amount });
  if (error) throw toAppError(error);
}
export async function setActualCost(id: string, amount: number | null, complete: boolean) {
  const { error } = await supabase.rpc("set_commitment_actual_cost", { p_commitment: id, p_amount: amount, p_complete: complete });
  if (error) throw toAppError(error);
}
