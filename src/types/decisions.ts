export type DecisionRow = {
  id: string; project_id: string; title: string; description: string | null; created_by: string;
  status: "open" | "resolved"; voting_deadline: string | null; deadline_version: number;
  voting_started: boolean; vote_revision: number; resolved_option_id: string | null;
  resolved_at: string | null; resolved_by: string | null; converted_activity_id: string | null;
  created_at: string; updated_at: string; deleted_at: string | null;
}
export type DecisionOptionRow = {
  id: string; project_id: string; decision_id: string; title: string;
  estimated_cost_minor: number | null; sort_order: number; created_at: string;
}
export type DecisionVoteRow = {
  id: string; project_id: string; decision_id: string; option_id: string; voter_user_id: string;
  revision: number; created_at: string; updated_at: string;
}
export interface Decision extends DecisionRow {
  can_manage: boolean; writable: boolean; can_vote: boolean; deadline_reached: boolean; my_option_id: string | null;
  vote_count: number; options: (DecisionOptionRow & { vote_count: number })[];
}
export interface DecisionInput {
  title: string; description: string | null; deadline: string | null;
  options: { title: string; estimated_cost_minor: number | null }[] | null;
}
