<script setup lang="ts">
const CASES = [
  { title: "Group trips", body: "Flights, stays, activities and who owes whom." },
  { title: "Weddings and events", body: "Vendors, deposits, deadlines and a long guest-side checklist." },
  { title: "House moves", body: "Removals, contracts, utilities and overlapping dates." },
  { title: "Product & startup launches", body: "Suppliers, budgets, milestones and cross-team dependencies." },
  { title: "Team projects", body: "Owners, spend, timelines and the risks nobody's watching." },
  { title: "Any complex group plan", body: "Wherever people, money, responsibilities and deadlines collide." },
];
</script>

<template>
  <section
    id="use-cases"
    class="max-w-6xl mx-auto px-5 md:px-8 py-16 md:py-24"
    aria-labelledby="cases-heading"
  >
    <h2
      id="cases-heading"
      class="font-display text-[26px] md:text-[32px] font-semibold tracking-tight"
    >
      Different plans, the same problem
    </h2>
    <p class="mt-3 text-[16px] text-ink-soft max-w-2xl">
      Orchestrio isn't built for one kind of plan. These all share the need to coordinate across people, money,
      responsibilities and deadlines.
    </p>

    <div class="mt-10 grid sm:grid-cols-2 lg:grid-cols-3 gap-px bg-line rounded-xl overflow-hidden border border-line">
      <div
        v-for="c in CASES"
        :key="c.title"
        class="bg-surface p-5"
      >
        <h3 class="text-[15px] font-semibold">
          {{ c.title }}
        </h3>
        <p class="mt-1.5 text-13.5 leading-relaxed text-ink-soft">
          {{ c.body }}
        </p>
      </div>
    </div>
  </section>
</template>
