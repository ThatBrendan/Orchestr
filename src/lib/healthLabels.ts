/**
 * Short display titles for each deterministic health rule code
 * (docs/BUSINESS_RULES.md §9.2 — HLT-1..HLT-17). Titles only — the full
 * human-readable sentence for a specific finding is always `finding.message`,
 * computed server-side; nothing here re-derives business meaning.
 */
export const HEALTH_CODE_TITLES: Record<string, string> = {
  missing_owner: "Missing owner",
  orphaned_owner: "Owner has left the project",
  payment_overdue: "Overdue payment",
  payment_due_soon: "Payment due soon",
  unconfirmed_near_date: "Still unconfirmed",
  commitment_inactive: "No recent activity",
  missing_cost: "Missing cost",
  budget_exceeded: "Budget exceeded",
  category_over_target: "Category over target",
  schedule_conflict: "Scheduling conflict",
  tight_connection: "Tight connection",
  task_overdue: "Overdue task",
  task_unassigned_due_soon: "Unassigned task due soon",
  outside_project_dates: "Outside project dates",
  unallocated_cost: "Cost not split",
  on_budget: "On budget",
  activity_occurrence_overdue: "Overdue occurrence",
  task_occurrence_overdue: "Overdue task occurrence",
};

export function healthCodeTitle(code: string): string {
  return HEALTH_CODE_TITLES[code] ?? code.replace(/_/g, " ");
}
