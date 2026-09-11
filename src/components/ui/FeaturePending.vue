<script setup lang="ts">
/**
 * Explicitly isolates a screen/tab/action whose backend or UI is not built in
 * this pass. Never fakes data or behaviour (per the build brief).
 */
defineProps<{ title: string; detail?: string }>();
</script>

<template>
  <div class="border border-dashed rounded-xl p-10 text-center border-line bg-surface fade-in">
    <div class="inline-flex items-center gap-2 text-[12px] font-medium uppercase tracking-wide text-muted">
      <span class="w-1.5 h-1.5 rounded-full bg-muted" />
      Not in this build
    </div>
    <p class="mt-3 text-15 font-medium text-ink">
      {{ title }}
    </p>
    <p
      v-if="detail"
      class="mt-1 text-14 text-muted max-w-sm mx-auto"
    >
      {{ detail }}
    </p>
    <slot />
  </div>
</template>
