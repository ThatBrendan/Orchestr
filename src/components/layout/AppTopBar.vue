<script setup lang="ts">
import InvitationNotifications from "./InvitationNotifications.vue";
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useProjectContext } from "@/composables/useProjectContext";
import { APP_NAME, config } from "@/config";
import orchestrioIcon from "@/assets/orchestrio-favicon.svg";

const route = useRoute();
const { project } = useProjectContext();

const TITLES: Record<string, string> = {
  dashboard: "Dashboard",
  projects: "Projects",
  calendar: "Calendar",
  "people-global": "People",
  settings: "Settings",
};

const title = computed(() => {
  const name = String(route.name ?? "");
  if (name.startsWith("project.")) return project.value?.name ?? "Project";
  return TITLES[name] ?? APP_NAME;
});
</script>

<template>
  <div class="sticky top-0 z-10 h-14 flex items-center px-4 border-b border-line bg-surface">
    <RouterLink
      to="/"
      aria-label="Orchestrio home"
      class="mr-2 flex h-11 w-11 shrink-0 items-center justify-center rounded-lg focus-ring md:hidden"
    >
      <img
        :src="orchestrioIcon"
        alt="Orchestrio"
        class="h-7 w-auto"
      >
    </RouterLink>
    <span class="min-w-0 truncate font-display font-semibold text-[16px]">{{ title }}</span>
    <span
      v-if="config.env !== 'production'"
      class="ml-2 shrink-0 text-[10px] uppercase tracking-wide text-muted"
    >{{ config.env }}</span>
    <InvitationNotifications />
  </div>
</template>
