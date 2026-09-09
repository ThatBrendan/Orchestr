import type { RecurrenceFrequency } from "@/types/database";

export type RepeatOptionValue = "none" | "weekly_1" | "weekly_2" | "monthly_1";

export interface RepeatOption {
  value: RepeatOptionValue;
  label: string;
  frequency: RecurrenceFrequency | null;
  interval: number | null;
}

export const REPEAT_OPTIONS: RepeatOption[] = [
  { value: "none", label: "Does not repeat", frequency: null, interval: null },
  { value: "weekly_1", label: "Every week", frequency: "weekly", interval: 1 },
  { value: "weekly_2", label: "Every 2 weeks", frequency: "weekly", interval: 2 },
  { value: "monthly_1", label: "Every month", frequency: "monthly", interval: 1 },
];

export function repeatOptionFromParts(
  frequency: RecurrenceFrequency | null | undefined,
  interval: number | null | undefined,
): RepeatOptionValue {
  return REPEAT_OPTIONS.find((option) => option.frequency === frequency && option.interval === interval)?.value ?? "none";
}

export function repeatOption(value: RepeatOptionValue): RepeatOption {
  return REPEAT_OPTIONS.find((option) => option.value === value) ?? REPEAT_OPTIONS[0]!;
}

export function recurrenceLabel(
  frequency: RecurrenceFrequency | null | undefined,
  interval: number | null | undefined,
): string {
  return REPEAT_OPTIONS.find((option) => option.frequency === frequency && option.interval === interval)?.label ?? "Does not repeat";
}
