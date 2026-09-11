<script setup lang="ts">
import { RouterLink, type RouteLocationRaw } from "vue-router";
import type { FindingSeverity } from "@/types";
import SeverityIcon from "@/components/ui/SeverityIcon.vue";
import AppIcon from "@/components/ui/AppIcon.vue";

/** Structural prop — accepts a project HealthFinding or a DashboardFinding. */
interface FindingLike {
  severity: FindingSeverity;
  message: string;
  resolution: string;
}

const props = defineProps<{
  finding: FindingLike;
  /** Optional project label (dashboard aggregates findings across projects). */
  projectLabel?: string;
  to?: RouteLocationRaw;
}>();
</script>

<template>
  <RouterLink
    v-if="props.to"
    :to="props.to"
    class="flex items-center gap-3 px-4 py-3.5 hover:bg-[#FBFBFA] transition-colors"
  >
    <SeverityIcon :severity="finding.severity" />
    <div class="min-w-0 flex-1 [overflow-wrap:anywhere]">
      <div class="text-14 font-medium">
        {{ finding.message }}
      </div>
      <div class="text-13 text-ink-soft">
        <span
          v-if="projectLabel"
          class="text-muted"
        >{{ projectLabel }} · </span>{{ finding.resolution }}
      </div>
    </div>
    <span class="text-muted"><AppIcon
      name="chevronRight"
      :size="16"
    /></span>
  </RouterLink>

  <div
    v-else
    class="flex items-center gap-3 px-4 py-3.5"
  >
    <SeverityIcon :severity="finding.severity" />
    <div class="min-w-0 flex-1 [overflow-wrap:anywhere]">
      <div class="text-14 font-medium">
        {{ finding.message }}
      </div>
      <div class="text-13 text-ink-soft">
        <span
          v-if="projectLabel"
          class="text-muted"
        >{{ projectLabel }} · </span>{{ finding.resolution }}
      </div>
    </div>
  </div>
</template>
