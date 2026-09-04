import type { IconName } from "@/components/ui/icons";

export interface NavItem {
  to: { name: string };
  label: string;
  shortLabel: string;
  icon: IconName;
  /** route name prefixes considered "active" for this item */
  match: string[];
}

export const NAV_ITEMS: NavItem[] = [
  { to: { name: "dashboard" }, label: "Dashboard", shortLabel: "Home", icon: "home", match: ["dashboard"] },
  {
    to: { name: "projects" },
    label: "Projects",
    shortLabel: "Projects",
    icon: "projects",
    match: ["projects", "project."],
  },
  { to: { name: "calendar" }, label: "Calendar", shortLabel: "Calendar", icon: "calendar", match: ["calendar"] },
  { to: { name: "people-global" }, label: "People", shortLabel: "People", icon: "people", match: ["people-global"] },
  { to: { name: "settings" }, label: "Settings", shortLabel: "Settings", icon: "settings", match: ["settings"] },
];
