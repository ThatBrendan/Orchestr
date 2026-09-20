/** Private app-schema contracts, not part of the public PostgREST Database API.
 * Keep aligned with the Phase 1 foundation and Phase 2 join-link migrations.
 * No client emitter: these describe trusted server facts only.
 */
export type DomainEventType = "activity.created" | "activity.completed" | "project.join_requested" | "project.member_approved";

/** Reserved vocabulary: register a validated server handler before enabling emission. */
export type FutureDomainEventType =
  | "decision.created" | "decision.vote_cast" | "decision.deadline_reached" | "decision.resolved"
  | "activity.due_soon" | "activity.overdue"
  | "payment.obligation_created" | "payment.requested" | "payment.due_soon"
  | "payment.marked_paid" | "payment.confirmed" | "payment.collection_settled"
  | "comment.created";

interface DomainEventBase {
  readonly id: string;
  readonly project_id: string;
  readonly actor_user_id: string | null;
  readonly resource_id: string;
  readonly deduplication_key: string;
  readonly created_at: string;
}

export type DomainEventRow = DomainEventBase & (
  | { readonly event_type: "activity.created" | "activity.completed"; readonly resource_type: "activity"; readonly payload: { readonly category_id: string | null } }
  | { readonly event_type: "project.join_requested" | "project.member_approved"; readonly resource_type: "join_request"; readonly payload: Record<string, never> }
);

export interface DomainEventTypeRow {
  event_type: DomainEventType;
  resource_type: "activity" | "join_request";
}
export interface AutomationRuleRow {
  id: string;
  event_type: "activity.created" | "project.join_requested" | "project.member_approved";
  enabled: boolean;
  condition_handler: "always" | "activity_live" | "join_project_live";
  action_type: "notify_activity_collaborators" | "notify_join_organizers" | "notify_approved_requester";
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
