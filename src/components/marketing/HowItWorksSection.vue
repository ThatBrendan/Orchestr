<script setup lang="ts">
const STEPS = [
  {
    n: "01",
    title: "Create a plan",
    body: "Start a project with its dates, currency and the people involved.",
  },
  {
    n: "02",
    title: "Add activities and people",
    body: "Add categories, activities and any costs. Invite people when you’re ready.",
  },
  {
    n: "03",
    title: "Keep up with the plan",
    body: "See deadlines, progress and payments in one place.",
  },
  {
    n: "04",
    title: "Get things done",
    body: "Complete activities as you go. Reuse repeating activities for regular work.",
  },
];
</script>

<template>
  <section
    id="how-it-works"
    class="bg-surface border-y border-line"
    aria-labelledby="how-heading"
  >
    <div class="max-w-6xl mx-auto px-5 md:px-8 py-16 md:py-24">
      <h2
        id="how-heading"
        class="font-display text-[26px] md:text-[32px] font-semibold tracking-tight"
      >
        How it works
      </h2>
      <p class="mt-3 text-[16px] text-ink-soft max-w-2xl">
        From the first idea to the last task.
      </p>

      <ol class="mt-10 grid sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <li
          v-for="s in STEPS"
          :key="s.n"
          class="rounded-xl border border-line bg-paper p-5"
        >
          <div class="font-display text-13 font-semibold text-brand-dark tnum">
            {{ s.n }}
          </div>
          <h3 class="mt-2 text-[15px] font-semibold">
            {{ s.title }}
          </h3>
          <p class="mt-1.5 text-13.5 leading-relaxed text-ink-soft">
            {{ s.body }}
          </p>
        </li>
      </ol>
    </div>
  </section>
</template>
