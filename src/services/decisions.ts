import { supabase } from "@/lib/supabase";
import { toAppError } from "@/lib/errors";
import type { Decision, DecisionInput } from "@/types/decisions";
export async function listDecisions(project: string, decision?: string): Promise<Decision[]> {
  const { data, error } = await supabase.rpc("get_decisions", { p_project: project, p_decision: decision });
  if (error) throw toAppError(error);
  return data as unknown as Decision[];
}
export async function saveDecision(project: string, id: string, input: DecisionInput, editing: boolean) {
  const fields = { p_title: input.title, p_description: input.description, p_deadline: input.deadline, p_options: input.options };
  const { error } = editing
    ? await supabase.rpc("edit_decision", { p_decision: id, ...fields })
    : await supabase.rpc("create_decision", { p_project: project, p_id: id, ...fields });
  if (error) throw toAppError(error);
  return id;
}
export async function voteDecision(id: string, option: string | null) {
  const { error } = await supabase.rpc("cast_decision_vote", { p_decision: id, p_option: option });
  if (error) throw toAppError(error);
}
export async function resolveDecision(id: string, option: string) {
  const { error } = await supabase.rpc("resolve_decision", { p_decision: id, p_option: option });
  if (error) throw toAppError(error);
}
export async function deleteDecision(id: string) {
  const { error } = await supabase.rpc("soft_delete_decision", { p_decision: id });
  if (error) throw toAppError(error);
}
export async function convertDecision(id: string, category: string, type: string) {
  const { data, error } = await supabase.rpc("convert_decision_to_activity", { p_decision: id, p_category: category, p_activity_type: type });
  if (error) throw toAppError(error);
  return data;
}
