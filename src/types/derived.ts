import type {
  Database,
  HealthFindingRow,
  MyAttentionRow,
  FindingSeverity,
} from "./database";

/** Derived — computed server-side, read-only (docs/DATABASE_SCHEMA.md §5). */
export type ProjectFinancials = Database["public"]["Views"]["v_project_financials"]["Row"];
export type TimelineEvent = Database["public"]["Views"]["v_timeline_events"]["Row"];
export type MemberDirectoryEntry = Database["public"]["Views"]["v_member_directory"]["Row"];

/**
 * `severity` is stored as text in the DB (DATABASE_SCHEMA D3) but only ever one of
 * four values — the service layer narrows it at the boundary.
 */
export type HealthFinding = Omit<HealthFindingRow, "severity"> & { severity: FindingSeverity };
export type HealthSummary = Database["public"]["Functions"]["get_project_health_summary"]["Returns"][number];

/** A finding tagged with its project — from public.get_my_attention() (one set-based call). */
export type DashboardFinding = Omit<MyAttentionRow, "severity"> & { severity: FindingSeverity };
