import type { ProjectProfile } from "@/types/database";

export type OverviewCardKey =
  | "countdown"
  | "progress"
  | "activities"
  | "bookings"
  | "budget"
  | "payments"
  | "people"
  | "milestones"
  | "overdue"
  | "owners"
  | "health"
  | "upcoming";

export interface OverviewProfileConfig {
  profile: ProjectProfile;
  cards: OverviewCardKey[];
}

export const OVERVIEW_PROFILE_CONFIGS: OverviewProfileConfig[] = [
  {
    profile: "group_trip",
    cards: ["countdown", "bookings", "budget", "payments", "people", "upcoming", "health"],
  },
  {
    profile: "wedding_event",
    cards: ["countdown", "bookings", "budget", "payments", "milestones", "people", "health"],
  },
  {
    profile: "house_move",
    cards: ["progress", "overdue", "owners", "milestones", "upcoming", "health", "budget"],
  },
  {
    profile: "recurring_process",
    cards: ["progress", "overdue", "activities", "upcoming", "owners", "health"],
  },
  {
    profile: "team_project",
    cards: ["progress", "activities", "overdue", "owners", "milestones", "upcoming", "health", "budget"],
  },
  {
    profile: "launch",
    cards: ["countdown", "progress", "milestones", "budget", "activities", "overdue", "owners", "health"],
  },
  {
    profile: "blank",
    cards: ["activities", "upcoming", "people", "health", "budget", "milestones"],
  },
];

export function overviewConfig(profile: ProjectProfile | null | undefined): OverviewProfileConfig {
  return OVERVIEW_PROFILE_CONFIGS.find((config) => config.profile === profile) ?? overviewConfig("blank");
}
