<script setup lang="ts">
import { computed } from "vue";

const props = withDefaults(
  defineProps<{ name: string; url?: string | null; size?: number; tone?: "ink" | "muted" }>(),
  { size: 28, tone: "muted", url: undefined },
);

const initials = computed(() =>
  props.name
    .split(/\s+/)
    .slice(0, 2)
    .map((p) => p[0]?.toUpperCase() ?? "")
    .join(""),
);
</script>

<template>
  <img
    v-if="props.url"
    :src="props.url"
    :alt="props.name"
    :width="size"
    :height="size"
    class="rounded-full object-cover shrink-0"
    :style="{ width: size + 'px', height: size + 'px' }"
  >
  <div
    v-else
    class="rounded-full flex items-center justify-center font-semibold shrink-0"
    :class="tone === 'ink' ? 'bg-ink text-white' : 'bg-[#F0F0EE] text-ink-soft'"
    :style="{ width: size + 'px', height: size + 'px', fontSize: Math.round(size * 0.42) + 'px' }"
  >
    {{ initials }}
  </div>
</template>
