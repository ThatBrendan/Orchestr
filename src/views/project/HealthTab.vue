<script setup lang="ts">
import ListPagination from "@/components/ui/ListPagination.vue";
import { useListPagination } from "@/composables/useListPagination";
import { computed, ref } from "vue";
import { useRoute } from "vue-router";
import { useProjectHealth, useProjectHealthSummary } from "@/composables/useProject";
import { useProjectContext } from "@/composables/useProjectContext";
import SkeletonBlock from "@/components/ui/SkeletonBlock.vue";
import ErrorState from "@/components/ui/ErrorState.vue";
import EmptyState from "@/components/ui/EmptyState.vue";

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

const resetKey = computed(() => `${projectId.value}:${filter.value}:${showResolved.value}`);
const { page, result: paginated } = useListPagination(visible, 10, resetKey);

const TABS: { key: Filter; label: string }[] = [
  { key: "all", label: "All" },
  { key: "blocker", label: "Blockers" },
  { key: "warning", label: "Warnings" },
  { key: "info", label: "Info" },
  { key: "ok", label: "Passed" },
];
const heading = ref<HTMLElement | null>(null);
const pageAttention = computed(() => paginated.value.items.filter(f => f.severity !== 'ok' && !f.dismissed));
const pagePassed = computed(() => paginated.value.items.filter(f => f.severity === 'ok' && !f.dismissed));
const pageDismissed = computed(() => paginated.value.items.filter(f => f.dismissed));
const hasAttention = computed(() => health.findings.value.some(f => f.severity !== 'ok' && !f.dismissed));
function focusHeading() { heading.value?.focus({ preventScroll: true }); }
</script>

<template>
  <div class="fade-in max-w-3xl space-y-5">
    <header>
      <h2
        ref="heading"
        tabindex="-1"
        class="text-section-heading focus-ring"
      >
        Health
      </h2><p class="mt-1 text-sm text-muted">
        What needs attention in this project.
      </p>
    </header>
    <div class="flex items-center justify-between flex-wrap gap-3 mb-5">
      <div class="flex items-center gap-3">
        <SkeletonBlock
          v-if="summaryPending"
          width="120px"
          height="24px"
        />
        <span
          v-if="!summaryPending && summary"
          class="text-meta text-muted"
        >
          {{ summary.attention_count }} need{{ summary.attention_count === 1 ? "s" : "" }} attention
        </span>
      </div>
      <label class="min-h-11 flex items-center gap-2 text-sm text-ink-soft">
        <input
          v-model="showResolved"
          type="checkbox"
          class="h-4 w-4 rounded border-line focus-ring"
        >
        Show dismissed/snoozed
      </label>
    </div>

    <div class="flex gap-1.5 mb-4 flex-wrap">
      <button
        v-for="t in TABS"
        :key="t.key"
        class="min-h-11 px-3 py-2 rounded-lg text-sm font-medium focus-ring"
        :aria-pressed="filter === t.key"
        :class="filter === t.key ? 'bg-brand-soft text-brand' : 'text-ink-soft hover:bg-surface-subtle'"
        @click="filter = t.key"
      >
        {{ t.label }}<span v-if="t.key !== 'all'"> · {{ counts[t.key] }}</span>
      </button>
    </div>

    <div
      v-if="health.isPending.value"
      class="space-y-2"
      role="status"
      aria-label="Loading health findings"
    >
      <SkeletonBlock
        v-for="i in 4"
        :key="i"
        height="72px"
        rounded="0.75rem"
      />
    </div>
    <ErrorState
      v-else-if="health.isError.value"
      :error="health.error.value"
      :retry="() => health.refetch()"
    />
    <EmptyState
      v-else-if="visible.length === 0"
      message="Nothing here — all clear for this filter."
    />
    <div
      v-else
      class="space-y-5"
    >
      <section
        v-if="pageAttention.length"
        aria-label="Needs attention"
      >
        <h3 class="text-sm font-semibold text-ink-soft mb-3">
          Needs attention
        </h3><div class="rounded-xl border border-line bg-surface divide-y divide-line">
          <FindingCard
            v-for="f in pageAttention"
            :key="f.code + (f.subject_id ?? '') + f.subject_type"
            :finding="f"
            :project-id="projectId"
            :can-dismiss="canDismiss"
            @changed="focusHeading"
          />
        </div>
      </section>
      <p
        v-else-if="!hasAttention"
        class="text-sm text-success"
      >
        No findings need attention.
      </p>
      <details
        v-if="pagePassed.length"
        :open="filter === 'ok'"
        class="rounded-xl border border-line bg-surface"
      >
        <summary class="min-h-11 px-4 py-3 text-sm text-success cursor-pointer rounded-lg focus-ring">
          <h3 class="inline font-medium">
            Passed · {{ pagePassed.length }} on this page
          </h3>
        </summary><div class="divide-y divide-line">
          <FindingCard
            v-for="f in pagePassed"
            :key="f.code + (f.subject_id ?? '') + f.subject_type"
            :finding="f"
            :project-id="projectId"
            :can-dismiss="canDismiss"
            @changed="focusHeading"
          />
        </div>
      </details>
      <section
        v-if="pageDismissed.length"
        aria-label="Dismissed and snoozed"
      >
        <h3 class="text-sm font-semibold text-muted mb-3">
          Dismissed / snoozed
        </h3><div class="rounded-xl border border-line bg-surface divide-y divide-line">
          <FindingCard
            v-for="f in pageDismissed"
            :key="f.code + (f.subject_id ?? '') + f.subject_type"
            :finding="f"
            :project-id="projectId"
            :can-dismiss="canDismiss"
            @changed="focusHeading"
          />
        </div>
      </section>
    </div>
    <ListPagination
      v-if="!health.isPending.value && !health.isError.value"
      v-model:page="page"
      :previous="paginated.canGoPrevious"
      :next="paginated.canGoNext"
      label="Health findings pages"
    />
  </div>
</template>
