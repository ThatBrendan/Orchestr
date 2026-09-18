<script setup lang="ts">
import AppIcon from "@/components/ui/AppIcon.vue";
import type { IconName } from "@/components/ui/icons";

const PILLARS: { title: string; body: string; icon: IconName }[] = [
  {
    title: "Categories and activities",
    body: "Keep the work, bookings and details of your project together.",
    icon: "projects",
  },
  {
    title: "Work together",
    body: "Assign activities when you need to share the work.",
    icon: "flag",
  },
  {
    title: "Money",
    body: "See what things cost, what’s paid and what’s left to pay.",
    icon: "coins",
  },
  {
    title: "Timeline",
    body: "Bring bookings, payment deadlines and activities together chronologically, in the plan's own timezone.",
    icon: "calendar",
  },
  {
    title: "People",
    body: "See people, their responsibilities and their involvement across the whole plan.",
    icon: "people",
  },
  {
    title: "Stay on track",
    body: "Catch overdue activities, upcoming payments and unfinished bookings.",
    icon: "alert",
  },
];
</script>

<template>
  <section
    id="product"
    class="max-w-6xl mx-auto px-5 md:px-8 py-16 md:py-24"
    aria-labelledby="pillars-heading"
  >
    <h2
      id="pillars-heading"
      class="font-display text-[26px] md:text-[32px] font-semibold tracking-tight"
    >
      One workspace for the whole plan
    </h2>
    <p class="mt-3 text-[16px] text-ink-soft max-w-2xl">
      Orchestrio keeps the moving parts of a plan connected — not scattered across tools that don't talk to each other.
    </p>

    <div class="mt-10 grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
      <div
        v-for="p in PILLARS"
        :key="p.title"
        class="rounded-xl border border-line bg-surface p-5"
      >
        <div class="w-9 h-9 rounded-lg bg-brand-soft text-brand-dark flex items-center justify-center">
          <AppIcon
            :name="p.icon"
            :size="18"
          />
        </div>
        <h3 class="mt-3.5 text-[15px] font-semibold">
          {{ p.title }}
        </h3>
        <p class="mt-1.5 text-13.5 leading-relaxed text-ink-soft">
          {{ p.body }}
        </p>
      </div>
    </div>
  </section>
</template>
