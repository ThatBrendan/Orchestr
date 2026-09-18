import type { QueryClient, QueryKey } from "@tanstack/vue-query";
import { qk } from "./keys";

/** Shared read-model dependencies; never clear unrelated projects or auth data. */
export function invalidatePlanning(client: QueryClient, projectId: string, extra: QueryKey[] = []) {
  return Promise.all([
    ['project',projectId,'items'], ['project',projectId,'area-totals'], ['settlement'], qk.project.overview(projectId), qk.project.timeline(projectId),
    qk.project.upcoming(projectId), qk.project.health(projectId),
    qk.project.financials(projectId), qk.me.projects(),
    qk.me.attention(), qk.me.calendarRoot(), ...extra,
  ].map((queryKey) => client.invalidateQueries({ queryKey })));
}
