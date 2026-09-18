import type { Json, ProjectProfile } from "@/types/database";

export type ProjectModule = "overview" | "commitments" | "budget" | "timeline" | "people" | "notes" | "health";

export interface ProjectProfileDefinition {
  value: ProjectProfile;
  label: string;
  description: string;
  defaultModules: ProjectModule[];
}

export const ALL_PROJECT_MODULES: ProjectModule[] = ["overview", "commitments", "budget", "timeline", "people", "notes", "health"];

export const PROJECT_PROFILES: ProjectProfileDefinition[] = [
  {
    value: "group_trip",
    label: "Group Trip",
    description: "Plan travel, bookings, shared costs and people.",
    defaultModules: ALL_PROJECT_MODULES,
  },
  {
    value: "wedding_event",
    label: "Wedding & Event",
    description: "Coordinate suppliers, budgets, milestones and guests.",
    defaultModules: ALL_PROJECT_MODULES,
  },
  {
    value: "house_move",
    label: "House Move & Checklist",
    description: "Keep activities, deadlines and responsibilities organised.",
    defaultModules: ["overview", "commitments", "timeline", "people", "notes", "health"],
  },
  {
    value: "recurring_process",
    label: "Recurring Process",
    description: "Run work that repeats weekly, fortnightly or monthly.",
    defaultModules: ["overview", "commitments", "timeline", "people", "notes", "health"],
  },
  {
    value: "team_project",
    label: "Team Project",
    description: "Coordinate owners, deadlines, milestones and execution.",
    defaultModules: ["overview", "commitments", "timeline", "people", "notes", "health"],
  },
  {
    value: "launch",
    label: "Product / Startup Launch",
    description: "Manage launch activities, budgets, suppliers and teams.",
    defaultModules: ALL_PROJECT_MODULES,
  },
  {
    value: "blank",
    label: "Blank Project",
    description: "Start without a predefined workflow.",
    defaultModules: ALL_PROJECT_MODULES,
  },
];

export const DEFAULT_PROJECT_PROFILE: ProjectProfile = "blank";
export const OPTIONAL_PROJECT_MODULES: ProjectModule[] = ["budget"];

export function profileDefinition(profile: ProjectProfile | null | undefined): ProjectProfileDefinition {
  return PROJECT_PROFILES.find((p) => p.value === profile) ?? PROJECT_PROFILES[PROJECT_PROFILES.length - 1]!;
}

export function moduleVisibilityValue(moduleVisibility: Json | null | undefined, module: ProjectModule): boolean | null {
  if (!moduleVisibility || typeof moduleVisibility !== "object" || Array.isArray(moduleVisibility)) return null;
  const value = (moduleVisibility as Record<string, unknown>)[module];
  return typeof value === "boolean" ? value : null;
}

export function isProjectModuleVisible(
  profile: ProjectProfile | null | undefined,
  moduleVisibility: Json | null | undefined,
  module: ProjectModule,
): boolean {
  const override = moduleVisibilityValue(moduleVisibility, module);
  if (override != null) return override;
  return profileDefinition(profile).defaultModules.includes(module);
}

export function setModuleVisibility(moduleVisibility: Json | null | undefined, module: ProjectModule, visible: boolean): Json {
  const current =
    moduleVisibility && typeof moduleVisibility === "object" && !Array.isArray(moduleVisibility)
      ? { ...(moduleVisibility as Record<string, unknown>) }
      : {};
  current[module] = visible;
  return current as Json;
}
