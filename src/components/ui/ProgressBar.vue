<script setup lang="ts">
import { computed } from "vue";
const props = defineProps<{ value: number | null | undefined }>();
const pct = computed(() => Math.max(0, Math.min(100, props.value ?? 0)));
</script>

<template>
  <div class="h-1.5 rounded-full overflow-hidden bg-secondary">
    <div
      class="h-full rounded-full bar-fill bg-brand"
      :style="{ width: pct + '%' }"
    />
  </div>
</template>
