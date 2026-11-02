<script setup lang="ts">
import { computed } from "vue";
import { RouterLink, type RouteLocationRaw } from "vue-router";
import type { FindingSeverity } from "@/types";

import AppIcon from "@/components/ui/AppIcon.vue";
import type { IconName } from "@/components/ui/icons";
import { normalizeHealthCopy } from "@/lib/presentation";

/** Structural prop — accepts a project HealthFinding or a DashboardFinding. */
interface FindingLike {
  severity: FindingSeverity;
  subject_type?: string;
  subject_label?: string | null;
  message: string;
  resolution: string;
}

const props = defineProps<{
  finding: FindingLike;
  /** Optional project label (dashboard aggregates findings across projects). */
  projectLabel?: string;
  to?: RouteLocationRaw;
  destinationLabel?: string;
  /** Dashboard-only icon treatment; the project Overview keeps its existing layout. */
  dashboard?: boolean;
}>();

const contextIcon = computed<IconName>(() => {
  if (!props.dashboard) return "alert";
  if (["payment_schedule", "reimbursement"].includes(props.finding.subject_type ?? "")) return "coins";
  if (props.finding.subject_type === "decision") return "flag";
  if (["commitment", "task"].includes(props.finding.subject_type ?? "")) return "checkCircle";
  return "alert";
});

const message = computed(() => props.finding.subject_type === "reimbursement" ? props.finding.message : normalizeHealthCopy(props.finding.message));
const resolution = computed(() => props.finding.subject_type === "reimbursement" ? props.finding.resolution : normalizeHealthCopy(props.finding.resolution));
</script>

<template>
  <RouterLink
    v-if="props.to"
    :to="props.to"
    class="flex items-center gap-3 px-4 py-3.5 first:rounded-t-xl last:rounded-b-xl hover:bg-surface-subtle focus-ring transition-colors"
  >
    <AppIcon
      :name="contextIcon"
      :size="18"
      class="shrink-0"
      :class="[finding.severity === 'blocker' ? 'text-danger' : 'text-warning', dashboard ? ['box-content rounded-lg p-2.5', finding.severity === 'blocker' ? 'bg-danger-soft' : 'bg-warning-soft'] : '']"
    />
    <div class="min-w-0 flex-1 [overflow-wrap:anywhere]">
      <div class="text-14 font-medium">
        <span
          v-if="finding.subject_label"
          class="font-semibold"
        >{{ finding.subject_label }} · </span>
        {{ message }}
      </div>
      <div class="text-13 text-ink-soft">
        <span
          v-if="projectLabel"
          class="text-muted"
        >{{ projectLabel }} · </span>{{ resolution }}
      </div>
      <div
        v-if="destinationLabel"
        class="mt-1 text-meta font-medium text-brand"
      >
        {{ destinationLabel }}
      </div>
    </div>
    <span class="shrink-0 text-brand"><AppIcon
      name="chevronRight"
      :size="16"
    /></span>
  </RouterLink>

  <div
    v-else
    class="flex items-center gap-3 px-4 py-3.5"
  >
    <AppIcon
      name="alert"
      :size="18"
      class="shrink-0"
      :class="finding.severity === 'blocker' ? 'text-danger' : 'text-warning'"
    />
    <div class="min-w-0 flex-1 [overflow-wrap:anywhere]">
      <div class="text-14 font-medium">
        <span
          v-if="finding.subject_label"
          class="font-semibold"
        >{{ finding.subject_label }} · </span>
        {{ message }}
      </div>
      <div class="text-13 text-ink-soft">
        <span
          v-if="projectLabel"
          class="text-muted"
        >{{ projectLabel }} · </span>{{ resolution }}
      </div>
    </div>
  </div>
</template>
