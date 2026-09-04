import { computed } from "vue";
import { storeToRefs } from "pinia";
import { useProjectContextStore } from "@/stores/project-context";
import { can, type PermissionKey } from "@/lib/permissions";

/**
 * The currently-open project + the caller's role.
 * Hydrated by the `hydrateProjectContext` router guard (docs/TECHNICAL_ARCHITECTURE.md §3, §5).
 */
export function useProjectContext() {
  const store = useProjectContextStore();
  const { context } = storeToRefs(store);

  const projectId = computed(() => context.value?.projectId ?? null);
  const role = computed(() => context.value?.role ?? null);
  const project = computed(() => context.value?.project ?? null);
  const isOrganizer = computed(() => role.value === "organizer");

  /** ADVISORY permission check — RLS is the real gate. */
  function allowed(key: PermissionKey) {
    return can(role.value, key);
  }

  return { context, projectId, role, project, isOrganizer, allowed };
}
