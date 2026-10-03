/** Static product categories. Missing overrides mean enabled; critical delivery is server-owned. */
export const notificationCategories = [
  { id: 'activities', label: 'Activities', description: 'New activities and upcoming activity reminders.' },
  { id: 'decisions', label: 'Decisions', description: 'Voting deadlines and decision results.' },
  { id: 'payments', label: 'Payments', description: 'Upcoming scheduled payment reminders.' },
  { id: 'reimbursements', label: 'Reimbursements', description: 'New reimbursement requests. Payment claims, withdrawals and receipt confirmations always arrive.' },
  { id: 'project_access', label: 'Project access', description: 'Requests to join your projects. Your approval results always arrive.' },
] as const;
export type NotificationCategory = typeof notificationCategories[number]['id'];
export const notificationPolicies = {
  activity_created: { category: 'activities', critical: false },
  activity_due_soon: { category: 'activities', critical: false },
  decision_deadline_reached: { category: 'decisions', critical: false },
  decision_resolved: { category: 'decisions', critical: false },
  payment_due_soon: { category: 'payments', critical: false },
  reimbursement_created: { category: 'reimbursements', critical: false },
  reimbursement_payment_acknowledged: { category: 'reimbursements', critical: true },
  reimbursement_payment_acknowledgement_withdrawn: { category: 'reimbursements', critical: true },
  reimbursement_receipt_confirmed: { category: 'reimbursements', critical: true },
  project_join_requested: { category: 'project_access', critical: false },
  project_member_approved: { category: 'project_access', critical: true },
} as const satisfies Record<string, { category: NotificationCategory; critical: boolean }>;
