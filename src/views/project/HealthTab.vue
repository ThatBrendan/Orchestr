<script setup lang="ts">
import { computed, ref } from "vue";
import { useRoute } from "vue-router";
import { useProjectHealth, useProjectHealthSummary } from "@/composables/useProject";
import { useProjectContext } from "@/composables/useProjectContext";
import SkeletonBlock from "@/components/ui/SkeletonBlock.vue";
import ErrorState from "@/components/ui/ErrorState.vue";
import EmptyState from "@/components/ui/EmptyState.vue";
import ProjectHealthBadge from "@/components/health/ProjectHealthBadge.vue";
import FindingCard from "@/components/health/FindingCard.vue";
import type { FindingSeverity } from "@/types/database";

const route = useRoute();
const projectId = computed(() => String(route.params.projectId));
const { allowed, project } = useProjectContext();
const archived = computed(() => project.value?.status === "archived");
const canDismiss = computed(() => allowed("finding.dismiss") && !archived.value);

const health = useProjectHealth(projectId);
const { summary, isPending: summaryPending } = useProjectHealthSummary(projectId);

type Filter = "all" | FindingSeverity;
const filter = ref<Filter>("all");
const showResolved = ref(false);

// Counts reflect the current "show dismissed/snoozed" toggle, so a tab's count
// always matches what clicking it actually reveals.
const inScope = computed(() => health.findings.value.filter((f) => showResolved.value || !f.dismissed));

const counts = computed(() => {
  const c: Record<FindingSeverity, number> = { blocker: 0, warning: 0, info: 0, ok: 0 };
  for (const f of inScope.value) c[f.severity]++;
  return c;
});

const visible = computed(() =>
  inScope.value
    .filter((f) => filter.value === "all" || f.severity === filter.value)
    .sort((a, b) => {
      const order: Record<FindingSeverity, number> = { blocker: 0, warning: 1, info: 2, ok: 3 };
      return order[a.severity] - order[b.severity];
    }),
);

const TABS: { key: Filter; label: string }[] = [
  { key: "all", label: "All" },
  { key: "blocker", label: "Blockers" },
  { key: "warning", label: "Warnings" },
  { key: "info", label: "Info" },
  { key: "ok", label: "On track" },
];
</script>

<template>
  <div class="fade-in">
    <div class="flex items-center justify-between flex-wrap gap-3 mb-5">
      <div class="flex items-center gap-3">
        <SkeletonBlock v-if="summaryPending" width="120px" height="24px" />
        <ProjectHealthBadge v-else :status="summary?.status as 'needs_attention' | 'at_risk' | 'healthy' | undefined" />
        <span v-if="!summaryPending && summary" class="text-13 text-muted">
          {{ summary.attention_count }} need{{ summary.attention_count === 1 ? "s" : "" }} attention
        </span>
      </div>
      <label class="flex items-center gap-2 text-13 text-ink-soft">
        <input v-model="showResolved" type="checkbox" class="rounded border-line" />
        Show dismissed/snoozed
      </label>
    </div>

    <div class="flex gap-1.5 mb-4 flex-wrap">
      <button
        v-for="t in TABS"
        :key="t.key"
        class="px-3 py-1.5 rounded-lg text-13 font-medium focus-ring"
        :class="filter === t.key ? 'bg-ink text-white' : 'bg-[#F1F1EF] text-ink-soft hover:bg-[#E7E7E3]'"
        @click="filter = t.key"
      >
        {{ t.label }}<span v-if="t.key !== 'all'"> · {{ counts[t.key] }}</span>
      </button>
    </div>

    <div v-if="health.isPending.value" class="space-y-2">
      <SkeletonBlock v-for="i in 4" :key="i" height="72px" rounded="0.75rem" />
    </div>
    <ErrorState v-else-if="health.isError.value" :error="health.error.value" :retry="() => health.refetch()" />
    <EmptyState v-else-if="visible.length === 0" message="Nothing here — all clear for this filter." />
    <div v-else class="border rounded-xl divide-y border-line bg-surface">
      <FindingCard
        v-for="f in visible"
        :key="f.code + (f.subject_id ?? '') + f.subject_type"
        :finding="f"
        :project-id="projectId"
        :can-dismiss="canDismiss"
      />
    </div>
  </div>
</template>
