import type { ActivityType, CommitmentStatus, ProjectProfile } from "@/types/database";

export interface ActivityWorkflowAction {
  to: CommitmentStatus;
  label: string;
}

export interface ActivityWorkflow {
  value: ActivityType;
  label: string;
  description: string;
  defaultStatus: CommitmentStatus;
  statusLabels: Record<CommitmentStatus, string>;
  actions: Record<CommitmentStatus, ActivityWorkflowAction[]>;
  preferredFields: {
    owner: boolean;
    endDate: boolean;
    location: boolean;
    supplier: boolean;
    booking: boolean;
    cost: boolean;
    payments: boolean;
  };
}

// Execution presentation does not change the persisted status or its financial/Health meaning.
// Confirmed/booked records represent progressed work, not completed work. Booking is shown separately.
const EXECUTION_LABELS: Record<CommitmentStatus, string> = {
  idea: "Not started", researching: "In progress", confirmed: "In progress",
  booked: "In progress", completed: "Completed", cancelled: "Cancelled",
};
const EXECUTION_ACTIONS: Record<CommitmentStatus, ActivityWorkflowAction[]> = {
  idea: [{ to: "researching", label: "Start" }, { to: "completed", label: "Complete" }],
  researching: [{ to: "completed", label: "Complete" }],
  confirmed: [{ to: "completed", label: "Complete" }],
  booked: [{ to: "completed", label: "Complete" }],
  completed: [], cancelled: [],
};
// Existing booking transition rules require booked before completed; never invent booking history.
const BOOKING_EXECUTION_ACTIONS: Record<CommitmentStatus, ActivityWorkflowAction[]> = {
  ...EXECUTION_ACTIONS,
  idea: [{ to: "researching", label: "Start" }],
  researching: [], confirmed: [],
};

export function bookingStatusLabel(status: CommitmentStatus, confirmed: boolean): string {
  if (status === "booked" || status === "completed" || confirmed) return "Booked";
  return status === "confirmed" ? "Ready to book" : "Not booked";
}

export function bookingStatusActions(status: CommitmentStatus): ActivityWorkflowAction[] {
  if (status === "researching") return [{ to: "confirmed", label: "Confirm booking" }];
  if (status === "confirmed") return [{ to: "booked", label: "Mark booked" }];
  return [];
}

export function secondaryActivityActions(type: ActivityType, status: CommitmentStatus): ActivityWorkflowAction[] {
  if (status === "completed") return [{ to: type === "booking" ? "booked" : "researching", label: "Reopen activity" }];
  if (status === "cancelled") return [{ to: "researching", label: "Restore activity" }];
  return [{ to: "cancelled", label: "Cancel activity" }];
}

export function executionStatusLabel(status: string): string {
  return EXECUTION_LABELS[status as CommitmentStatus] ?? status;
}

export const ACTIVITY_WORKFLOWS: ActivityWorkflow[] = [
  {
    value: "task",
    label: "Task / Action",
    description: "A piece of work with an owner, due date and outcome.",
    defaultStatus: "idea",
    statusLabels: EXECUTION_LABELS,
    actions: EXECUTION_ACTIONS,
    preferredFields: { owner: true, endDate: false, location: false, supplier: false, booking: false, cost: false, payments: false },
  },
  {
    value: "booking",
    label: "Booking",
    description: "A reservation or supplier booking to confirm and track.",
    defaultStatus: "idea",
    statusLabels: EXECUTION_LABELS,
    actions: BOOKING_EXECUTION_ACTIONS,
    preferredFields: { owner: true, endDate: true, location: true, supplier: true, booking: true, cost: true, payments: true },
  },
  {
    value: "purchase",
    label: "Purchase",
    description: "Something to buy, price up, pay for or reimburse.",
    defaultStatus: "idea",
    statusLabels: EXECUTION_LABELS,
    actions: EXECUTION_ACTIONS,
    preferredFields: { owner: true, endDate: false, location: false, supplier: true, booking: false, cost: true, payments: true },
  },
  {
    value: "event",
    label: "Meeting / Event",
    description: "A scheduled moment with time, place and participants.",
    defaultStatus: "idea",
    statusLabels: EXECUTION_LABELS,
    actions: EXECUTION_ACTIONS,
    preferredFields: { owner: true, endDate: true, location: true, supplier: false, booking: false, cost: false, payments: false },
  },
  {
    value: "other",
    label: "Other",
    description: "A flexible activity without booking-specific behaviour.",
    defaultStatus: "idea",
    statusLabels: EXECUTION_LABELS,
    actions: EXECUTION_ACTIONS,
    preferredFields: { owner: true, endDate: false, location: false, supplier: false, booking: false, cost: false, payments: false },
  },
];

export const DEFAULT_ACTIVITY_TYPE: ActivityType = "other";

export const PROJECT_PROFILE_DEFAULT_ACTIVITY_TYPE: Record<ProjectProfile, ActivityType> = {
  group_trip: "booking",
  wedding_event: "booking",
  house_move: "task",
  recurring_process: "task",
  team_project: "task",
  launch: "task",
  blank: "other",
};

export function activityWorkflow(type: ActivityType | null | undefined): ActivityWorkflow {
  return ACTIVITY_WORKFLOWS.find((workflow) => workflow.value === type) ?? activityWorkflow(DEFAULT_ACTIVITY_TYPE);
}

export function activityTypeLabel(type: ActivityType | null | undefined): string {
  return activityWorkflow(type).label;
}

export function defaultActivityTypeForProjectProfile(profile: ProjectProfile | null | undefined): ActivityType {
  return profile ? PROJECT_PROFILE_DEFAULT_ACTIVITY_TYPE[profile] ?? DEFAULT_ACTIVITY_TYPE : DEFAULT_ACTIVITY_TYPE;
}

export function commitmentStatusLabel(type: ActivityType | null | undefined, status: CommitmentStatus): string {
  return activityWorkflow(type).statusLabels[status];
}

export function commitmentStatusActions(type: ActivityType | null | undefined, status: CommitmentStatus): ActivityWorkflowAction[] {
  return activityWorkflow(type).actions[status];
}
