<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useProjectContext } from "@/composables/useProjectContext";
import { isProjectModuleVisible, type ProjectModule } from "@/lib/projectProfiles";

const props = defineProps<{ projectId: string }>();
const route = useRoute();
const { project } = useProjectContext();

const TABS = [
  { name: "project.overview", label: "Overview", module: "overview" },
  { name: "project.commitments", label: "Activities", module: "commitments" },
  { name: "project.decisions", label: "Decisions", module: "decisions" },
  { name: "project.budget", label: "Budget", module: "budget" },
  { name: "project.calendar", label: "Calendar", module: "timeline" },
  { name: "project.timeline", label: "Timeline", module: "timeline" },
  { name: "project.people", label: "People", module: "people" },
  { name: "project.notes", label: "Notes", module: "notes" },
  { name: "project.health", label: "Health", module: "health" },
] satisfies { name: string; label: string; module: ProjectModule }[];

const visibleTabs = computed(() =>
  TABS.filter((tab) => isProjectModuleVisible(project.value?.profile, project.value?.module_visibility, tab.module)),
);

const current = computed(() => String(route.name ?? ""));
</script>

<template>
  <div class="mt-8 border-b flex gap-1 overflow-x-auto border-line">
    <RouterLink
      v-for="t in visibleTabs"
      :key="t.name"
      :to="{ name: t.name, params: { projectId: props.projectId } }"
      :aria-current="(current === t.name || (t.name === 'project.decisions' && current === 'project.decision')) ? 'page' : undefined"
      class="min-h-11 px-3.5 py-2.5 text-sm font-medium whitespace-nowrap border-b-2 -mb-px focus-ring transition-colors"
      :class="(current === t.name || (t.name === 'project.decisions' && current === 'project.decision')) ? 'border-ink text-ink' : 'border-transparent text-muted hover:text-ink-soft'"
    >
      {{ t.label }}
    </RouterLink>
  </div>
</template>
