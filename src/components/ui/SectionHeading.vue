<script setup lang="ts">
defineProps<{ label: string }>();
</script>

<template>
  <h2 class="text-section-heading font-semibold text-ink-soft">
    {{ label }}
  </h2>
</template>
