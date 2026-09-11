<script setup lang="ts">
import { useProjectContext } from "@/composables/useProjectContext";

const { projectId, project } = useProjectContext();
</script>

<template>
  <div
    v-if="projectId && project"
    class="px-3 pb-4"
  >
    <div class="text-[11px] font-medium uppercase tracking-wide px-3 pb-2 text-muted">
      Current project
    </div>
    <RouterLink
      :to="{ name: 'project.overview', params: { projectId } }"
      class="flex items-center gap-2.5 px-3 py-2.5 rounded-lg bg-accent-soft"
    >
      <span class="w-2 h-2 rounded-full shrink-0 bg-accent" />
      <span class="text-[13.5px] font-medium truncate text-ink">{{ project.name }}</span>
    </RouterLink>
  </div>
</template>
