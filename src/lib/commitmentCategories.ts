import type { CommitmentKind } from "@/types/database";

// Categories classify spending/reporting; activityWorkflows controls operational behaviour.
export const DEFAULT_COMMITMENT_KIND: CommitmentKind = "other";
export const COMMITMENT_CATEGORY_OPTIONS: { value: CommitmentKind; label: string }[] = [
  { value: "accommodation", label: "Accommodation" },
  { value: "transport", label: "Transport" },
  { value: "food", label: "Food" },
  { value: "experience", label: "Experience" },
  { value: "services", label: "Services" },
  { value: "equipment_assets", label: "Equipment & Assets" },
  { value: "technology", label: "Technology" },
  { value: "marketing", label: "Marketing" },
  { value: "supplies_materials", label: "Supplies & Materials" },
  { value: "fees_admin", label: "Fees & Admin" },
  { value: "other", label: "Other" },
];
export const COMMITMENT_CATEGORY_LABELS = Object.fromEntries(
  COMMITMENT_CATEGORY_OPTIONS.map(({ value, label }) => [value, label]),
) as Record<CommitmentKind, string>;
export function categoryLabel(kind: CommitmentKind): string {
  return COMMITMENT_CATEGORY_LABELS[kind];
}
