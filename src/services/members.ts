import { supabase } from "@/lib/supabase";
import { toAppError } from "@/lib/errors";
import type { ProjectMember } from "@/types/domain";
import type { MemberDirectoryEntry } from "@/types/derived";
import type { MemberRole } from "@/types/database";

/** The caller's own membership row for a project (drives role/permissions). */
export async function getMyMembership(projectId: string, userId: string): Promise<ProjectMember | null> {
  const { data, error } = await supabase
    .from("project_members")
    .select("*")
    .eq("project_id", projectId)
    .eq("user_id", userId)
    .eq("status", "active")
    .is("deleted_at", null)
    .maybeSingle();
  if (error) throw toAppError(error);
  return data;
}

/** Display-safe co-member list (name + avatar + role). Includes invited + active + removed. */
export async function listMemberDirectory(projectId: string): Promise<MemberDirectoryEntry[]> {
  const { data, error } = await supabase
    .from("v_member_directory")
    .select("*")
    .eq("project_id", projectId)
    .order("display_name", { ascending: true });
  if (error) throw toAppError(error);
  return data ?? [];
}

/**
 * Invite a person by email — routed through the `invitations-send` Edge Function.
 * `invitations` has no client INSERT policy (docs/SECURITY_RLS.md §5.4); this is the only path.
 */
export async function inviteMember(
  projectId: string,
  email: string,
  role: Extract<MemberRole, "member" | "viewer">,
): Promise<{ invitationId: string; emailed: boolean }> {
  const { data, error } = await supabase.functions.invoke<{ invitationId: string; emailed: boolean }>(
    "invitations-send",
    { body: { projectId, email, role } },
  );
  if (error) throw toAppError(error);
  if (!data) throw toAppError(new Error("The invitation service did not return a result."));
  return data;
}

/** Organizer-only role change on an existing member row (docs/SECURITY_RLS.md §5.3). */
export async function updateMemberRole(memberId: string, role: MemberRole): Promise<ProjectMember> {
  const { data, error } = await supabase
    .from("project_members")
    .update({ role })
    .eq("id", memberId)
    .select("*")
    .single();
  if (error) throw toAppError(error);
  return data;
}

/** Soft removal — organizer only; blocked by `tg_last_organizer_guard` if it would leave zero organizers. */
export async function removeMember(memberId: string): Promise<ProjectMember> {
  const { data, error } = await supabase
    .from("project_members")
    .update({ status: "removed" })
    .eq("id", memberId)
    .select("*")
    .single();
  if (error) throw toAppError(error);
  return data;
}

/** Reinstate a previously removed member (organizer only). */
export async function reactivateMember(memberId: string): Promise<ProjectMember> {
  const { data, error } = await supabase
    .from("project_members")
    .update({ status: "active" })
    .eq("id", memberId)
    .select("*")
    .single();
  if (error) throw toAppError(error);
  return data;
}
