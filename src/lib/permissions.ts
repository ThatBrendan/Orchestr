import type { MemberRole } from "@/types/database";

/**
 * The [MEM-14] permission matrix, encoded once (docs/SECURITY_RLS.md §5).
 * ADVISORY ONLY — RLS is the real gate. Used to disable/hide dead-end controls.
 */
export type PermissionKey =
  | "project.settings"
  | "project.archive"
  | "project.delete"
  | "project.invite"
  | "members.manage"
  | "budget.edit"
  | "commitment.edit"
  | "task.edit"
  | "payment.edit"
  | "milestone.edit"
  | "finding.dismiss";

const MATRIX: Record<PermissionKey, MemberRole[]> = {
  "project.settings": ["organizer"],
  "project.archive": ["organizer"],
  "project.delete": ["organizer"],
  "project.invite": ["organizer"], // members-can-invite flag is FUTURE
  "members.manage": ["organizer"],
  "budget.edit": ["organizer"],
  "commitment.edit": ["organizer", "member"],
  "task.edit": ["organizer", "member"],
  "payment.edit": ["organizer", "member"],
  "milestone.edit": ["organizer", "member"],
  "finding.dismiss": ["organizer", "member"],
};

export function can(role: MemberRole | null | undefined, key: PermissionKey): boolean {
  return !!role && MATRIX[key].includes(role);
}
