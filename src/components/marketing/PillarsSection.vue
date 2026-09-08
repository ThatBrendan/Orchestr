<script setup lang="ts">
import AppIcon from "@/components/ui/AppIcon.vue";
import type { IconName } from "@/components/ui/icons";

const PILLARS: { title: string; body: string; icon: IconName }[] = [
  {
    title: "Commitments",
    body: "Keep activities, bookings and important commitments organised in one place, each with its cost, dates and status.",
    icon: "projects",
  },
  {
    title: "Ownership",
    body: "Make responsibility explicit. Every commitment has an owner, so everyone knows who's handling what.",
    icon: "flag",
  },
  {
    title: "Money",
    body: "Track planned cost, committed spend, payments, refunds and what's still outstanding — for the plan and per person.",
    icon: "coins",
  },
  {
    title: "Timeline",
    body: "Bring bookings, payment deadlines, tasks and milestones together chronologically, in the plan's own timezone.",
    icon: "calendar",
  },
  {
    title: "People",
    body: "See participants, their responsibilities and their involvement across the whole plan.",
    icon: "people",
  },
  {
    title: "Planning health",
    body: "Surface missing owners, overdue payments, incomplete bookings, budget risk and other issues before they bite.",
    icon: "alert",
  },
];
</script>

<template>
  <section id="product" class="max-w-6xl mx-auto px-5 md:px-8 py-16 md:py-24" aria-labelledby="pillars-heading">
    <h2 id="pillars-heading" class="font-display text-[26px] md:text-[32px] font-semibold tracking-tight">
      One workspace for the whole plan
    </h2>
    <p class="mt-3 text-[16px] text-ink-soft max-w-2xl">
      Orchestrio keeps the moving parts of a plan connected — not scattered across tools that don't talk to each other.
    </p>

    <div class="mt-10 grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
      <div v-for="p in PILLARS" :key="p.title" class="rounded-xl border border-line bg-surface p-5">
        <div class="w-9 h-9 rounded-lg bg-accent-soft text-accent flex items-center justify-center">
          <AppIcon :name="p.icon" :size="18" />
        </div>
        <h3 class="mt-3.5 text-[15px] font-semibold">{{ p.title }}</h3>
        <p class="mt-1.5 text-13.5 leading-relaxed text-ink-soft">{{ p.body }}</p>
      </div>
    </div>
  </section>
</template>
