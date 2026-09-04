import { defineStore } from "pinia";
import { ref } from "vue";
import type { ProjectContext } from "@/types/domain";

/**
 * The currently-open project (docs/TECHNICAL_ARCHITECTURE.md §4).
 * Hydrated by the `hydrateProjectContext` router guard; cleared when leaving the project area.
 */
export const useProjectContextStore = defineStore("project-context", () => {
  const context = ref<ProjectContext | null>(null);

  function set(ctx: ProjectContext) {
    context.value = ctx;
  }
  function clear() {
    context.value = null;
  }

  return { context, set, clear };
});
