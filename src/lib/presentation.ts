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
  commitment_participants: "Activity participants",
  cost_shares: "Cost shares",
  payments: "Payments",
  project_members: "Project members",
  projects: "Projects",
};

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