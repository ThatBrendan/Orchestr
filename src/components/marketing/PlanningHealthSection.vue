<script setup lang="ts">
import SeverityIcon from "@/components/ui/SeverityIcon.vue";

// Illustrative findings — fixed marketing content, scoped to this component.
const CHECKS = [
  { severity: "warning" as const, label: "Missing assignee", detail: "An activity with nobody responsible for it." },
  { severity: "blocker" as const, label: "Overdue payment", detail: "A scheduled payment past its due date." },
  { severity: "warning" as const, label: "Incomplete booking", detail: "Confirmed, but no confirmation reference." },
  { severity: "warning" as const, label: "Overdue activity", detail: "An activity past its due date and still open." },
  { severity: "warning" as const, label: "Budget overrun", detail: "Projected spend above the plan's budget." },
];
</script>

<template>
  <section
    id="features"
    class="bg-surface border-y border-line"
    aria-labelledby="health-heading"
  >
    <div class="max-w-6xl mx-auto px-5 md:px-8 py-16 md:py-24 grid lg:grid-cols-2 gap-10 items-start">
      <div>
        <div class="text-13 font-semibold uppercase tracking-wide text-brand-dark">
          Planning health
        </div>
        <h2
          id="health-heading"
          class="mt-2 font-display text-[26px] md:text-[32px] font-semibold tracking-tight"
        >
          Orchestrio continuously checks your plan for things that need attention.
        </h2>
        <p class="mt-4 text-[16px] leading-relaxed text-ink-soft">
          It's a set of clear, consistent checks — not a black box. When something's missing, overdue or off budget, it
          shows up on the dashboard with a simple explanation and what to do next.
        </p>
        <p class="mt-3 text-13.5 text-muted">
          No AI guesswork. Orchestrio won't make bookings for you or plan the project on its own — it keeps you informed so
          you can.
        </p>
      </div>

      <div class="rounded-xl border border-line bg-paper divide-y divide-line">
        <div
          v-for="c in CHECKS"
          :key="c.label"
          class="flex items-start gap-3 p-4"
        >
          <SeverityIcon :severity="c.severity" />
          <div>
            <div class="text-14 font-medium">
              {{ c.label }}
            </div>
            <div class="text-13 text-ink-soft">
              {{ c.detail }}
            </div>
          </div>
        </div>
      </div>
    </div>
  </section>
</template>
