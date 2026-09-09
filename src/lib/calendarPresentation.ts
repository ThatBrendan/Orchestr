import type { IconName } from "@/components/ui/icons";

export type CalendarSemantic = "start" | "end" | "due" | "payment" | "milestone";

export interface CalendarPresentation {
  semantic: CalendarSemantic;
  label: string;
  icon: IconName;
  markerClass: string;
  softClass: string;
}

const PRESENTATION: Record<CalendarSemantic, CalendarPresentation> = {
  start: {
    semantic: "start",
    label: "Starts",
    icon: "play",
    markerClass: "text-sky-700 bg-sky-50 border-sky-200",
    softClass: "text-sky-700",
  },
  end: {
    semantic: "end",
    label: "Ends",
    icon: "flag",
    markerClass: "text-violet-700 bg-violet-50 border-violet-200",
    softClass: "text-violet-700",
  },
  due: {
    semantic: "due",
    label: "Due",
    icon: "clock",
    markerClass: "text-amber-700 bg-amber-50 border-amber-200",
    softClass: "text-amber-700",
  },
  payment: {
    semantic: "payment",
    label: "Payment",
    icon: "banknote",
    markerClass: "text-emerald-700 bg-emerald-50 border-emerald-200",
    softClass: "text-emerald-700",
  },
  milestone: {
    semantic: "milestone",
    label: "Milestone",
    icon: "diamond",
    markerClass: "text-rose-700 bg-rose-50 border-rose-200",
    softClass: "text-rose-700",
  },
};

export function calendarPresentation(eventType: string): CalendarPresentation {
  if (eventType.includes("payment")) return PRESENTATION.payment;
  if (eventType.includes("milestone")) return PRESENTATION.milestone;
  if (eventType.includes("due")) return PRESENTATION.due;
  if (eventType.includes("end")) return PRESENTATION.end;
  return PRESENTATION.start;
}

export function calendarTypeLabel(eventType: string): string {
  return calendarPresentation(eventType).label;
}

export const CALENDAR_SEMANTICS = Object.values(PRESENTATION);