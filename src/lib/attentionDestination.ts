import type { RouteLocationRaw } from "vue-router";

/** Presentation-only links to existing routes; unknown subjects stay in Health. */
export function attentionDestination(projectId: string, finding: {
  subject_type?: string;
  subject_id?: string | null;
  params?: unknown;
}): { to: RouteLocationRaw; label: string } {
  const params = { projectId };
  const id = finding.subject_id;
  const details = finding.params && typeof finding.params === "object"
    ? finding.params as Record<string, unknown> : {};
  if (finding.subject_type === "decision" && id) {
    return { to: { name: "project.decision", params: { ...params, decisionId: id } }, label: "Open decision" };
  }
  if (["payment_schedule", "reimbursement"].includes(finding.subject_type ?? "") && typeof details.activity_id === "string" && details.activity_id) {
    const reimbursement = finding.subject_type === "reimbursement";
    return { to: { name: "project.commitments", params, query: { commitment: details.activity_id, section: reimbursement ? "reimbursements" : "payments" } }, label: reimbursement ? "Open reimbursements" : "Open payments" };
  }
  if (["commitment", "task"].includes(finding.subject_type ?? "") && id) {
    return { to: { name: "project.commitments", params, query: { [finding.subject_type === "task" ? "item" : "commitment"]: id } }, label: "Review activity" };
  }
  return { to: { name: "project.health", params }, label: "Review in Health" };
}
