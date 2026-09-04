<script setup lang="ts">
const STEPS = [
  {
    n: "01",
    title: "Create a plan",
    body: "Start a project with its dates, currency and the people involved.",
  },
  {
    n: "02",
    title: "Add commitments and people",
    body: "Capture activities and bookings, assign an owner to each, and record what they cost.",
  },
  {
    n: "03",
    title: "Track costs, ownership and deadlines",
    body: "Watch committed spend, payments and outstanding balances update as the plan takes shape.",
  },
  {
    n: "04",
    title: "Resolve risks and execute",
    body: "Clear the issues Orchestr flags — missing owners, overdue payments, incomplete bookings — and run the plan.",
  },
];
</script>

<template>
  <section id="how-it-works" class="bg-surface border-y border-line" aria-labelledby="how-heading">
    <div class="max-w-6xl mx-auto px-5 md:px-8 py-16 md:py-24">
      <h2 id="how-heading" class="font-display text-[26px] md:text-[32px] font-semibold tracking-tight">How it works</h2>
      <p class="mt-3 text-[16px] text-ink-soft max-w-2xl">Four steps from a rough idea to a plan that runs itself.</p>

      <ol class="mt-10 grid sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <li v-for="s in STEPS" :key="s.n" class="rounded-xl border border-line bg-paper p-5">
          <div class="font-display text-13 font-semibold text-accent tnum">{{ s.n }}</div>
          <h3 class="mt-2 text-[15px] font-semibold">{{ s.title }}</h3>
          <p class="mt-1.5 text-13.5 leading-relaxed text-ink-soft">{{ s.body }}</p>
        </li>
      </ol>
    </div>
  </section>
</template>
