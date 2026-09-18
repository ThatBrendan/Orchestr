<script setup lang="ts">
import { computed } from "vue";
import type { MyProject } from "@/types/domain";
import { useMoney } from "@/composables/useMoney";
import { useProjectTime } from "@/composables/useProjectTime";
import { isProjectModuleVisible, profileDefinition } from "@/lib/projectProfiles";
import AppIcon from "@/components/ui/AppIcon.vue";
import ProgressBar from "@/components/ui/ProgressBar.vue";

const props = defineProps<{ project: MyProject }>();

const { format } = useMoney();
const time = computed(() => useProjectTime(props.project.timezone));

const dates = computed(() => time.value.dateRange(props.project.starts_on, props.project.ends_on));
const profile = computed(() => profileDefinition(props.project.profile));
const showBudget = computed(() =>
  isProjectModuleVisible(props.project.profile, props.project.module_visibility, "budget"),
);

const spendLine = computed(() => {
  const p = props.project;
  const committed = format(p.committed_spend_minor ?? 0, p.currency);
  // total_target_minor is derived server-side (v_my_projects ← v_project_financials).
  return p.total_target_minor != null
    ? `${committed} committed of ${format(p.total_target_minor, p.currency)}`
    : `${committed} committed`;
});

const attention = computed(() => props.project.attention_count ?? 0);
</script>

<template>
  <RouterLink
    :to="{ name: 'project.overview', params: { projectId: project.project_id } }"
    class="row-hover block border rounded-xl p-5 border-line bg-surface hover:bg-[#FBFBFA] transition-colors"
  >
    <div class="flex flex-col sm:flex-row items-start justify-between gap-3 sm:gap-6">
      <div class="min-w-0 [overflow-wrap:anywhere]">
        <div class="font-medium text-[15.5px]">
          {{ project.name }}
          <span class="ml-2 text-13 font-normal capitalize text-muted">{{ project.status }}</span>
        </div>
        <div class="text-13 mt-0.5 text-muted">
          {{ dates }}
        </div>
        <div class="mt-3 flex items-center gap-2 text-13 text-ink-soft flex-wrap">
          <span class="tnum">{{ project.progress_pct ?? 0 }}%</span>
          <span class="text-muted">complete</span>
          <span
            v-if="showBudget"
            class="text-line"
          >·</span>
          <span
            v-if="showBudget"
            class="tnum"
          >{{ spendLine }}</span>
        </div>
        <div class="mt-2 text-13 text-muted">
          {{ profile.label }}
        </div>
      </div>
      <div class="text-left sm:text-right sm:max-w-[45%]">
        <div
          v-if="attention > 0 && (project.status === 'draft' || project.status === 'active')"
          class="text-13 font-medium text-amber"
        >
          {{ attention }} {{ attention === 1 ? "item needs" : "items need" }} attention
        </div>
        <div class="mt-3 inline-flex items-center gap-1 text-[13.5px] font-medium text-brand-dark">
          Open project <AppIcon
            name="chevronRight"
            :size="16"
          />
        </div>
      </div>
    </div>
    <div class="mt-4">
      <ProgressBar :value="project.progress_pct" />
    </div>
  </RouterLink>
</template>
