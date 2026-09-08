import type {
  Database,
  HealthFindingRow,
  MyAttentionRow,
  FindingSeverity,
  MemberRole,
  MemberStatus,
} from "./database";

/** Derived — computed server-side, read-only (docs/DATABASE_SCHEMA.md §5). */
export type ProjectFinancials = Database["public"]["Views"]["v_project_financials"]["Row"];
export type CommitmentFinancials = Database["public"]["Views"]["v_commitment_financials"]["Row"];
export type BudgetCategoryActual = Database["public"]["Views"]["v_budget_category_actuals"]["Row"];
export type TimelineEvent = Database["public"]["Views"]["v_timeline_events"]["Row"];
export type GlobalTimelineEvent = Database["public"]["Views"]["v_my_timeline_events"]["Row"];
export type MemberDirectoryEntry = Database["public"]["Views"]["v_member_directory"]["Row"];
export type GlobalPersonRow = Database["public"]["Views"]["v_my_people"]["Row"];
export interface GlobalPersonProject {
  project_id: string;
  project_name: string;
  member_id: string;
  role: MemberRole;
  status: MemberStatus;
}
export type GlobalPerson = Omit<GlobalPersonRow, "projects"> & { projects: GlobalPersonProject[] };

/**
 * `severity` is stored as text in the DB (DATABASE_SCHEMA D3) but only ever one of
 * four values — the service layer narrows it at the boundary.
 */
export type HealthFinding = Omit<HealthFindingRow, "severity"> & { severity: FindingSeverity };
export type HealthSummary = Database["public"]["Functions"]["get_project_health_summary"]["Returns"][number];

/** A finding tagged with its project — from public.get_my_attention() (one set-based call). */
export type DashboardFinding = Omit<MyAttentionRow, "severity"> & { severity: FindingSeverity };
