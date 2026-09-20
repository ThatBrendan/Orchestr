import { supabase } from "@/lib/supabase";
import { toAppError } from "@/lib/errors";
import { config } from "@/config";

export type JoinState = { state: "unavailable" | "sign_in" | "eligible" | "pending" } | { state: "member"; project_id: string };
export interface AccessRequest { id: string; display_name: string; requested_at: string }
export interface JoinAccess { active: boolean; link: string | null; requests: AccessRequest[]; pending_count: number }
export async function resolveJoin(token: string): Promise<JoinState> {
  const { data, error } = await supabase.rpc("resolve_project_join_link", { p_token: token });
  if (error) throw toAppError(error);
  return data as unknown as JoinState;
}
export async function requestAccess(token: string): Promise<JoinState> {
  const { data, error } = await supabase.rpc("request_project_access", { p_token: token });
  if (error) throw toAppError(error);
  return data as unknown as JoinState;
}
export async function getJoinAccess(project: string, offset = 0): Promise<JoinAccess> {
  const { data, error } = await supabase.rpc("get_project_join_access", { p_project: project, p_offset: offset });
  if (error) throw toAppError(error);
  const result = data as unknown as Omit<JoinAccess, "link"> & { token: string | null };
  return { active: result.active, requests: result.requests, pending_count: result.pending_count, link: result.active && result.token ? new URL(`/join/${result.token}`, config.appUrl).href : null };
}
export async function regenerateJoinLink(project: string) {
  const { data, error } = await supabase.rpc("regenerate_project_join_link", { p_project: project });
  if (error) throw toAppError(error);
  return new URL(`/join/${data}`, config.appUrl).href;
}
export async function disableJoinLink(project: string) {
  const { error } = await supabase.rpc("disable_project_join_link", { p_project: project });
  if (error) throw toAppError(error);
}
export async function reviewJoinRequest(request: string, approve: boolean) {
  const { error } = await supabase.rpc("review_project_join_request", { p_request: request, p_approve: approve });
  if (error) throw toAppError(error);
}
