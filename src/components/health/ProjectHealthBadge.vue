<script setup lang="ts">
import { computed } from "vue";
import type { HealthStatus } from "@/types/database";
import StatusBadge from "@/components/ui/StatusBadge.vue";

const props = defineProps<{ status: HealthStatus | null | undefined }>();

const map = computed(
  () =>
    ({
      needs_attention: { label: "Needs attention", tone: "danger" as const },
      at_risk: { label: "At risk", tone: "amber" as const },
      healthy: { label: "Healthy", tone: "accent" as const },
    })[props.status ?? "healthy"],
);
</script>

<template>
  <StatusBadge :label="map.label" :tone="map.tone" />
</template>
