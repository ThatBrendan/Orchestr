import { supabase } from "@/lib/supabase";
import { toAppError } from "@/lib/errors";
import type {
  AdminAuditEvent,
  AdminHealthSummary,
  AdminInvitation,
  AdminOverview,
  AdminProject,
  AdminProjectMember,
  AdminUser,
  AdminUserMembership,
} from "@/types/domain";

export async function isCurrentUserPlatformAdmin(userId: string): Promise<boolean> {
  const { data, error } = await supabase.from("users").select("platform_role").eq("id", userId).single();
  if (error) throw toAppError(error);
  return data.platform_role === "admin";
}

export async function getOverview(): Promise<AdminOverview> {
  const { data, error } = await supabase.rpc("get_admin_overview");
  if (error) throw toAppError(error);
  const row = data?.[0];
  if (!row) {
    throw new Error("Admin overview returned no data.");
  }
  return row;
}

export async function listUsers(search = ""): Promise<AdminUser[]> {
  let q = supabase.from("v_admin_users").select("*").order("created_at", { ascending: false }).limit(100);
  const term = search.trim();
  if (term) q = q.or(`display_name.ilike.%${term}%,email.ilike.%${term}%`);
  const { data, error } = await q;
  if (error) throw toAppError(error);
  return data ?? [];
}

export async function getUser(userId: string): Promise<AdminUser> {
  const { data, error } = await supabase.from("v_admin_users").select("*").eq("id", userId).single();
  if (error) throw toAppError(error);
  return data;
}

export async function listUserMemberships(userId: string): Promise<AdminUserMembership[]> {
  const { data, error } = await supabase
    .from("v_admin_user_memberships")
    .select("*")
    .eq("user_id", userId)
    .order("created_at", { ascending: false });
  if (error) throw toAppError(error);
  return data ?? [];
}

export async function listProjects(search = ""): Promise<AdminProject[]> {
  let q = supabase.from("v_admin_projects").select("*").order("updated_at", { ascending: false }).limit(100);
  const term = search.trim();
  if (term) q = q.ilike("name", `%${term}%`);
  const { data, error } = await q;
  if (error) throw toAppError(error);
  return data ?? [];
}

export async function getProject(projectId: string): Promise<AdminProject> {
  const { data, error } = await supabase.from("v_admin_projects").select("*").eq("id", projectId).single();
  if (error) throw toAppError(error);
  return data;
}

export async function listProjectMembers(projectId: string): Promise<AdminProjectMember[]> {
  const { data, error } = await supabase
    .from("v_admin_project_members")
    .select("*")
    .eq("project_id", projectId)
    .order("created_at", { ascending: true });
  if (error) throw toAppError(error);
  return data ?? [];
}

export async function getProjectHealthSummary(projectId: string): Promise<AdminHealthSummary> {
  const { data, error } = await supabase.rpc("get_admin_project_health_summary", { p_project: projectId });
  if (error) throw toAppError(error);
  const row = data?.[0];
  if (!row) {
    throw new Error("Admin project health summary returned no data.");
  }
  return row;
}

export async function listInvitations(search = ""): Promise<AdminInvitation[]> {
  let q = supabase.from("v_admin_invitations").select("*").order("created_at", { ascending: false }).limit(100);
  const term = search.trim();
  if (term) q = q.or(`email.ilike.%${term}%,project_name.ilike.%${term}%`);
  const { data, error } = await q;
  if (error) throw toAppError(error);
  return data ?? [];
}

export async function listAuditEvents(opts: { search?: string; userId?: string; projectId?: string } = {}): Promise<AdminAuditEvent[]> {
  let q = supabase.from("v_admin_audit_log").select("*").order("at", { ascending: false }).limit(100);
  if (opts.userId) q = q.eq("actor_user_id", opts.userId);
  if (opts.projectId) q = q.eq("project_id", opts.projectId);
  const term = opts.search?.trim();
  if (term) {
    q = q.or(`entity_type.ilike.%${term}%,project_name.ilike.%${term}%,actor_email.ilike.%${term}%`);
  }
  const { data, error } = await q;
  if (error) throw toAppError(error);
  return data ?? [];
}
