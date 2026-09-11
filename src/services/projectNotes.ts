import { supabase } from "@/lib/supabase";
import { toAppError } from "@/lib/errors";
import type { ProjectNote } from "@/types/domain";

export interface NoteInput { title: string; body: string }

export async function listProjectNotes(projectId: string): Promise<ProjectNote[]> {
  const { data, error } = await supabase.from("v_project_notes").select("*")
    .eq("project_id", projectId).order("updated_at", { ascending: false }).order("id");
  if (error) throw toAppError(error);
  return data ?? [];
}
export async function createProjectNote(projectId: string, input: NoteInput) {
  const { data, error } = await supabase.rpc("create_project_note", {
    p_project: projectId, p_title: input.title, p_body: input.body,
  });
  if (error) throw toAppError(error);
  return data;
}
export async function updateProjectNote(noteId: string, input: NoteInput) {
  const { data, error } = await supabase.rpc("update_project_note", {
    p_note: noteId, p_title: input.title, p_body: input.body,
  });
  if (error) throw toAppError(error);
  return data;
}
export async function deleteProjectNote(noteId: string) {
  const { data, error } = await supabase.rpc("soft_delete_project_note", { p_note: noteId });
  if (error) throw toAppError(error);
  return data;
}
