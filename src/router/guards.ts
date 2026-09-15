import { watch } from "vue";
import type { NavigationGuardWithThis, RouteLocationNormalized } from "vue-router";
import { storeToRefs } from "pinia";
import { useAuthStore } from "@/stores/auth";
import { useProjectContextStore } from "@/stores/project-context";
import { queryClient } from "@/lib/query-client";
import { qk } from "@/composables/keys";
import * as membersService from "@/services/members";
import * as projectsService from "@/services/projects";
import * as adminService from "@/services/admin";
import { toAppError } from "@/lib/errors";

import { safeRedirect } from "@/lib/authPolicy";
export { safeRedirect } from "@/lib/authPolicy";

/** Wait until the initial Supabase session has resolved. */
export function whenReady(): Promise<void> {
  const auth = useAuthStore();
  if (auth.ready) return Promise.resolve();
  const { ready } = storeToRefs(auth);
  return new Promise((resolve) => {
    const stop = watch(
      ready,
      (v) => {
        if (v) {
          stop();
          resolve();
        }
      },
      { immediate: true },
    );
  });
}

export const requireAuth: NavigationGuardWithThis<undefined> = async (to) => {
  await whenReady();
  const auth = useAuthStore();
  if (!auth.isAuthenticated) return { name: "login", query: { redirect: to.fullPath } };
  return true;
};

export const requirePlatformAdmin: NavigationGuardWithThis<undefined> = async (to) => {
  await whenReady();
  const auth = useAuthStore();
  if (!auth.isAuthenticated) return { name: "login", query: { redirect: to.fullPath } };

  try {
    const isAdmin = await queryClient.fetchQuery({
      queryKey: qk.me.platformAdmin(auth.userId ?? "anon"),
      queryFn: () => adminService.isCurrentUserPlatformAdmin(auth.userId!),
      staleTime: 30_000,
    });
    if (!isAdmin) return { name: "access-denied" };
    return true;
  } catch (e) {
    if (toAppError(e).kind === "permission") return { name: "access-denied" };
    throw e;
  }
};

/** For /login and /signup: a signed-in visitor is bounced into the app (honouring ?redirect). */
export const requireGuest: NavigationGuardWithThis<undefined> = async (to) => {
  await whenReady();
  const auth = useAuthStore();
  if (!auth.isAuthenticated) return true;
  const dest = safeRedirect(to.query.redirect);
  return dest ?? { name: "dashboard" };
};

/**
 * Global guard: keep useProjectContext in sync with :projectId.
 * Runs on every navigation (incl. project↔project param changes, which a
 * route `beforeEnter` would miss). Redirects to not-found if the caller isn't
 * an active member (RLS returns nothing anyway). docs/TECHNICAL_ARCHITECTURE.md §3.
 */
export async function hydrateProjectContext(to: RouteLocationNormalized) {
  const ctxStore = useProjectContextStore();
  const name = String(to.name ?? "");
  const projectId = typeof to.params.projectId === "string" ? to.params.projectId : null;

  if (!name.startsWith("project.") || !projectId) {
    return true; // not in the project area — ProjectLayout clears context on unmount
  }
  if (ctxStore.context?.projectId === projectId) return true; // already hydrated

  await whenReady();
  const auth = useAuthStore();
  if (!auth.userId) return { name: "login", query: { redirect: to.fullPath } };

  try {
    const [membership, project] = await Promise.all([
      queryClient.fetchQuery({
        queryKey: qk.project.membership(projectId, auth.userId),
        queryFn: () => membersService.getMyMembership(projectId, auth.userId!),
      }),
      queryClient.fetchQuery({
        queryKey: qk.project.detail(projectId),
        queryFn: () => projectsService.getProject(projectId),
      }),
    ]);
    if (!membership || !project) return { name: "not-found" };

    ctxStore.set({
      projectId,
      role: membership.role,
      memberId: membership.id,
      project: {
        id: project.id,
        name: project.name,
        status: project.status,
        profile: project.profile,
        module_visibility: project.module_visibility as Record<string, boolean>,
        starts_on: project.starts_on,
        ends_on: project.ends_on,
        timezone: project.timezone,
        currency: project.currency,
      },
    });
    return true;
  } catch (e) {
    if (toAppError(e).kind === "not_found") return { name: "not-found" };
    throw e;
  }
}
