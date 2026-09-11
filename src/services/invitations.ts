import { supabase } from "@/lib/supabase";
import { toAppError } from "@/lib/errors";
import type { MemberRole } from "@/types/database";

export interface InvitationPreview {
  project_name: string;
  inviter_name: string | null;
  role: MemberRole;
  status: string;
}

export async function getInvitation(token: string): Promise<InvitationPreview | null> {
  const { data, error } = await supabase.rpc("get_invitation", { p_token: token });
  if (error) throw toAppError(error);
  return data?.[0] ?? null;
}

/** Returns the project_id joined. */
export async function acceptInvitation(token: string): Promise<string> {
  const { data, error } = await supabase.rpc("accept_invitation", { p_token: token });
  if (error) throw toAppError(error);
  return data as string;
}

export async function listMyInvitations() {
  const { data, error } = await supabase.rpc("list_my_invitations");
  if (error) throw toAppError(error);
  return data ?? [];
}

export async function declineInvitation(token: string) {
  const { data, error } = await supabase.rpc("decline_invitation", { p_token: token });
  if (error) throw toAppError(error);
  return data;
}

export async function listProjectInvitations(projectId: string) {
  const { data, error } = await supabase.from("invitations")
    .select("id,email,role,status,created_at,expires_at").eq("project_id", projectId)
    .neq("status", "accepted").order("created_at", { ascending: false });
  if (error) throw toAppError(error);
  return (data ?? []).map((i) => ({ ...i, status: i.status === "pending" && Date.parse(i.expires_at) <= Date.now() ? "expired" : i.status }));
}
