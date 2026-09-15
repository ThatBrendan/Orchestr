import type { ProjectStatus } from "@/types/database";
export type ProjectGroup = "active" | "past" | "archived";
export function projectGroup(status: ProjectStatus | null): ProjectGroup | null {
  if (status === "draft" || status === "active") return "active";
  if (status === "completed") return "past";
  if (status === "archived") return "archived";
  return null;
}
