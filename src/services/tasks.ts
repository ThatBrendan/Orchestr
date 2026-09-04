import { supabase } from "@/lib/supabase";
import { toAppError } from "@/lib/errors";
import type { Tables, TablesInsert, TablesUpdate, Enums } from "@/types/database";

export type Task = Tables<"tasks">;
export type TaskStatus = Enums<"task_status">;

/** All non-deleted tasks for a project (docs/SECURITY_RLS.md §5.9). */
export async function listTasks(projectId: string): Promise<Task[]> {
  const { data, error } = await supabase
    .from("tasks")
    .select("*")
    .eq("project_id", projectId)
    .order("due_on", { ascending: true, nullsFirst: false })
    .order("created_at", { ascending: true });
  if (error) throw toAppError(error);
  return data ?? [];
}

export async function createTask(input: TablesInsert<"tasks">): Promise<Task> {
  const { data, error } = await supabase.from("tasks").insert(input).select("*").single();
  if (error) throw toAppError(error);
  return data;
}

export async function updateTask(
  id: string,
  patch: Omit<TablesUpdate<"tasks">, "status" | "deleted_at">,
): Promise<Task> {
  const { data, error } = await supabase.from("tasks").update(patch).eq("id", id).select("*").single();
  if (error) throw toAppError(error);
  return data;
}

export async function setTaskStatus(id: string, status: TaskStatus): Promise<Task> {
  const { data, error } = await supabase.from("tasks").update({ status }).eq("id", id).select("*").single();
  if (error) throw toAppError(error);
  return data;
}

/** Soft delete — organizer, creator, or assignee only (docs/SECURITY_RLS.md §5.9). */
export async function softDeleteTask(id: string): Promise<void> {
  const { error } = await supabase.from("tasks").update({ deleted_at: new Date().toISOString() }).eq("id", id);
  if (error) throw toAppError(error);
}
