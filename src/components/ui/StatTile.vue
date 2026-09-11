<script setup lang="ts">
defineProps<{ value: string; label: string; tone?: "default" | "amber" }>();
</script>

<template>
  <div>
    <div
      class="font-display text-[21px] font-semibold tnum"
      :class="tone === 'amber' ? 'text-amber' : 'text-ink'"
    >
      {{ value }}
    </div>
    <div class="text-[12.5px] mt-0.5 text-muted">
      {{ label }}
    </div>
  </div>
</template>
