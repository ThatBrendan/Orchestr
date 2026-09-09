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

const NON_BOOKING_ACTIONS: Record<CommitmentStatus, ActivityWorkflowAction[]> = {
  idea: [
    { to: "researching", label: "Start" },
    { to: "completed", label: "Complete" },
    { to: "cancelled", label: "Cancel" },
  ],
  researching: [
    { to: "idea", label: "Mark not started" },
    { to: "completed", label: "Complete" },
    { to: "cancelled", label: "Cancel" },
  ],
  confirmed: [
    { to: "researching", label: "Reopen" },
    { to: "completed", label: "Complete" },
    { to: "cancelled", label: "Cancel" },
  ],
  booked: [
    { to: "confirmed", label: "Back to confirmed" },
    { to: "completed", label: "Complete" },
    { to: "cancelled", label: "Cancel" },
  ],
  completed: [{ to: "researching", label: "Reopen" }],
  cancelled: [{ to: "researching", label: "Reinstate" }],
};

const PURCHASE_ACTIONS: Record<CommitmentStatus, ActivityWorkflowAction[]> = {
  idea: [
    { to: "researching", label: "Start pricing" },
    { to: "completed", label: "Complete" },
    { to: "cancelled", label: "Cancel" },
  ],
  researching: [
    { to: "idea", label: "Back to idea" },
    { to: "confirmed", label: "Mark purchased" },
    { to: "cancelled", label: "Cancel" },
  ],
  confirmed: [
    { to: "researching", label: "Reopen" },
    { to: "completed", label: "Complete" },
    { to: "cancelled", label: "Cancel" },
  ],
  booked: [
    { to: "confirmed", label: "Back to purchased" },
    { to: "completed", label: "Complete" },
    { to: "cancelled", label: "Cancel" },
  ],
  completed: [{ to: "researching", label: "Reopen" }],
  cancelled: [{ to: "researching", label: "Reinstate" }],
};

const EVENT_ACTIONS: Record<CommitmentStatus, ActivityWorkflowAction[]> = {
  idea: [
    { to: "researching", label: "Start planning" },
    { to: "completed", label: "Complete" },
    { to: "cancelled", label: "Cancel" },
  ],
  researching: [
    { to: "idea", label: "Back to idea" },
    { to: "confirmed", label: "Confirm" },
    { to: "cancelled", label: "Cancel" },
  ],
  confirmed: [
    { to: "researching", label: "Reopen planning" },
    { to: "completed", label: "Complete" },
    { to: "cancelled", label: "Cancel" },
  ],
  booked: [
    { to: "confirmed", label: "Back to confirmed" },
    { to: "completed", label: "Complete" },
    { to: "cancelled", label: "Cancel" },
  ],
  completed: [{ to: "researching", label: "Reopen" }],
  cancelled: [{ to: "researching", label: "Reinstate" }],
};

const BOOKING_ACTIONS: Record<CommitmentStatus, ActivityWorkflowAction[]> = {
  idea: [
    { to: "researching", label: "Move to researching" },
    { to: "cancelled", label: "Cancel" },
  ],
  researching: [
    { to: "idea", label: "Back to idea" },
    { to: "confirmed", label: "Confirm" },
    { to: "cancelled", label: "Cancel" },
  ],
  confirmed: [
    { to: "researching", label: "Back to researching" },
    { to: "booked", label: "Mark booked" },
    { to: "cancelled", label: "Cancel" },
  ],
  booked: [
    { to: "confirmed", label: "Back to confirmed" },
    { to: "completed", label: "Mark completed" },
    { to: "cancelled", label: "Cancel" },
  ],
  completed: [{ to: "booked", label: "Reopen" }],
  cancelled: [{ to: "researching", label: "Reinstate" }],
};

const BASE_STATUS_LABELS: Record<CommitmentStatus, string> = {
  idea: "Idea",
  researching: "Researching",
  confirmed: "Confirmed",
  booked: "Booked",
  completed: "Completed",
  cancelled: "Cancelled",
};

const TASK_STATUS_LABELS: Record<CommitmentStatus, string> = {
  idea: "Not started",
  researching: "In progress",
  confirmed: "Ready",
  booked: "In progress",
  completed: "Completed",
  cancelled: "Cancelled",
};

export const ACTIVITY_WORKFLOWS: ActivityWorkflow[] = [
  {
    value: "task",
    label: "Task / Action",
    description: "A piece of work with an owner, due date and outcome.",
    defaultStatus: "idea",
    statusLabels: TASK_STATUS_LABELS,
    actions: NON_BOOKING_ACTIONS,
    preferredFields: { owner: true, endDate: false, location: false, supplier: false, booking: false, cost: false, payments: false },
  },
  {
    value: "booking",
    label: "Booking",
    description: "A reservation or supplier booking to confirm and track.",
    defaultStatus: "researching",
    statusLabels: BASE_STATUS_LABELS,
    actions: BOOKING_ACTIONS,
    preferredFields: { owner: true, endDate: true, location: true, supplier: true, booking: true, cost: true, payments: true },
  },
  {
    value: "purchase",
    label: "Purchase",
    description: "Something to buy, price up, pay for or reimburse.",
    defaultStatus: "researching",
    statusLabels: { ...BASE_STATUS_LABELS, confirmed: "Purchased", booked: "Purchased" },
    actions: PURCHASE_ACTIONS,
    preferredFields: { owner: true, endDate: false, location: false, supplier: true, booking: false, cost: true, payments: true },
  },
  {
    value: "event",
    label: "Meeting / Event",
    description: "A scheduled moment with time, place and participants.",
    defaultStatus: "researching",
    statusLabels: { ...BASE_STATUS_LABELS, researching: "Planning", booked: "Scheduled" },
    actions: EVENT_ACTIONS,
    preferredFields: { owner: true, endDate: true, location: true, supplier: false, booking: false, cost: false, payments: false },
  },
  {
    value: "other",
    label: "Other",
    description: "A flexible activity without booking-specific behaviour.",
    defaultStatus: "researching",
    statusLabels: { ...BASE_STATUS_LABELS, researching: "In progress" },
    actions: NON_BOOKING_ACTIONS,
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
