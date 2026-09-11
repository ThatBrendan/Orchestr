<script setup lang="ts">
withDefaults(defineProps<{ width?: "md" | "lg" }>(), { width: "lg" });
</script>

<template>
  <div
    class="mx-auto min-w-0 px-4 sm:px-6 md:px-10 py-6 sm:py-10 fade-in"
    :class="width === 'md' ? 'max-w-3xl' : 'max-w-5xl'"
  >
    <slot />
  </div>
</template>
