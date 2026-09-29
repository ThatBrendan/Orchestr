/** Private app-schema contracts, not part of the public PostgREST Database API.
 * Keep aligned with the event foundation, project join, Decision and Comment migrations.
 * No client emitter: these describe trusted server facts only.
 */
export type DomainEventType = "reimbursement.created" | "reimbursement.cancelled" | "payment.due_soon" | "comment.created" | "activity.created" | "activity.completed" | "project.join_requested" | "project.member_approved" | "decision.created" | "decision.vote_cast" | "decision.deadline_reached" | "decision.resolved";

/** Reserved vocabulary: register a validated server handler before enabling emission. */
export type FutureDomainEventType =
  | "activity.due_soon" | "activity.overdue"
  | "payment.obligation_created" | "payment.requested"
  | "payment.marked_paid" | "payment.confirmed" | "payment.collection_settled";

interface DomainEventBase {
  readonly id: string;
  readonly project_id: string;
  readonly actor_user_id: string | null;
  readonly resource_id: string;
  readonly deduplication_key: string;
  readonly created_at: string;
}

export type DomainEventRow = DomainEventBase & (
  | { readonly event_type: "reimbursement.created" | "reimbursement.cancelled"; readonly resource_type: "reimbursement"; readonly payload: { readonly activity_id: string; readonly payment_id: string } }
  | { readonly event_type: "payment.due_soon"; readonly resource_type: "payment_schedule"; readonly payload: { readonly activity_id: string } }
  | { readonly event_type: "comment.created"; readonly resource_type: "comment"; readonly payload: { readonly parent_resource_type: "activity" | "decision"; readonly parent_resource_id: string } }
  | { readonly event_type: "decision.created" | "decision.vote_cast" | "decision.deadline_reached"; readonly resource_type: "decision"; readonly payload: Record<string, never> }
  | { readonly event_type: "decision.resolved"; readonly resource_type: "decision"; readonly payload: { readonly resolved_option_id: string } }
  | { readonly event_type: "activity.created" | "activity.completed"; readonly resource_type: "activity"; readonly payload: { readonly category_id: string | null } }
  | { readonly event_type: "project.join_requested" | "project.member_approved"; readonly resource_type: "join_request"; readonly payload: Record<string, never> }
);

export interface DomainEventTypeRow {
  event_type: DomainEventType;
  resource_type: "reimbursement" | "payment_schedule" | "activity" | "join_request" | "decision" | "comment";
}
export interface AutomationRuleRow {
  id: string;
  event_type: "reimbursement.created" | "payment.due_soon" | "activity.created" | "project.join_requested" | "project.member_approved" | "decision.deadline_reached" | "decision.resolved";
  enabled: boolean;
  condition_handler: "always" | "activity_live" | "join_project_live" | "decision_live";
  action_type: "notify_reimbursement_debtor" | "notify_payment_responsible" | "notify_activity_collaborators" | "notify_join_organizers" | "notify_approved_requester" | "notify_decision_managers" | "notify_decision_members";
  action_config: Record<string, never>;
  priority: number;
}
export interface DomainEventProcessingRow {
  readonly event_id: string;
  readonly processed_at: string;
}
export interface AutomationActionRunRow {
  readonly event_id: string;
  readonly rule_id: string;
  readonly executed_at: string;
}
