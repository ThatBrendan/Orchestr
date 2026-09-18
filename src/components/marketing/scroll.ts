import type { RouteLocationRaw } from "vue-router";

export const PUBLIC_SECTION_LINKS = [
  { label: "Product", to: { path: "/", hash: "#product" } },
  { label: "How it works", to: { path: "/", hash: "#how-it-works" } },
  { label: "Use cases", to: { path: "/", hash: "#use-cases" } },
] as const;

export type PublicSectionLink = (typeof PUBLIC_SECTION_LINKS)[number] & { to: RouteLocationRaw };
