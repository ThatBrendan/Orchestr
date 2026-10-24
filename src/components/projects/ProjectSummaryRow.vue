<script setup lang="ts">
import { computed } from "vue";
import type { MyProject } from "@/types/domain";
import { useMoney } from "@/composables/useMoney";
import { useProjectTime } from "@/composables/useProjectTime";
import { isProjectModuleVisible, profileDefinition } from "@/lib/projectProfiles";
import AppIcon from "@/components/ui/AppIcon.vue";


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
    :aria-label="`Open project: ${project.name}`"
    class="group block rounded-xl border border-line bg-surface p-4 sm:p-5 hover:border-brand/40 focus-ring transition-colors"
  >
    <div class="flex items-start justify-between gap-4">
      <div class="min-w-0 [overflow-wrap:anywhere]">
        <h3 class="text-card-heading text-ink">
          {{ project.name }}
        </h3>
        <p class="mt-1 text-meta text-muted">
          <span class="capitalize">{{ project.status }}</span> · {{ profile.label }} · {{ dates }}
        </p>
      </div>
      <AppIcon
        name="chevronRight"
        :size="18"
        class="mt-1 shrink-0 text-brand"
      />
    </div>
    <p
      v-if="attention > 0 && (project.status === 'draft' || project.status === 'active')"
      class="mt-3 text-sm font-medium text-warning"
    >
      {{ attention }} {{ attention === 1 ? 'item needs' : 'items need' }} attention
    </p>
    <div class="mt-3 flex flex-wrap gap-x-4 gap-y-1 text-meta text-ink-soft">
      <span class="tnum">{{ project.progress_pct ?? 0 }}% complete</span>
      <span
        v-if="showBudget"
        class="tnum"
      >{{ spendLine }}</span>
    </div>
  </RouterLink>
</template>
