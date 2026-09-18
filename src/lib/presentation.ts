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