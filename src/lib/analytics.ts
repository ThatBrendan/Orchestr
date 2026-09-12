import { inject, pageview, track } from "@vercel/analytics";
import type { Router } from "vue-router";
import { config } from "@/config";
import { PUBLIC_ORIGIN } from "@/publicSite";
import { analyticsPath } from "./analyticsPrivacy";

export type ProductEvent = "signup_confirmation_requested" | "signup_started" | "signup_completed" | "login_completed" | "project_created" | "member_invited" | "invitation_accepted" | "activity_created" | "task_created" | "cost_split_saved" | "payment_recorded" | "activity_completed";
let enabled = false;

export function initAnalytics(router: Router) {
  if (enabled || config.env !== "production" || window.location.origin !== PUBLIC_ORIGIN) return;
  enabled = true;
  inject({
    mode: "production", disableAutoTrack: true,
    beforeSend: (event) => {
      // Custom events have no per-record URL context or payload.
      if (event.type === "event") return { ...event, url: `${PUBLIC_ORIGIN}/app` };
      const path = analyticsPath(event.url);
      return path ? { ...event, url: PUBLIC_ORIGIN + path } : null;
    },
  });
  router.afterEach((to, _from, failure) => {
    if (failure) return;
    const path = analyticsPath(to.path);
    if (path) pageview({ path, route: path });
  });
}

/** Analytics must never block or fail a successful product action. No payload API. */
export function trackProductEvent(name: ProductEvent) {
  if (!enabled) return;
  try { track(name); } catch { /* Best-effort telemetry. */ }
}
