import { supabase } from "@/lib/supabase";
import { toAppError } from "@/lib/errors";
import type {
  ProjectFinancials,
  TimelineEvent,
  HealthFinding,
  HealthSummary,
  DashboardFinding,
} from "@/types/derived";

/** Derived read-models — all read-only (docs/DATABASE_SCHEMA.md §5). */

export async function getProjectFinancials(projectId: string): Promise<ProjectFinancials | null> {
  const { data, error } = await supabase
    .from("v_project_financials")
    .select("*")
    .eq("project_id", projectId)
    .maybeSingle();
  if (error) throw toAppError(error);
  return data;
}

export async function getProjectHealth(projectId: string): Promise<HealthFinding[]> {
  const { data, error } = await supabase.rpc("get_project_health", { p_project: projectId });
  if (error) throw toAppError(error);
  return (data ?? []) as HealthFinding[];
}

export async function getProjectHealthSummary(projectId: string): Promise<HealthSummary | null> {
  const { data, error } = await supabase.rpc("get_project_health_summary", { p_project: projectId });
  if (error) throw toAppError(error);
  return data?.[0] ?? null;
}

/** Dashboard "Needs attention", every project, ONE call (no client N+1). */
export async function getMyAttention(): Promise<DashboardFinding[]> {
  const { data, error } = await supabase.rpc("get_my_attention");
  if (error) throw toAppError(error);
  return (data ?? []) as DashboardFinding[];
}

export async function getUpcomingEvents(projectId: string, days = 14): Promise<TimelineEvent[]> {
  const now = new Date();
  const until = new Date(now.getTime() + days * 86_400_000);
  const { data, error } = await supabase
    .from("v_timeline_events")
    .select("*")
    .eq("project_id", projectId)
    .gte("occurs_at", now.toISOString())
    .lte("occurs_at", until.toISOString())
    .order("occurs_at", { ascending: true });
  if (error) throw toAppError(error);
  return data ?? [];
}
