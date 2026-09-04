import { supabase } from "@/lib/supabase";
import { toAppError } from "@/lib/errors";
import type {
  ProjectFinancials,
  TimelineEvent,
  HealthFinding,
  HealthSummary,
  DashboardFinding,
  CommitmentFinancials,
  BudgetCategoryActual,
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

/** Per-commitment outstanding balance etc. — always read, never recomputed in Vue. */
export async function getCommitmentFinancials(commitmentId: string): Promise<CommitmentFinancials | null> {
  const { data, error } = await supabase
    .from("v_commitment_financials")
    .select("*")
    .eq("commitment_id", commitmentId)
    .maybeSingle();
  if (error) throw toAppError(error);
  return data;
}

/** Per-category budget target vs. actual (BUD-10) — always read, never recomputed in Vue. */
export async function getBudgetCategoryActuals(projectId: string): Promise<BudgetCategoryActual[]> {
  const { data, error } = await supabase
    .from("v_budget_category_actuals")
    .select("*")
    .eq("project_id", projectId)
    .order("kind", { ascending: true });
  if (error) throw toAppError(error);
  return data ?? [];
}

/** Full derived project timeline (no date bound) — commitments, payments, tasks, milestones, boundaries. */
export async function getFullTimeline(projectId: string): Promise<TimelineEvent[]> {
  const { data, error } = await supabase
    .from("v_timeline_events")
    .select("*")
    .eq("project_id", projectId)
    .order("occurs_at", { ascending: true });
  if (error) throw toAppError(error);
  return data ?? [];
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
