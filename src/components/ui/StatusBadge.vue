<script setup lang="ts">
import { computed } from "vue";

// Tone-mapped pill, matching the prototype's statusBadge().
const props = defineProps<{ label: string; tone?: "accent" | "amber" | "danger" | "neutral" }>();

const cls = computed(
  () =>
    ({
      accent: "bg-accent-soft text-accent",
      amber: "bg-amber-soft text-amber",
      danger: "bg-danger-soft text-danger",
      neutral: "bg-[#F1F1EF] text-ink-soft",
    })[props.tone ?? "neutral"],
);
</script>

<template>
  <span
    class="inline-flex max-w-full items-center [overflow-wrap:anywhere] px-2 py-0.5 rounded text-[12.5px] font-medium"
    :class="cls"
  >
    {{ props.label }}
  </span>
</template>
