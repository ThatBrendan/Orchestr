<script setup lang="ts">
import { computed } from "vue";
import { RouterLink } from "vue-router";
import type { MyProject } from "@/types/domain";
import type { IconName } from "@/components/ui/icons";
import { useMoney } from "@/composables/useMoney";
import { useProjectTime } from "@/composables/useProjectTime";
import { isProjectModuleVisible, PROJECT_PROFILES } from "@/lib/projectProfiles";
import AppIcon from "@/components/ui/AppIcon.vue";
import ProgressBar from "@/components/ui/ProgressBar.vue";

const props = defineProps<{ project: MyProject }>();
const { format } = useMoney();
const profile = computed(() => PROJECT_PROFILES.find(p => p.value === props.project.profile));
const dates = computed(() => useProjectTime(props.project.timezone).dateRange(props.project.starts_on, props.project.ends_on));
const showBudget = computed(() => isProjectModuleVisible(props.project.profile, props.project.module_visibility, "budget") && props.project.committed_spend_minor != null);
const appearance = computed<{ icon: IconName; tone: string }>(() => {
  switch (props.project.profile) {
    case "group_trip": return { icon: "pin", tone: "bg-accent-soft text-accent" };
    case "wedding_event": return { icon: "diamond", tone: "bg-amber-soft text-amber" };
    case "house_move": return { icon: "home", tone: "bg-accent-soft text-accent" };
    case "recurring_process": return { icon: "clock", tone: "bg-brand-soft text-brand" };
    case "launch": return { icon: "flag", tone: "bg-brand-soft text-brand" };
    case "team_project": return { icon: "people", tone: "bg-brand-soft text-brand" };
    default: return { icon: "projects", tone: "bg-brand-soft text-brand" };
  }
});
</script>

<template>
  <RouterLink
    :to="{ name: 'project.overview', params: { projectId: project.project_id } }"
    :aria-label="`Open project: ${project.name}`"
    class="group min-w-0 flex h-full flex-col rounded-2xl border border-line bg-surface p-5 hover:border-brand/40 hover:shadow-sm focus-ring transition-colors"
  >
    <div class="flex items-center justify-between gap-3">
      <span
        class="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl"
        :class="appearance.tone"
      >
        <AppIcon
          :name="appearance.icon"
          :size="22"
        />
      </span>
      <span class="rounded-full bg-surface-subtle px-2.5 py-1 text-meta text-ink-soft capitalize">{{ project.status }}</span>
    </div>
    <h3 class="mt-4 text-lg leading-snug font-semibold [overflow-wrap:anywhere] group-hover:text-brand">
      {{ project.name }}
    </h3>
    <p
      v-if="profile && project.profile !== 'blank'"
      class="mt-1.5 text-meta text-ink-soft"
    >
      {{ profile.label }}
    </p>
    <p
      v-if="project.starts_on || project.ends_on"
      class="mt-3 flex items-start gap-2 text-meta text-muted"
    >
      <AppIcon
        name="calendar"
        :size="16"
        class="shrink-0 mt-0.5"
      />{{ dates }}
    </p>
    <p
      v-if="(project.attention_count ?? 0) > 0"
      class="mt-4 flex items-center gap-2 rounded-lg bg-warning-soft px-3 py-2 text-meta font-medium text-warning"
    >
      <AppIcon
        name="alert"
        :size="16"
        class="shrink-0"
      />
      {{ project.attention_count }} {{ project.attention_count === 1 ? 'item needs' : 'items need' }} attention
    </p>
    <div
      v-if="project.progress_pct != null || showBudget"
      class="mt-5 space-y-4"
    >
      <div v-if="project.progress_pct != null">
        <div class="mb-2 flex flex-wrap justify-between gap-2 text-meta">
          <span class="text-ink-soft">Progress</span><span class="font-medium tnum">{{ project.progress_pct }}% complete</span>
        </div>
        <ProgressBar
          :value="project.progress_pct"
          aria-hidden="true"
        />
      </div>
      <p
        v-if="showBudget"
        class="text-meta text-ink-soft [overflow-wrap:anywhere]"
      >
        <span class="font-semibold text-ink tnum">{{ format(project.committed_spend_minor!, project.currency) }}</span> committed<span v-if="project.total_target_minor != null"> of {{ format(project.total_target_minor, project.currency) }}</span>
      </p>
    </div>
    <div class="flex-1 min-h-5" />
    <div class="border-t border-line pt-4 flex flex-wrap items-center justify-between gap-2 text-meta">
      <span
        v-if="project.my_role"
        class="text-muted capitalize"
      >{{ project.my_role }}</span>
      <span class="ml-auto inline-flex items-center gap-2 font-semibold text-brand">Open project <AppIcon
        name="arrowRight"
        :size="16"
      /></span>
    </div>
  </RouterLink>
</template>
