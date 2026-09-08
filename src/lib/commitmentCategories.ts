import type { CommitmentKind } from "@/types/database";

export const DEFAULT_COMMITMENT_KIND: CommitmentKind = "other";

export const COMMITMENT_CATEGORY_OPTIONS: { value: CommitmentKind; label: string }[] = [
  { value: "other", label: "Other" },
  { value: "accommodation", label: "Accommodation" },
  { value: "transport", label: "Transport" },
  { value: "food", label: "Food" },
  { value: "experience", label: "Experience" },
  { value: "services", label: "Services" },
];

export const COMMITMENT_CATEGORY_LABELS: Record<CommitmentKind, string> = {
  accommodation: "Accommodation",
  transport: "Transport",
  food: "Food",
  experience: "Experience",
  services: "Services",
  other: "Other",
};

export function categoryLabel(kind: CommitmentKind): string {
  return COMMITMENT_CATEGORY_LABELS[kind];
}
