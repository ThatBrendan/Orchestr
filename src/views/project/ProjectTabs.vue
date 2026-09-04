<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";

const props = defineProps<{ projectId: string }>();
const route = useRoute();

const TABS = [
  { name: "project.overview", label: "Overview" },
  { name: "project.commitments", label: "Activities" },
  { name: "project.budget", label: "Budget" },
  { name: "project.timeline", label: "Timeline" },
  { name: "project.people", label: "People" },
  { name: "project.health", label: "Health" },
];

const current = computed(() => String(route.name ?? ""));
</script>

<template>
  <div class="mt-8 border-b flex gap-1 overflow-x-auto border-line">
    <RouterLink
      v-for="t in TABS"
      :key="t.name"
      :to="{ name: t.name, params: { projectId: props.projectId } }"
      class="px-3.5 py-2.5 text-[13.5px] font-medium whitespace-nowrap border-b-2 -mb-px focus-ring transition-colors"
      :class="current === t.name ? 'border-ink text-ink' : 'border-transparent text-muted hover:text-ink-soft'"
    >
      {{ t.label }}
    </RouterLink>
  </div>
</template>
