import { supabase } from "@/lib/supabase";
import { toAppError } from "@/lib/errors";
import type { ProjectMember } from "@/types/domain";
import type { MemberDirectoryEntry } from "@/types/derived";

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

/** Display-safe co-member list (name + avatar + role). */
export async function listMemberDirectory(projectId: string): Promise<MemberDirectoryEntry[]> {
  const { data, error } = await supabase
    .from("v_member_directory")
    .select("*")
    .eq("project_id", projectId)
    .order("display_name", { ascending: true });
  if (error) throw toAppError(error);
  return data ?? [];
}
