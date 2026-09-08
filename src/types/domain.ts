import type { Database, MemberRole } from "./database";

type T = Database["public"]["Tables"];
type V = Database["public"]["Views"];

export type UserProfile = T["users"]["Row"];
export type Project = T["projects"]["Row"];
export type ProjectInsert = T["projects"]["Insert"];
export type ProjectMember = T["project_members"]["Row"];

/** Row of v_my_projects — dashboard / projects list. */
export type MyProject = V["v_my_projects"]["Row"];
export type AdminUser = V["v_admin_users"]["Row"];
export type AdminUserMembership = V["v_admin_user_memberships"]["Row"];
export type AdminProject = V["v_admin_projects"]["Row"];
export type AdminProjectMember = V["v_admin_project_members"]["Row"];
export type AdminInvitation = V["v_admin_invitations"]["Row"];
export type AdminAuditEvent = V["v_admin_audit_log"]["Row"];
export type AdminOverview = Database["public"]["Functions"]["get_admin_overview"]["Returns"][number];
export type AdminHealthSummary = Database["public"]["Functions"]["get_admin_project_health_summary"]["Returns"][number];

/** Ergonomic view for the current-project context. */
export interface ProjectContext {
  projectId: string;
  role: MemberRole;
  memberId: string | null;
  project: Pick<Project, "id" | "name" | "status" | "starts_on" | "ends_on" | "timezone" | "currency">;
}

/** Money is always minor units in the project's single currency. */
export type Minor = number;
