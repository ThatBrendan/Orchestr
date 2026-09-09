import { computed, type ComputedRef } from "vue";
import { useProjectContextStore } from "@/stores/project-context";
import { can, type PermissionKey } from "@/lib/permissions";
import type { ProjectContext, ProjectContextProject } from "@/types/domain";
import type { MemberRole } from "@/types/database";

/**
 * The currently-open project + the caller's role.
 * Hydrated by the `hydrateProjectContext` router guard (docs/TECHNICAL_ARCHITECTURE.md §3, §5).
 */
export function useProjectContext() {
  const store = useProjectContextStore();
  const context: ComputedRef<ProjectContext | null> = computed(() => store.context);

  const projectId: ComputedRef<string | null> = computed(() => context.value?.projectId ?? null);
  const role: ComputedRef<MemberRole | null> = computed(() => context.value?.role ?? null);
  const project: ComputedRef<ProjectContextProject | null> = computed(() => context.value?.project ?? null);
  const isOrganizer = computed(() => role.value === "organizer");

  /** ADVISORY permission check — RLS is the real gate. */
  function allowed(key: PermissionKey) {
    return can(role.value, key);
  }

  return { context, projectId, role, project, isOrganizer, allowed };
}
