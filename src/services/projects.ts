import { supabase } from "@/lib/supabase";
import { toAppError } from "@/lib/errors";
import type { MyProject, Project, ProjectInsert } from "@/types/domain";

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
