<script setup lang="ts">
import AppIcon from "@/components/ui/AppIcon.vue";
import type { IconName } from "@/components/ui/icons";
const capabilities: { label: string; icon: IconName; tone: string }[] = [
  { label: "Activities", icon: "checkCircle", tone: "text-brand" },
  { label: "People", icon: "people", tone: "text-accent" },
  { label: "Decisions", icon: "flag", tone: "text-brand" },
  { label: "Dates", icon: "calendar", tone: "text-amber" },
  { label: "Money", icon: "coins", tone: "text-accent" },
  { label: "Progress", icon: "circleDot", tone: "text-brand" },
];
</script>

<template>
  <section
    id="product"
    class="border-y border-line bg-surface"
    aria-labelledby="pillars-heading"
  >
    <div class="max-w-6xl mx-auto px-5 md:px-8 py-7 flex flex-col xl:flex-row items-center justify-between gap-5">
      <h2
        id="pillars-heading"
        class="text-13 uppercase tracking-wider text-ink-soft text-center"
      >
        What Orchestrio brings together
      </h2>
      <ul class="flex flex-wrap justify-center gap-2 sm:gap-3">
        <li
          v-for="item in capabilities"
          :key="item.label"
          class="inline-flex items-center gap-2 rounded-full border border-line bg-paper px-3 py-2 text-13 font-semibold"
        >
          <AppIcon
            :name="item.icon"
            :class="item.tone"
            :size="16"
          />{{ item.label }}
        </li>
      </ul>
    </div>
  </section>
</template>
