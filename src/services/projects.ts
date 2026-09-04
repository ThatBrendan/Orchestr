import { supabase } from "@/lib/supabase";
import { toAppError } from "@/lib/errors";
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
  const { data, error } = await supabase.from("projects").insert(input).select("id").single();
  if (error) throw toAppError(error);
  return data;
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
export async function setProjectStatus(projectId: string, status: ProjectStatus): Promise<Project> {
  const { data, error } = await supabase
    .from("projects")
    .update({ status })
    .eq("id", projectId)
    .select("*")
    .single();
  if (error) throw toAppError(error);
  return data;
}

/** Soft delete — organizer only. There is no hard-delete client path (docs/SECURITY_RLS.md §5.2). */
export async function softDeleteProject(projectId: string): Promise<void> {
  const { error } = await supabase.from("projects").update({ deleted_at: new Date().toISOString() }).eq(
    "id",
    projectId,
  );
  if (error) throw toAppError(error);
}
