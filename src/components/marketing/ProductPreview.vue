<script setup lang="ts">
import AppIcon from "@/components/ui/AppIcon.vue";
// Fixed illustration only. No product controls, live data or requests.
</script>

<template>
  <figure class="relative min-w-0">
    <div
      class="absolute -inset-2 sm:-inset-3 rounded-[28px] bg-brand-soft/60 sm:-rotate-2"
      aria-hidden="true"
    />
    <div class="relative rounded-2xl border border-line bg-surface p-4 sm:p-6 shadow-[0_20px_50px_-20px_rgba(31,35,40,0.22)]">
      <div class="flex flex-wrap justify-between gap-2 border-b border-line pb-4 text-13 text-muted">
        <span>Projects <span
          aria-hidden="true"
          class="mx-1"
        >/</span> <span class="text-ink">Summer launch</span></span>
        <span class="text-brand-dark">Illustrative project</span>
      </div>
      <div class="mt-5 flex flex-wrap items-center justify-between gap-3">
        <div>
          <p class="text-xl sm:text-2xl font-bold tracking-tight">
            A launch worth sharing
          </p>
          <p class="mt-1 text-13 text-ink-soft">
            18 June · 5 people, one plan
          </p>
        </div>
        <div
          class="flex -space-x-2"
          aria-label="Project members: Alex, Priya and three others"
        >
          <span
            v-for="(member, i) in ['AL', 'PR', '+3']"
            :key="member"
            class="w-8 h-8 rounded-full border-2 border-surface flex items-center justify-center text-13 font-semibold"
            :class="i === 1 ? 'bg-accent-soft text-accent' : 'bg-brand-soft text-brand-dark'"
            aria-hidden="true"
          >{{ member }}</span>
        </div>
      </div>
      <div
        class="mt-5 flex flex-wrap gap-x-5 gap-y-2 border-b border-line pb-3 text-13 text-ink-soft"
        aria-hidden="true"
      >
        <span class="text-brand font-semibold">Overview</span><span>Activities</span><span>Decisions</span><span>Budget</span><span>People</span>
      </div>
      <div class="mt-4 flex items-start gap-3 rounded-xl border border-amber/20 bg-amber-soft p-3.5">
        <AppIcon
          name="alert"
          :size="20"
          class="text-amber shrink-0 mt-0.5"
        />
        <div>
          <p class="text-13 font-semibold text-amber">
            Needs attention · Due tomorrow
          </p>
          <p class="mt-1 text-sm font-semibold">
            Venue deposit
          </p>
          <p class="mt-1 text-13 text-ink-soft">
            £240 outstanding · Alex is responsible
          </p>
        </div>
      </div>
      <p class="mt-5 mb-3 text-13 font-semibold">
        Coming up in the plan
      </p>
      <div class="space-y-3">
        <div class="flex items-start gap-3 rounded-xl border border-line p-3">
          <div class="rounded-lg bg-brand-soft p-2 text-brand">
            <AppIcon
              name="checkCircle"
              :size="18"
            />
          </div>
          <div class="min-w-0 flex-1">
            <p class="text-sm font-semibold">
              Prepare the launch demo
            </p>
            <p class="mt-1 text-13 text-ink-soft">
              16 Jun · Priya · In progress
            </p>
          </div>
        </div>
        <div class="flex items-start gap-3 rounded-xl border border-line p-3">
          <div class="rounded-lg bg-accent-soft p-2 text-accent">
            <AppIcon
              name="people"
              :size="18"
            />
          </div>
          <div>
            <p class="text-sm font-semibold">
              Choose the event format
            </p>
            <p class="mt-1 text-13 text-ink-soft">
              Decision · 4 of 5 people voted
            </p>
          </div>
        </div>
      </div>
      <div class="mt-5 pt-4 border-t border-line flex flex-wrap justify-between gap-3 text-13">
        <span class="text-ink-soft">Budget <strong class="text-ink">£2,000</strong></span>
        <span class="text-accent font-semibold">6 of 10 Activities complete</span>
      </div>
      <div
        class="mt-3 h-1.5 rounded-full bg-accent-soft"
        aria-hidden="true"
      >
        <div class="h-full w-3/5 rounded-full bg-accent" />
      </div>
    </div>
    <figcaption class="relative mt-5 text-center text-13 text-muted">
      The people, the details, the next step. Together.
    </figcaption>
  </figure>
</template>
