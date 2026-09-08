import { supabase } from "@/lib/supabase";
import { toAppError } from "@/lib/errors";
import type { GlobalPerson, GlobalPersonProject, GlobalPersonRow } from "@/types/derived";

function parseProjects(row: GlobalPersonRow): GlobalPersonProject[] {
  return Array.isArray(row.projects) ? (row.projects as unknown as GlobalPersonProject[]) : [];
}

/** Cross-project people directory derived from project_members, not a contacts table. */
export async function listMyPeople(): Promise<GlobalPerson[]> {
  const { data, error } = await supabase
    .from("v_my_people")
    .select("*")
    .order("display_name", { ascending: true });
  if (error) throw toAppError(error);
  return (data ?? []).map((row) => ({ ...row, projects: parseProjects(row) }));
}
