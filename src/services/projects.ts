import { trackProductEvent } from "@/lib/analytics";
import { supabase } from "@/lib/supabase";
import { AppError, toAppError } from "@/lib/errors";
import type { MyProject, Project, ProjectInsert } from "@/types/domain";
import type { ProjectStatus, TablesUpdate } from "@/types/database";

/** Thin Supabase calls — one call + error mapping, no business logic (§6). */

export async function listMyProjects(): Promise<MyProject[]> {
  const { data, error } = await supabase.from("v_my_projects").select("*").order("next_event_at", {
    ascending: true,
    nullsFirst: false,
  });
  if (error) throw toAppError(error);
  return data ?? [];
}

export async function getProject(projectId: string): Promise<Project> {
  const { data, error } = await supabase
    .from("projects")
    .select("*")
    .eq("id", projectId)
    .is("deleted_at", null)
    .single();
  if (error) throw toAppError(error);
  return data;
}

export async function createProject(input: ProjectInsert): Promise<{ id: string }> {
  const { data, error } = await supabase.rpc("create_project", {
    p_name: input.name,
    p_timezone: input.timezone,
    p_currency: input.currency,
    p_profile: input.profile ?? "blank",
    p_starts_on: input.starts_on ?? null,
    p_ends_on: input.ends_on ?? null,
  });
  if (error) throw toAppError(error);
  trackProductEvent("project_created");
  return { id: data };
}

/** Editable field update — organizer only (enforced by RLS, docs/SECURITY_RLS.md §5.2). */
export async function updateProject(
  projectId: string,
  patch: Omit<TablesUpdate<"projects">, "status" | "deleted_at">,
): Promise<Project> {
  const { data, error } = await supabase.from("projects").update(patch).eq("id", projectId).select("*").single();
  if (error) throw toAppError(error);
  return data;
}

/** Status change (archive / unarchive / mark active or completed) — legality enforced by DB trigger. */
export async function setProjectStatus(projectId: string, status: ProjectStatus, from?: ProjectStatus): Promise<Project> {
  let query = supabase
    .from("projects")
    .update({ status })
    .eq("id", projectId);
  // Compare the state shown in the confirmation dialog. A stale reopen cannot
  // accidentally restore a project someone has since archived or deleted.
  if (from) query = query.eq("status", from);
  const { data, error } = await query.select("*").single();
  if (error) throw toAppError(error);
  return data;
}

/** Soft delete — organizer only. There is no hard-delete client path (docs/SECURITY_RLS.md §5.2). */
export async function softDeleteProject(projectId: string): Promise<void> {
  const { data, error } = await supabase.rpc("soft_delete_project", { p_project: projectId });
  if (error) throw toAppError(error);
  if (data !== projectId) throw new AppError("not_found", "Not found or cannot be deleted.");
}
