const LABELS: Record<string, string> = {
  active: "Active",
  archived: "Archived",
  booked: "Booked",
  cancelled: "Cancelled",
  completed: "Completed",
  create: "Created",
  deleted: "Deleted",
  delete: "Deleted",
  done: "Done",
  draft: "Draft",
  healthy: "Healthy",
  in_progress: "In progress",
  invited: "Invited",
  member: "Member",
  organizer: "Organizer",
  open: "Open",
  warning: "Needs attention",
  paid: "Paid",
  researching: "In progress",
  scheduled: "Scheduled",
  soft_delete: "Deleted",
  update: "Updated",
  viewer: "Viewer",
  waived: "Waived",
};

const ENTITY_LABELS: Record<string, string> = {
  commitment_participants: "Activity cost participants",
  cost_shares: "Cost shares",
  payments: "Payments",
  project_members: "Project members",
  projects: "Projects",
};

const INTERNAL_ACTIVITY_STATUSES = new Set([
  "idea",
  "researching",
  "confirmed",
  "booked",
  "open",
  "in_progress",
  "upcoming",
  "pending",
  "scheduled",
]);

export type SettlementState = "unpaid" | "partial" | "settled";

export function getSettlementPresentation(paidMinor: number, remainingMinor: number): {
  state: SettlementState;
  label: string;
  tone: "danger" | "amber" | "accent";
} {
  if (remainingMinor === 0) return { state: "settled", label: "Settled", tone: "accent" };
  if (paidMinor === 0 && remainingMinor > 0) return { state: "unpaid", label: "Unpaid", tone: "danger" };
  if (remainingMinor > 0) return { state: "partial", label: "Partially paid", tone: "amber" };
  return { state: "settled", label: "Credit", tone: "accent" };
}

export function formatDuration(value: number, unit: "day" | "hour" | "week"): string {
  return `${value} ${unit}${value === 1 ? "" : "s"}`;
}

export function userFacingActivityStatus(status: string | null | undefined): string {
  const value = (status ?? "").toLowerCase();
  if (["completed", "done", "complete"].includes(value)) return "Complete";
  if (["cancelled", "canceled", "skipped", "declined"].includes(value)) return "Cancelled";
  if (["overdue"].includes(value)) return "Overdue";
  if (INTERNAL_ACTIVITY_STATUSES.has(value)) return "Pending";
  return presentLabel(value) || "Pending";
}

export function normalizeHealthCopy(value: string | null | undefined): string {
  if (!value) return "";
  let text = value;
  text = text.replace(/\bstill\s+unconfirmed\b/gi, "");
  text = text.replace(/\bunconfirmed\b/gi, "pending");
  text = text.replace(/\bidea\b/gi, "pending");
  text = text.replace(/\bresearching\b/gi, "pending");
  text = text.replace(/\bconfirmed\b/gi, "pending");
  text = text.replace(/\bbooked\b/gi, "pending");
  text = text.replace(/\bin_progress\b/gi, "pending");
  text = text.replace(/\bopen\b/gi, "pending");
  text = text.replace(/\bstill\s+pending\b/gi, "pending");
  text = text.replace(/\b(.*)\s+is\s+pending\s+happens soon\.?/gi, "This activity is pending.");
  text = text.replace(/\b(.*)\s+is\s+still\s+.*\s+but\s+happens\s+soon\.?/gi, "This activity is pending.");
  text = text.replace(/\b(.*)\s+is\s+pending\s+.*Due\b/gi, "This activity is pending.");
  text = text.replace(/\bProjected spend\b/gi, "Spent so far");
  text = text.replace(/\bPlanned spend\b/gi, "Budget");
  text = text.replace(/\bCommitted spend\b/gi, "Spent so far");
  text = text.replace(/\bConfirm it, complete it, or cancel it\b/i, "Review activity");
  text = text.replace(/\bReview this item\b/i, "Review activity");
  text = text.replace(/\bitem\b/gi, "activity");
  text = text.replace(/\barea\b/gi, "category");
  text = text.replace(/\bcommitment\b/gi, "activity");
  text = text.replace(/\s{2,}/g, " ").trim();
  return text;
}

export function relativeDueText(params: Record<string, unknown> | null | undefined): string | null {
  const firstValue = ("starts_at" in (params ?? {}) ? params?.starts_at : null)
    ?? ("due_on" in (params ?? {}) ? params?.due_on : null)
    ?? ("occurrence_date" in (params ?? {}) ? params?.occurrence_date : null)
    ?? ("date" in (params ?? {}) ? params?.date : null)
    ?? ("due_date" in (params ?? {}) ? params?.due_date : null)
    ?? ("starts_on" in (params ?? {}) ? params?.starts_on : null)
    ?? ("ends_on" in (params ?? {}) ? params?.ends_on : null);
  if (!firstValue || typeof firstValue !== "string") return null;
  const date = new Date(firstValue);
  if (Number.isNaN(date.getTime())) return null;
  const diffDays = Math.round((date.getTime() - Date.now()) / 86_400_000);
  if (diffDays === 0) return "Due today.";
  if (diffDays === 1) return "Due tomorrow.";
  if (diffDays > 1) return `Due in ${diffDays} days.`;
  if (diffDays === -1) return "Due yesterday.";
  return `Overdue by ${Math.abs(diffDays)} days.`;
}

export function presentLabel(value: string | null | undefined): string {
  if (!value) return "-";
  return LABELS[value] ?? value.replace(/_/g, " ").replace(/\b\w/g, (letter) => letter.toUpperCase());
}

export function presentEntity(value: string | null | undefined): string {
  if (!value) return "-";
  return ENTITY_LABELS[value] ?? presentLabel(value);
}

export function presentAuditAction(action: string | null | undefined, entity?: string | null): string {
  if (action === "create" && entity === "commitment_participants") return "Added participant";
  if (action === "soft_delete" || action === "soft-delete") return "Deleted";
  return presentLabel(action);
}