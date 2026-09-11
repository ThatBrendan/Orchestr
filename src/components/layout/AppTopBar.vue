<script setup lang="ts">
import InvitationNotifications from "./InvitationNotifications.vue";
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useProjectContext } from "@/composables/useProjectContext";
import { APP_NAME, config } from "@/config";

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
    <span class="font-display font-semibold text-[16px] truncate">{{ title }}</span>
    <span
      v-if="config.env !== 'production'"
      class="ml-3 text-[10px] uppercase tracking-wide text-muted"
    >{{ config.env }}</span>
    <InvitationNotifications />
  </div>
</template>
